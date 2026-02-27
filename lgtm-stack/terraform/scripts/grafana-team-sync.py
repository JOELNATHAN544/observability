"""
grafana-team-sync.py — Dynamic Keycloak -> Grafana Multi-Tenant Sync

This script treats Keycloak groups as the source of truth and reconciles Grafana
state every run.

What it does:
  1. Discover all `<tenant><suffix>` groups from Keycloak (default suffix: -team)
  2. For each tenant:
       a. Ensure a dedicated Grafana Organization exists
       b. Ensure a Grafana Team exists in that tenant organization
       c. Ensure tenant-scoped datasources exist in that organization
       d. Ensure shared default datasources (Loki/Mimir/Tempo) also exist
       e. Ensure a tenant folder exists and is restricted to that team
  3. Sync users from Keycloak group membership into Grafana org + team
  4. Update Loki gateway htpasswd Secret for tenant read isolation

Notes:
  - Users who have never logged into Grafana cannot be mapped yet (no Grafana UID).
  - Per-tenant organizations are used for OSS-safe datasource isolation.
"""

import os
import sys
import secrets
import string
import logging
import requests


# --------------------------------------------------------------------
# Logging
# --------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)
log = logging.getLogger(__name__)


# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------
def _require(name: str) -> str:
    value = os.getenv(name)
    if not value:
        log.error("Required env var %s is missing.", name)
        sys.exit(1)
    return value


# Keycloak
KEYCLOAK_URL = os.getenv("KEYCLOAK_URL", "").rstrip("/")
KEYCLOAK_REALM = os.getenv("KEYCLOAK_REALM", "")
KEYCLOAK_CLIENT_ID = os.getenv("KEYCLOAK_CLIENT_ID", "admin-cli")
KEYCLOAK_USERNAME = os.getenv("KEYCLOAK_USERNAME", "")
KEYCLOAK_PASSWORD = os.getenv("KEYCLOAK_PASSWORD", "")

if not all([KEYCLOAK_URL, KEYCLOAK_REALM, KEYCLOAK_USERNAME, KEYCLOAK_PASSWORD]):
    log.error("KEYCLOAK_URL, KEYCLOAK_REALM, KEYCLOAK_USERNAME, KEYCLOAK_PASSWORD are all required.")
    sys.exit(1)

# Grafana
GRAFANA_URL = os.getenv("GRAFANA_URL", "http://monitoring-grafana.observability.svc.cluster.local:80").rstrip("/")
GRAFANA_ADMIN_USER = "admin"
GRAFANA_ADMIN_PASSWORD = _require("GRAFANA_ADMIN_PASSWORD")

# Backend service URLs (in-cluster defaults)
LOKI_GATEWAY_URL = os.getenv("LOKI_GATEWAY_URL", "http://monitoring-loki-gateway.observability.svc.cluster.local:80")
MIMIR_URL = os.getenv("MIMIR_URL", "http://monitoring-mimir-nginx.observability.svc.cluster.local:80/prometheus")
TEMPO_URL = os.getenv("TEMPO_URL", "http://monitoring-tempo-query-frontend.observability.svc.cluster.local:3200")

# Kubernetes
K8S_NAMESPACE = os.getenv("K8S_NAMESPACE", "observability")
HTPASSWD_SECRET_NAME = "loki-tenant-htpasswd"
TENANT_PASSWORDS_SECRET = "grafana-tenant-passwords"
GLOBAL_SCOPE_TENANT = os.getenv("GLOBAL_SCOPE_TENANT", "default")

