# =============================================================================
# KEYCLOAK OIDC CONFIGURATION (Comprehensive)
# Supports both Client Authentication and PKCE flows
# Implements full group-based RBAC as per official documentation
# =============================================================================

# =============================================================================
# SECTION 1: KEYCLOAK REALM SETUP
# =============================================================================

resource "keycloak_realm" "argocd" {
  count   = var.deploy_hub && var.enable_keycloak ? 1 : 0
  realm   = var.keycloak_realm
  enabled = true
}

# =============================================================================
# SECTION 2: KEYCLOAK CLIENT (Client Authentication Flow)
# =============================================================================

# Main ArgoCD OIDC Client with Client Authentication (Confidential)
resource "keycloak_openid_client" "argocd" {
  count = var.deploy_hub && var.enable_keycloak && !var.keycloak_enable_pkce ? 1 : 0

  realm_id                     = keycloak_realm.argocd[0].id
  client_id                    = var.keycloak_client_id
  name                         = "ArgoCD OIDC Client (Client Authentication)"
  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = true
  implicit_flow_enabled        = false

  # Redirect URIs for callback
  valid_redirect_uris = concat(
    [
      "${var.argocd_url}/auth/callback",
      "${var.argocd_url}/*",
    ],
    var.keycloak_enable_pkce ? [
      "http://localhost:8085/auth/callback", # For CLI with --sso
    ] : []
  )

  # Logout configuration
  valid_post_logout_redirect_uris = [
    "${var.argocd_url}/applications",
    "${var.argocd_url}/*",
  ]

  # Web origins for CORS
  web_origins = [
    var.argocd_host,
    var.argocd_url,
  ]

  # Client URLs
  root_url  = var.argocd_url
  admin_url = var.argocd_url

  access_token_lifespan = 3600 # 1 hour

  # Security settings
  pkce_code_challenge_method               = var.keycloak_enable_pkce ? "S256" : null
  exclude_session_state_from_auth_response = false

  depends_on = [keycloak_realm.argocd]
}

# PKCE Client (Public Flow, for CLI authentication)
resource "keycloak_openid_client" "argocd_pkce" {
  count = var.deploy_hub && var.enable_keycloak && var.keycloak_enable_pkce ? 1 : 0

  realm_id              = keycloak_realm.argocd[0].id
  client_id             = var.keycloak_client_id
  name                  = "ArgoCD OIDC Client (PKCE)"
  enabled               = true
  access_type           = "PUBLIC" # PKCE is public (no client secret)
  standard_flow_enabled = true
  implicit_flow_enabled = false

  # Redirect URIs for callback (PKCE)
  valid_redirect_uris = [
    "http://localhost:8085/auth/callback", # For CLI with --sso
    "${var.argocd_url}/auth/callback",
    "${var.argocd_url}/*",
  ]

  # Logout configuration
  valid_post_logout_redirect_uris = [
    "${var.argocd_url}/applications",
    "${var.argocd_url}/*",
  ]

  # Web origins for CORS
  web_origins = [
    var.argocd_host,
    var.argocd_url,
  ]

  # Client URLs
  root_url  = var.argocd_url
  admin_url = var.argocd_url

  access_token_lifespan = 3600 # 1 hour

  # PKCE Configuration
  pkce_code_challenge_method = "S256"

  depends_on = [keycloak_realm.argocd]
}

# =============================================================================
# SECTION 3: DEFAULT SCOPES (openid, profile, email)
# =============================================================================

# =============================================================================
# SECTION 4: GROUP MANAGEMENT
# =============================================================================

# Groups Client Scope - Required for group claim in token
resource "keycloak_openid_client_scope" "groups" {
  count                  = var.deploy_hub && var.enable_keycloak ? 1 : 0
  realm_id               = keycloak_realm.argocd[0].id
  name                   = "groups"
  description            = "Group membership claim for ArgoCD authorization"
  include_in_token_scope = true
}

# Group Membership Protocol Mapper
# Maps Keycloak groups to "groups" claim in token
resource "keycloak_openid_group_membership_protocol_mapper" "groups_mapper" {
  count = var.deploy_hub && var.enable_keycloak ? 1 : 0

  realm_id        = keycloak_realm.argocd[0].id
  client_scope_id = keycloak_openid_client_scope.groups[0].id
  name            = "group-membership"
  claim_name      = "groups"
  full_path       = false # Return group name only, not full path
}

# Add groups scope to client default scopes
# Per ArgoCD docs: "Click on "Add client scope", choose the groups scope and add it 
# either to the Default or to the Optional Client Scope. If you put it in the Optional 
# category you will need to make sure that ArgoCD requests the scope in its OIDC configuration."
resource "keycloak_openid_client_default_scopes" "argocd" {
  count = var.deploy_hub && var.enable_keycloak ? 1 : 0

  realm_id  = keycloak_realm.argocd[0].id
  client_id = var.keycloak_enable_pkce ? keycloak_openid_client.argocd_pkce[0].id : keycloak_openid_client.argocd[0].id

  default_scopes = [
    "acr",
    "email",
    "openid",
    "profile",
    "roles",
    "web-origins",
    "groups",
  ]

  depends_on = [
    keycloak_openid_client_scope.groups,
    keycloak_openid_group_membership_protocol_mapper.groups_mapper
  ]
}