# Group discovery
TENANT_GROUP_SUFFIX = os.getenv("TENANT_GROUP_SUFFIX", "-team")
KEYCLOAK_GRAFANA_ADMIN_ROLE = os.getenv("KEYCLOAK_GRAFANA_ADMIN_ROLE", "grafana-admin")
KEYCLOAK_GRAFANA_EDITOR_ROLE = os.getenv("KEYCLOAK_GRAFANA_EDITOR_ROLE", "grafana-editor")
KEYCLOAK_GRAFANA_VIEWER_ROLE = os.getenv("KEYCLOAK_GRAFANA_VIEWER_ROLE", "grafana-viewer")
REMOVE_USERS_FROM_MAIN_ORG = os.getenv("REMOVE_USERS_FROM_MAIN_ORG", "true").lower() in {"1", "true", "yes"}
GRAFANA_MAIN_ORG_ID = int(os.getenv("GRAFANA_MAIN_ORG_ID", "1"))
SET_CURRENT_ORG_ON_SYNC = os.getenv("SET_CURRENT_ORG_ON_SYNC", "false").lower() in {"1", "true", "yes"}

log.info(
    "Configuration: Keycloak realm=%s, tenant suffix=%s, global tenant=%s, set_current_org=%s",
    KEYCLOAK_REALM,
    TENANT_GROUP_SUFFIX,
    GLOBAL_SCOPE_TENANT,
    SET_CURRENT_ORG_ON_SYNC,
)


# --------------------------------------------------------------------
# Kubernetes helpers
# --------------------------------------------------------------------
def _get_k8s_client():
    try:
        from kubernetes import client, config
        config.load_incluster_config()
        return client.CoreV1Api()
    except Exception as exc:
        log.warning("Could not load Kubernetes client: %s. Secret management will be skipped.", exc)
        return None


def k8s_get_secret_data(v1, secret_name: str) -> dict:
    """Return decoded Secret data, or {} when missing."""
    import base64
    try:
        secret = v1.read_namespaced_secret(name=secret_name, namespace=K8S_NAMESPACE)
        raw = secret.data or {}
        return {k: base64.b64decode(v).decode() for k, v in raw.items()}
    except Exception:
        return {}


def k8s_patch_secret(v1, secret_name: str, new_data: dict):
    """Patch an existing Secret, creating it when absent."""
    from kubernetes import client as k8s_client
    body = k8s_client.V1Secret(
        metadata=k8s_client.V1ObjectMeta(name=secret_name, namespace=K8S_NAMESPACE),
        string_data=new_data,
    )
    try:
        v1.patch_namespaced_secret(name=secret_name, namespace=K8S_NAMESPACE, body=body)
        log.info("Patched Secret '%s'", secret_name)
    except Exception:
        try:
            v1.create_namespaced_secret(namespace=K8S_NAMESPACE, body=body)
            log.info("Created Secret '%s'", secret_name)
        except Exception as exc:
            log.error("Failed to create/patch Secret '%s': %s", secret_name, exc)


# --------------------------------------------------------------------
# Password helpers
# --------------------------------------------------------------------
def generate_password(length: int = 32) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def make_htpasswd_entry(username: str, password: str) -> str:
    """Return one htpasswd line for username/password."""
    try:
        from passlib.hash import bcrypt as passlib_bcrypt
        hashed = passlib_bcrypt.using(rounds=12).hash(password)
    except Exception as exc:
        # passlib+bcrypt can fail at runtime with some bcrypt releases.
        log.warning(
            "passlib bcrypt failed for user '%s': %s; falling back to sha512-crypt.",
            username,
            exc,
        )
        import crypt
        hashed = crypt.crypt(password, crypt.mksalt(crypt.METHOD_SHA512))
    return f"{username}:{hashed}"


def get_or_create_tenant_passwords(v1, tenants: list[str]) -> dict[str, str]:
    """
    Return stable {tenant: password}.
    Missing tenants get generated passwords persisted to Secret.
    """
    if v1 is None:
        log.warning("No K8s client: generating ephemeral passwords; htpasswd will not be updated.")
        return {tenant: generate_password() for tenant in tenants}

    existing = k8s_get_secret_data(v1, TENANT_PASSWORDS_SECRET)
    updated = False

    for tenant in tenants:
        if tenant not in existing:
            existing[tenant] = generate_password()
            updated = True
            log.info("Generated password for tenant '%s'", tenant)

    if updated:
        k8s_patch_secret(v1, TENANT_PASSWORDS_SECRET, existing)

    return {tenant: existing[tenant] for tenant in tenants if tenant in existing}


def update_loki_htpasswd(v1, tenant_passwords: dict[str, str]):
    """Write all tenant credentials into Loki gateway htpasswd Secret."""
    if v1 is None:
        log.warning("No K8s client: skipping Loki htpasswd Secret update.")
        return

    entries = [make_htpasswd_entry(tenant, password) for tenant, password in tenant_passwords.items()]
    k8s_patch_secret(v1, HTPASSWD_SECRET_NAME, {".htpasswd": "\n".join(entries)})
    log.info("Updated Loki htpasswd with %d tenant(s)", len(tenant_passwords))


# --------------------------------------------------------------------
# Keycloak helpers
# --------------------------------------------------------------------
def get_keycloak_admin_token() -> str:
    """Authenticate against Keycloak and return an admin token."""
    for realm in ["master", KEYCLOAK_REALM]:
        url = f"{KEYCLOAK_URL}/realms/{realm}/protocol/openid-connect/token"
        try:
            resp = requests.post(
                url,
                data={
                    "client_id": KEYCLOAK_CLIENT_ID,
                    "username": KEYCLOAK_USERNAME,
                    "password": KEYCLOAK_PASSWORD,
                    "grant_type": "password",
                },
                timeout=20,
            )
            resp.raise_for_status()
            log.info("Authenticated to Keycloak via realm '%s'", realm)
            return resp.json()["access_token"]
        except requests.RequestException as exc:
            log.warning("Keycloak auth via realm '%s' failed: %s", realm, exc)

    log.error("All Keycloak authentication attempts failed.")
    sys.exit(1)


def discover_tenant_groups(token: str) -> list[str]:
    """
    Return tenant names discovered from Keycloak groups.
    Group '<tenant><suffix>' -> tenant '<tenant>'.
    """
    url = f"{KEYCLOAK_URL}/admin/realms/{KEYCLOAK_REALM}/groups"
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.get(url, headers=headers, params={"max": 500}, timeout=20)
    resp.raise_for_status()

    tenants = []
    for group in resp.json():
        name = group.get("name", "")
        if name.endswith(TENANT_GROUP_SUFFIX) and name != TENANT_GROUP_SUFFIX:
            tenant = name[: -len(TENANT_GROUP_SUFFIX)]
            tenants.append(tenant)
            log.info("Discovered tenant group '%s' -> tenant '%s'", name, tenant)

    if not tenants:
        log.warning("No tenant groups found with suffix '%s'.", TENANT_GROUP_SUFFIX)
    return sorted(set(tenants))


def get_keycloak_group_id(token: str, group_name: str) -> str | None:
    url = f"{KEYCLOAK_URL}/admin/realms/{KEYCLOAK_REALM}/groups"
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.get(url, headers=headers, params={"search": group_name, "exact": "true"}, timeout=20)
    resp.raise_for_status()
    for group in resp.json():
        if group.get("name") == group_name:
            return group.get("id")
    return None


def get_keycloak_group_members(token: str, group_id: str) -> list[dict]:
    """
    Return Keycloak group members as dicts: {id, username, email}.
    Users without email are ignored to keep sync deterministic.
    """
    url = f"{KEYCLOAK_URL}/admin/realms/{KEYCLOAK_REALM}/groups/{group_id}/members"
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.get(url, headers=headers, params={"max": -1}, timeout=20)
    resp.raise_for_status()

    members = []
    for member in resp.json():
        email = member.get("email")
        if not email:
            continue
        members.append({
            "id": member.get("id"),
            "username": member.get("username"),
            "email": email.strip().lower(),
        })
    return members


def get_keycloak_user_realm_roles(token: str, user_id: str | None) -> set[str]:
    """Return a user's effective Keycloak realm role names."""
    if not user_id:
        return set()
    url = f"{KEYCLOAK_URL}/admin/realms/{KEYCLOAK_REALM}/users/{user_id}/role-mappings/realm/composite"
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.get(url, headers=headers, timeout=20)
    resp.raise_for_status()
    return {role.get("name", "") for role in resp.json() if role.get("name")}