# Create default ArgoCD admin group
resource "keycloak_group" "argocd_admins" {
  count    = var.deploy_hub && var.enable_keycloak ? 1 : 0
  realm_id = keycloak_realm.argocd[0].id
  name     = "ArgoCDAdmins"
}

resource "keycloak_group" "argocd_developers" {
  count    = var.deploy_hub && var.enable_keycloak ? 1 : 0
  realm_id = keycloak_realm.argocd[0].id
  name     = "ArgoCDDevelopers"
}

resource "keycloak_group" "argocd_viewers" {
  count    = var.deploy_hub && var.enable_keycloak ? 1 : 0
  realm_id = keycloak_realm.argocd[0].id
  name     = "ArgoCDViewers"
}

# =============================================================================
# SECTION 4.5: DEFAULT KEYCLOAK ADMIN USER
# =============================================================================

# Create default admin user for initial ArgoCD access
resource "keycloak_user" "argocd_admin" {
  count      = var.deploy_hub && var.enable_keycloak && var.create_default_admin_user ? 1 : 0
  realm_id   = keycloak_realm.argocd[0].id
  username   = var.default_admin_username
  enabled    = true
  email      = var.default_admin_email
  first_name = "ArgoCD"
  last_name  = "Administrator"

  initial_password {
    value     = var.default_admin_password
    temporary = var.default_admin_password_temporary
  }
}

# Add admin user to ArgoCDAdmins group
resource "keycloak_user_groups" "argocd_admin_groups" {
  count    = var.deploy_hub && var.enable_keycloak && var.create_default_admin_user ? 1 : 0
  realm_id = keycloak_realm.argocd[0].id
  user_id  = keycloak_user.argocd_admin[0].id
  group_ids = [
    keycloak_group.argocd_admins[0].id
  ]
}

# =============================================================================
# SECTION 5: CONFIGURE ARGOCD OIDC IN HUB CLUSTER
# =============================================================================

# Patch ArgoCD ConfigMap with OIDC configuration
resource "null_resource" "hub_keycloak_oidc_config" {
  count = var.deploy_hub && var.enable_keycloak ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Create OIDC patch file with proper YAML formatting
      cat > /tmp/oidc-patch.yaml <<'YAML_EOF'
data:
  url: ${var.argocd_url}
  oidc.config: |
    name: Keycloak
    issuer: ${var.keycloak_url}/realms/${var.keycloak_realm}
    clientID: ${var.keycloak_client_id}
    %{if var.keycloak_enable_pkce~}enablePKCEAuthentication: true%{else~}clientSecret: $oidc.keycloak.clientSecret%{endif~}

    requestedScopes: ["openid", "profile", "email", "groups"]
YAML_EOF

      # Patch ArgoCD ConfigMap
      kubectl patch configmap argocd-cm -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch-file /tmp/oidc-patch.yaml

      rm /tmp/oidc-patch.yaml
      echo "✓ ArgoCD OIDC configuration applied"
    EOT
  }

  depends_on = [
    null_resource.hub_argocd_install,
    keycloak_openid_client.argocd,
    keycloak_openid_client.argocd_pkce,
    keycloak_openid_client_default_scopes.argocd
  ]
}

# Store client secret in ArgoCD secret (only for Client Authentication mode)
resource "null_resource" "hub_keycloak_secret" {
  count = var.deploy_hub && var.enable_keycloak && !var.keycloak_enable_pkce ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      kubectl patch secret argocd-secret -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch "{\"stringData\":{\"oidc.keycloak.clientSecret\":\"${keycloak_openid_client.argocd[0].client_secret}\"}}"

      echo "✓ Keycloak client secret stored in ArgoCD secret"
    EOT
  }

  depends_on = [
    null_resource.hub_argocd_install,
    keycloak_openid_client.argocd
  ]

  triggers = {
    client_secret = keycloak_openid_client.argocd[0].client_secret
  }
}

# =============================================================================
# SECTION 6: CONFIGURE ARGOCD RBAC POLICIES
# =============================================================================

# Patch ArgoCD RBAC ConfigMap with group-to-role mappings
resource "null_resource" "hub_keycloak_rbac" {
  count = var.deploy_hub && var.enable_keycloak ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Create RBAC patch file
      cat <<EOF > rbac-patch.yaml
data:
  policy.csv: |
    g, ArgoCDAdmins, role:admin
    g, ArgoCDDevelopers, role:edit
    g, ArgoCDViewers, role:readonly
EOF

      # Patch ArgoCD RBAC ConfigMap
      kubectl patch configmap argocd-rbac-cm -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch-file rbac-patch.yaml

      rm rbac-patch.yaml
      echo "✓ ArgoCD RBAC policies configured"
    EOT
  }

  depends_on = [
    null_resource.hub_argocd_install,
    keycloak_group.argocd_admins,
    keycloak_group.argocd_developers,
    keycloak_group.argocd_viewers
  ]
}