def map_grafana_role_from_keycloak_roles(roles: set[str]) -> str:
    """
    Map Keycloak realm roles to Grafana org roles.
    Admin > Editor > Viewer precedence.
    """
    if KEYCLOAK_GRAFANA_ADMIN_ROLE in roles:
        return "Admin"
    if KEYCLOAK_GRAFANA_EDITOR_ROLE in roles:
        return "Editor"
    if KEYCLOAK_GRAFANA_VIEWER_ROLE in roles:
        return "Viewer"
    return "Viewer"


# --------------------------------------------------------------------
# Grafana HTTP helpers
# --------------------------------------------------------------------
def _grafana_auth():
    return GRAFANA_ADMIN_USER, GRAFANA_ADMIN_PASSWORD


def grafana_request(
    method: str,
    path: str,
    params: dict | None = None,
    payload: dict | None = None,
    org_id: int | None = None,
    allow_status: set[int] | None = None,
):
    headers = {}
    if org_id is not None:
        headers["X-Grafana-Org-Id"] = str(org_id)

    resp = requests.request(
        method=method,
        url=f"{GRAFANA_URL}{path}",
        auth=_grafana_auth(),
        headers=headers,
        params=params,
        json=payload,
        timeout=20,
    )

    if allow_status and resp.status_code in allow_status:
        return resp

    resp.raise_for_status()
    return resp


def grafana_get_json(path: str, params: dict | None = None, org_id: int | None = None):
    return grafana_request("GET", path, params=params, org_id=org_id).json()


# --------------------------------------------------------------------
# Grafana identity helpers
# --------------------------------------------------------------------
def get_grafana_user_id_by_email(email: str) -> int | None:
    resp = grafana_request("GET", "/api/users/lookup", params={"loginOrEmail": email}, allow_status={404})
    if resp.status_code == 404:
        return None
    return resp.json().get("id")


def ensure_grafana_user(member: dict) -> int | None:
    """
    Ensure a Grafana user exists for a Keycloak member.
    Returns the Grafana user ID or None when user creation cannot be completed.
    """
    email = (member.get("email") or "").strip().lower()
    username = (member.get("username") or "").strip()
    if not email:
        return None
    if not username:
        username = email.split("@")[0]

    existing_id = get_grafana_user_id_by_email(email)
    if existing_id:
        return existing_id

    payload = {
        "name": username,
        "email": email,
        "login": username,
        "password": generate_password(24),
    }

    resp = grafana_request("POST", "/api/admin/users", payload=payload, allow_status={400, 409, 412})
    if resp.status_code in (409, 412):
        # User may already exist by username/login conflict.
        return get_grafana_user_id_by_email(email) or get_grafana_user_id_by_email(username)

    if resp.status_code == 400:
        log.warning("Failed creating Grafana user for %s: %s", email, resp.text)
        return get_grafana_user_id_by_email(email)

    created_id = get_grafana_user_id_by_email(email)
    if created_id:
        log.info("Created Grafana user for %s (id=%s)", email, created_id)
    return created_id


def get_grafana_admin_user_id() -> int | None:
    for lookup in ["admin@localhost", GRAFANA_ADMIN_USER]:
        uid = get_grafana_user_id_by_email(lookup)
        if uid:
            return uid
    return None


# --------------------------------------------------------------------
# Grafana organization helpers
# --------------------------------------------------------------------
def tenant_name_to_org_name(tenant: str) -> str:
    return f"{tenant}{TENANT_GROUP_SUFFIX}"


def ensure_grafana_org(tenant: str) -> int:
    org_name = tenant_name_to_org_name(tenant)
    encoded = requests.utils.quote(org_name, safe="")

    existing = grafana_request("GET", f"/api/orgs/name/{encoded}", allow_status={404})
    if existing.status_code != 404:
        org_id = existing.json()["id"]
        log.info("Org '%s' already exists (id=%s)", org_name, org_id)
        return org_id

    created = grafana_request("POST", "/api/orgs", payload={"name": org_name}, allow_status={409})
    if created.status_code != 409:
        payload = created.json()
        org_id = payload.get("orgId") or payload.get("id")
        if org_id:
            log.info("Created Org '%s' (id=%s)", org_name, org_id)
            return int(org_id)

    # Race condition fallback
    fetched = grafana_request("GET", f"/api/orgs/name/{encoded}")
    org_id = fetched.json()["id"]
    log.info("Org '%s' resolved after create race (id=%s)", org_name, org_id)
    return org_id


def get_org_users(org_id: int) -> list[dict]:
    return grafana_get_json(f"/api/orgs/{org_id}/users")


def add_user_to_org(org_id: int, login_or_email: str, role: str = "Viewer"):
    resp = grafana_request(
        "POST",
        f"/api/orgs/{org_id}/users",
        payload={"loginOrEmail": login_or_email, "role": role},
        allow_status={409},
    )
    if resp.status_code == 409:
        return


def remove_user_from_org(org_id: int, user_id: int):
    grafana_request("DELETE", f"/api/orgs/{org_id}/users/{user_id}", allow_status={404})


def ensure_user_role_in_org(org_id: int, user_id: int, login_or_email: str, desired_role: str):
    """
    Ensure user's role in org matches desired_role.
    Some Grafana versions reject PATCH for externally synced users;
    in that case, re-create org membership with the desired role.
    """
    users = get_org_users(org_id)
    current = next((user for user in users if user.get("userId") == user_id), None)
    if not current:
        add_user_to_org(org_id, login_or_email, role=desired_role)
        return

    current_role = current.get("role")
    if current_role == desired_role:
        return

    resp = grafana_request(
        "PATCH",
        f"/api/orgs/{org_id}/users/{user_id}",
        payload={"role": desired_role},
        allow_status={403},
    )
    if resp.status_code != 403:
        log.info("Updated role for user_id=%s in org %s: %s -> %s", user_id, org_id, current_role, desired_role)
        return

    log.info(
        "PATCH role update blocked for user_id=%s in org %s; re-creating membership as %s",
        user_id,
        org_id,
        desired_role,
    )
    remove_user_from_org(org_id, user_id)
    add_user_to_org(org_id, login_or_email, role=desired_role)


def set_user_current_org(user_id: int, org_id: int):
    # Best-effort UX improvement so users land in their tenant org.
    resp = grafana_request(
        "POST",
        f"/api/users/{user_id}/using/{org_id}",
        allow_status={404, 412},
    )
    if resp.status_code in (404, 412):
        log.debug("Could not set current org for user %s to %s: %s", user_id, org_id, resp.status_code)


# --------------------------------------------------------------------
# Grafana team helpers (org-scoped)
# --------------------------------------------------------------------
def ensure_grafana_team(tenant: str, org_id: int) -> int:
    team_name = f"{tenant}{TENANT_GROUP_SUFFIX}"
    results = grafana_get_json("/api/teams/search", {"name": team_name}, org_id=org_id).get("teams", [])
    for team in results:
        if team.get("name") == team_name:
            log.info("Team '%s' already exists in org %s (id=%s)", team_name, org_id, team["id"])
            return team["id"]

    created = grafana_request("POST", "/api/teams", payload={"name": team_name}, org_id=org_id, allow_status={409})
    if created.status_code != 409:
        team_id = created.json()["teamId"]
        log.info("Created Team '%s' in org %s (id=%s)", team_name, org_id, team_id)
        return team_id

    # Race condition fallback
    results = grafana_get_json("/api/teams/search", {"name": team_name}, org_id=org_id).get("teams", [])
    for team in results:
        if team.get("name") == team_name:
            return team["id"]
    raise RuntimeError(f"Failed to resolve team '{team_name}' in org {org_id}")


def get_grafana_team_members(team_id: int, org_id: int) -> list[int]:
    members = grafana_get_json(f"/api/teams/{team_id}/members", org_id=org_id)
    return [member["userId"] for member in members if "userId" in member]