# Disable admin user when Keycloak is enabled (force SSO login only)
resource "null_resource" "hub_disable_admin_user" {
  count = var.deploy_hub && var.enable_keycloak ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Disable the built-in admin user (force SSO login only)
      kubectl patch configmap argocd-cm -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch '{"data":{"admin.enabled":"false"}}'
      
      echo "✓ ArgoCD admin user disabled (SSO-only login enforced)"
    EOT
  }

  depends_on = [
    null_resource.hub_keycloak_oidc_config,
    null_resource.hub_keycloak_rbac
  ]
}

# Restart ArgoCD server to apply OIDC and RBAC changes
resource "null_resource" "hub_keycloak_restart_server" {
  count = var.deploy_hub && var.enable_keycloak ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      kubectl rollout restart deployment argocd-server -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context}
      
      kubectl rollout status deployment/argocd-server -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} --timeout=300s

      echo "✓ ArgoCD server restarted with OIDC configuration"
    EOT
  }

  depends_on = [
    null_resource.hub_keycloak_oidc_config,
    null_resource.hub_keycloak_secret,
    null_resource.hub_keycloak_rbac,
    null_resource.hub_disable_admin_user
  ]
}

# =============================================================================
# SECTION 7: KEYCLOAK CONFIGURATION OUTPUTS
# =============================================================================

output "keycloak_realm_id" {
  description = "Keycloak realm ID"
  value       = var.enable_keycloak && var.deploy_hub ? keycloak_realm.argocd[0].id : null
}

output "keycloak_client_id_output" {
  description = "Keycloak client ID for ArgoCD"
  value       = var.enable_keycloak && var.deploy_hub ? var.keycloak_client_id : null
}

output "keycloak_client_secret" {
  description = "Keycloak client secret (only for Client Authentication mode)"
  value = var.enable_keycloak && var.deploy_hub && !var.keycloak_enable_pkce ? (
    keycloak_openid_client.argocd[0].client_secret
  ) : "N/A (PKCE mode)"
  sensitive = true
}

output "keycloak_authentication_method" {
  description = "Keycloak authentication method in use"
  value       = var.enable_keycloak && var.deploy_hub ? (var.keycloak_enable_pkce ? "PKCE (CLI enabled)" : "Client Authentication") : null
}

output "keycloak_oidc_issuer" {
  description = "Keycloak OIDC issuer URL"
  value       = var.enable_keycloak && var.deploy_hub ? "${var.keycloak_url}/realms/${var.keycloak_realm}" : null
}

output "keycloak_cli_login_command" {
  description = "Command to login via ArgoCD CLI with Keycloak PKCE"
  value = var.enable_keycloak && var.deploy_hub && var.keycloak_enable_pkce ? (
    "argocd login ${var.argocd_host} --sso --grpc-web"
  ) : "N/A (Client Authentication mode)"
}

output "keycloak_groups" {
  description = "Keycloak groups created for ArgoCD RBAC"
  value = var.enable_keycloak && var.deploy_hub ? {
    admins     = "ArgoCDAdmins (role:admin)"
    developers = "ArgoCDDevelopers (role:edit)"
    viewers    = "ArgoCDViewers (role:readonly)"
  } : null
}

output "keycloak_admin_user" {
  description = "Default Keycloak admin user credentials for initial ArgoCD login"
  value = var.enable_keycloak && var.deploy_hub && var.create_default_admin_user ? {
    username  = var.default_admin_username
    email     = var.default_admin_email
    temporary = var.default_admin_password_temporary
    login_url = "${var.argocd_url}/login"
    note      = var.default_admin_password_temporary ? "Password must be changed on first login" : "Use configured password"
  } : null
}

output "keycloak_login_instructions" {
  description = "Instructions for logging into ArgoCD with Keycloak"
  value = var.enable_keycloak && var.deploy_hub ? trimspace(<<-EOT
╔════════════════════════════════════════════════════════════════════════════╗
║                    ArgoCD Keycloak Login Instructions                     ║
╚════════════════════════════════════════════════════════════════════════════╝

WEB LOGIN:
──────────
1. Navigate to: ${var.argocd_url}
2. Click "LOG IN VIA KEYCLOAK" button
3. Use credentials:
   Username: ${var.create_default_admin_user ? var.default_admin_username : "<your-keycloak-user>"}
   Password: ${var.create_default_admin_user ? (var.default_admin_password_temporary ? "<set-in-terraform.tfvars> (must change on first login)" : "<set-in-terraform.tfvars>") : "<your-keycloak-password>"}

CLI LOGIN (PKCE mode only):
───────────────────────────
${var.keycloak_enable_pkce ? "argocd login ${var.argocd_host} --sso --grpc-web" : "PKCE not enabled - set keycloak_enable_pkce = true to use CLI login"}

NOTES:
──────
- Built-in admin user is DISABLED (SSO-only login)
- Users must be in Keycloak groups: ArgoCDAdmins, ArgoCDDevelopers, or ArgoCDViewers
- Create additional users in Keycloak: ${var.keycloak_url}
EOT
  ) : null
}