def add_user_to_grafana_team(team_id: int, user_id: int, org_id: int):
    resp = grafana_request(
        "POST",
        f"/api/teams/{team_id}/members",
        payload={"userId": user_id},
        org_id=org_id,
        allow_status={400, 409},
    )
    if resp.status_code == 409:
        return
    if resp.status_code == 400:
        message = ""
        try:
            message = str(resp.json().get("message", "")).lower()
        except ValueError:
            message = resp.text.lower()
        if "already added" in message:
            return
        resp.raise_for_status()


def remove_user_from_grafana_team(team_id: int, user_id: int, org_id: int):
    grafana_request("DELETE", f"/api/teams/{team_id}/members/{user_id}", org_id=org_id)


# --------------------------------------------------------------------
# Datasource helpers (org-scoped)
# --------------------------------------------------------------------
def _datasource_exists(name: str, org_id: int) -> bool:
    encoded = requests.utils.quote(name, safe="")
    resp = grafana_request("GET", f"/api/datasources/name/{encoded}", org_id=org_id, allow_status={404})
    return resp.status_code != 404


def _create_datasource(payload: dict, org_id: int):
    resp = grafana_request("POST", "/api/datasources", payload=payload, org_id=org_id, allow_status={409})
    if resp.status_code == 409:
        log.info("Datasource '%s' already exists in org %s (409)", payload["name"], org_id)
        return
    log.info("Created datasource '%s' in org %s", payload["name"], org_id)


def ensure_grafana_datasources(tenant: str, password: str, global_password: str, org_id: int):
    """
    Ensure both tenant-scoped and shared default datasources exist in a tenant organization.
    Creates 6 datasources:
      - Tenant: <Tenant>-Loki, <Tenant>-Mimir, <Tenant>-Tempo
      - Shared: Loki, Mimir, Tempo
    """
    title = tenant.title()

    def ds_base(
        name: str,
        ds_type: str,
        url: str,
        json_data: dict,
        scope_org: str,
        basic_user: str | None = None,
        basic_password: str | None = None,
    ) -> dict:
        payload = {
            "name": name,
            "type": ds_type,
            "url": url,
            "access": "proxy",
            "secureJsonData": {
                "httpHeaderValue1": scope_org,
            },
            "jsonData": {
                **json_data,
                "httpHeaderName1": "X-Scope-OrgID",
            },
        }
        if basic_user and basic_password:
            payload["basicAuth"] = True
            payload["basicAuthUser"] = basic_user
            payload["secureJsonData"]["basicAuthPassword"] = basic_password
        return payload

    datasources = [
        # Tenant-scoped datasources
        ds_base(
            f"{title}-Loki",
            "loki",
            LOKI_GATEWAY_URL,
            {"maxLines": 1000},
            tenant,
            basic_user=tenant,
            basic_password=password,
        ),
        ds_base(
            f"{title}-Mimir",
            "prometheus",
            MIMIR_URL,
            {"httpMethod": "POST", "timeInterval": "15s"},
            tenant,
        ),
        ds_base(
            f"{title}-Tempo",
            "tempo",
            TEMPO_URL,
            {"httpMethod": "GET"},
            tenant,
        ),
        # Shared default datasources visible to all tenant orgs
        ds_base(
            "Loki",
            "loki",
            LOKI_GATEWAY_URL,
            {"maxLines": 1000},
            GLOBAL_SCOPE_TENANT,
            basic_user=GLOBAL_SCOPE_TENANT,
            basic_password=global_password,
        ),
        ds_base(
            "Mimir",
            "prometheus",
            MIMIR_URL,
            {"httpMethod": "POST", "timeInterval": "15s"},
            GLOBAL_SCOPE_TENANT,
        ),
        ds_base(
            "Tempo",
            "tempo",
            TEMPO_URL,
            {"httpMethod": "GET"},
            GLOBAL_SCOPE_TENANT,
        ),
    ]

    for datasource in datasources:
        if _datasource_exists(datasource["name"], org_id):
            log.info("Datasource '%s' already exists in org %s", datasource["name"], org_id)
            continue
        _create_datasource(datasource, org_id)


# --------------------------------------------------------------------
# Folder helpers (org-scoped)
# --------------------------------------------------------------------
def ensure_grafana_folder(tenant: str, org_id: int) -> str:
    folder_title = f"{tenant.title()} Dashboards"
    folder_uid = f"{tenant}-dashboards"

    folders = grafana_get_json("/api/folders", org_id=org_id)
    for folder in folders:
        if folder.get("uid") == folder_uid or folder.get("title") == folder_title:
            log.info("Folder '%s' already exists in org %s (uid=%s)", folder_title, org_id, folder["uid"])
            return folder["uid"]

    resp = grafana_request(
        "POST",
        "/api/folders",
        payload={"uid": folder_uid, "title": folder_title},
        org_id=org_id,
        allow_status={409},
    )
    if resp.status_code == 409:
        log.info("Folder '%s' already exists in org %s (409)", folder_title, org_id)
        return folder_uid

    log.info("Created folder '%s' in org %s (uid=%s)", folder_title, org_id, folder_uid)
    return folder_uid


def ensure_folder_permission(folder_uid: str, team_id: int, org_id: int):
    path = f"/api/folders/{folder_uid}/permissions"
    payload = {
        "items": [
            {
                "teamId": team_id,
                "permission": 2,  # 1=View 2=Edit 4=Admin
            }
        ]
    }

    resp = grafana_request("POST", path, payload=payload, org_id=org_id, allow_status={404, 405})
    if resp.status_code in (404, 405):
        # Some Grafana versions only support PUT here.
        grafana_request("PUT", path, payload=payload, org_id=org_id)
    log.info("Set folder permission in org %s for team_id=%s on folder '%s'", org_id, team_id, folder_uid)


# --------------------------------------------------------------------
# Tenant reconciliation
# --------------------------------------------------------------------
def provision_tenant(tenant: str, password: str, global_password: str) -> tuple[int, int]:
    """Create/ensure Org + Team + Datasources + Folder for a tenant."""
    log.info("=== Provisioning tenant '%s' ===", tenant)
    org_id = ensure_grafana_org(tenant)
    team_id = ensure_grafana_team(tenant, org_id)
    ensure_grafana_datasources(tenant, password, global_password, org_id)
    folder_uid = ensure_grafana_folder(tenant, org_id)
    ensure_folder_permission(folder_uid, team_id, org_id)
    return org_id, team_id


def sync_tenant_users(tenant: str, org_id: int, team_id: int, kc_members: list[dict], kc_token: str):
    """Sync Keycloak group members -> Grafana org members + team members."""
    team_name = f"{tenant}{TENANT_GROUP_SUFFIX}"
    desired_members = {
        member["email"]: member
        for member in kc_members
        if member.get("email")
    }
    desired_emails = sorted(desired_members.keys())

    log.info("--- Syncing users for tenant '%s' (org=%s, team=%s) ---", tenant, org_id, team_id)
    log.info("Keycloak group '%s' has %d member(s): %s", team_name, len(desired_emails), desired_emails)

    protected_ids = {1}
    admin_id = get_grafana_admin_user_id()
    if admin_id:
        protected_ids.add(admin_id)

    desired_user_ids: list[int] = []

    for email in desired_emails:
        member = desired_members[email]
        user_id = ensure_grafana_user(member)
        if not user_id:
            log.warning("User %s could not be reconciled in Grafana; skipping.", email)
            continue

        desired_user_ids.append(user_id)
        kc_roles = get_keycloak_user_realm_roles(kc_token, member.get("id"))
        desired_role = map_grafana_role_from_keycloak_roles(kc_roles)

        try:
            ensure_user_role_in_org(org_id, user_id, email, desired_role)
            # Keep this optional so users with multi-org membership can choose
            # their preferred org in Grafana UI without sync overriding it.
            if SET_CURRENT_ORG_ON_SYNC:
                set_user_current_org(user_id, org_id)
            if REMOVE_USERS_FROM_MAIN_ORG and desired_role != "Admin" and org_id != GRAFANA_MAIN_ORG_ID:
                remove_user_from_org(GRAFANA_MAIN_ORG_ID, user_id)
        except Exception as exc:
            log.error("Failed adding user %s to org %s: %s", email, org_id, exc)

        try:
            add_user_to_grafana_team(team_id, user_id, org_id)
        except Exception as exc:
            log.error("Failed adding user %s to team %s: %s", email, team_id, exc)

    # Remove stale team memberships
    current_team_ids = get_grafana_team_members(team_id, org_id)
    for user_id in current_team_ids:
        if user_id in protected_ids:
            continue
        if user_id not in desired_user_ids:
            log.info("Removing stale team member user_id=%s from team '%s'", user_id, team_name)
            try:
                remove_user_from_grafana_team(team_id, user_id, org_id)
            except Exception as exc:
                log.error("Failed removing user %s from team %s: %s", user_id, team_id, exc)

    # Remove stale org memberships
    current_org_users = get_org_users(org_id)
    for user in current_org_users:
        user_id = user.get("userId")
        if not user_id or user_id in protected_ids:
            continue
        if user_id not in desired_user_ids:
            log.info("Removing stale org member user_id=%s from org '%s'", user_id, org_id)
            try:
                remove_user_from_org(org_id, user_id)
            except Exception as exc:
                log.error("Failed removing user %s from org %s: %s", user_id, org_id, exc)

    log.info("User sync complete for tenant '%s'", tenant)


# --------------------------------------------------------------------
# Main
# --------------------------------------------------------------------
def main():
    log.info("=" * 60)
    log.info("Starting Keycloak -> Grafana tenant sync job")
    log.info("=" * 60)

    kc_token = get_keycloak_admin_token()
    tenants = discover_tenant_groups(kc_token)
    if not tenants:
        log.info("No tenants discovered; exiting.")
        return

    log.info("Discovered %d tenant(s): %s", len(tenants), tenants)

    v1 = _get_k8s_client()
    all_scopes = sorted(set(tenants + [GLOBAL_SCOPE_TENANT]))
    tenant_passwords = get_or_create_tenant_passwords(v1, all_scopes)
    global_password = tenant_passwords.get(GLOBAL_SCOPE_TENANT)
    if not global_password:
        log.error("No password available for global scope tenant '%s'; exiting.", GLOBAL_SCOPE_TENANT)
        return

    tenant_members: dict[str, list[dict]] = {}
    for tenant in tenants:
        group_name = f"{tenant}{TENANT_GROUP_SUFFIX}"
        group_id = get_keycloak_group_id(kc_token, group_name)
        if not group_id:
            log.warning("Keycloak group '%s' not found; using empty membership.", group_name)
            tenant_members[tenant] = []
            continue
        tenant_members[tenant] = get_keycloak_group_members(kc_token, group_id)

    provisioned: dict[str, dict[str, int]] = {}

    for tenant in tenants:
        password = tenant_passwords.get(tenant)
        if not password:
            log.error("No password available for tenant '%s'; skipping provisioning.", tenant)
            continue
        try:
            org_id, team_id = provision_tenant(tenant, password, global_password)
            provisioned[tenant] = {"org_id": org_id, "team_id": team_id}
        except Exception as exc:
            log.error("Provisioning failed for tenant '%s': %s", tenant, exc, exc_info=True)

    for tenant, ids in provisioned.items():
        try:
                sync_tenant_users(
                    tenant=tenant,
                    org_id=ids["org_id"],
                    team_id=ids["team_id"],
                    kc_members=tenant_members.get(tenant, []),
                    kc_token=kc_token,
                )
        except Exception as exc:
            log.error("User sync failed for tenant '%s': %s", tenant, exc, exc_info=True)

    active_passwords = {tenant: tenant_passwords[tenant] for tenant in provisioned if tenant in tenant_passwords}
    active_passwords[GLOBAL_SCOPE_TENANT] = global_password
    update_loki_htpasswd(v1, active_passwords)

    log.info("=" * 60)
    log.info("Sync job completed")
    log.info("=" * 60)


if __name__ == "__main__":
    main()
