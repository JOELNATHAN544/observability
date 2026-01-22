# ArgoCD Agent - PKI Management Guide

This guide explains how certificates are managed in the ArgoCD Hub-and-Spoke architecture using Terraform.

## Overview

All PKI operations are **fully automated** via Terraform. No manual `argocd-agentctl` commands are required.

## Certificate Hierarchy

```
Hub CA (Self-Signed)
├── RSA 4096-bit
├── Validity: 10 years
├── Stored in: Hub cluster secret `argocd-agent-ca`
│
└── Spoke Client Certificates
    ├── spoke-01
    │   ├── RSA 4096-bit
    │   ├── Validity: 1 year
    │   ├── Signed by: Hub CA
    │   └── Stored in: Spoke cluster secret `argoc-agent-client-cert`
    │
    ├── spoke-02
    └── spoke-N
```

## Terraform PKI Resources

### Hub CA Creation

```hcl
# 1. Generate CA private key
resource "tls_private_key" "hub_ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# 2. Create self-signed CA certificate
resource "tls_self_signed_cert" "hub_ca" {
  private_key_pem = tls_private_key.hub_ca.private_key_pem
  
  subject {
    common_name  = var.ca_common_name
    organization = var.ca_organization
  }
  
  validity_period_hours = var.ca_validity_hours  # Default: 87600 (10 years)
  is_ca_certificate     = true
  
  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
    "key_encipherment",
  ]
}

# 3. Store in Hub cluster
resource "kubernetes_secret" "hub_ca" {
  provider = kubernetes.hub
  
  metadata {
    name      = "argocd-agent-ca"
    namespace = var.hub_namespace
  }
  
  data = {
    "ca.crt"  = tls_self_signed_cert.hub_ca.cert_pem
    "ca.key"  = tls_private_key.hub_ca.private_key_pem
    "tls.crt" = tls_self_signed_cert.hub_ca.cert_pem
    "tls.key" = tls_private_key.hub_ca.private_key_pem
  }
  
  type = "kubernetes.io/tls"
}
```

### Spoke Client Certificate Generation

```hcl
# 1. Generate client private key
resource "tls_private_key" "spoke_client" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# 2. Create certificate signing request
resource "tls_cert_request" "spoke_client" {
  private_key_pem = tls_private_key.spoke_client.private_key_pem
  
  subject {
    common_name  = var.spoke_id  # e.g., "spoke-01"
    organization = var.ca_organization
  }
}

# 3. Sign with Hub CA
resource "tls_locally_signed_cert" "spoke_client" {
  cert_request_pem   = tls_cert_request.spoke_client.cert_request_pem
  ca_private_key_pem = tls_private_key.hub_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.hub_ca.cert_pem
  
  validity_period_hours = var.client_cert_validity_hours  # Default: 8760 (1 year)
  
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth",
  ]
}

# 4. Store in Spoke cluster
resource "kubernetes_secret" "spoke_client_cert" {
  provider = kubernetes.spoke
  
  metadata {
    name      = "argocd-agent-client-cert"
    namespace = var.spoke_namespace
  }
  
  data = {
    "tls.crt" = tls_locally_signed_cert.spoke_client.cert_pem
    "tls.key" = tls_private_key.spoke_client.private_key_pem
    "ca.crt"  = tls_self_signed_cert.hub_ca.cert_pem
  }
  
  type = "kubernetes.io/tls"
}
```

## Certificate Lifecycle

### Initial Deployment

Certificates are automatically generated during `terraform apply`:

```bash
terraform apply
```

Terraform will:
1. Generate Hub CA (once)
2. Generate spoke client certificate
3. Store certificates as Kubernetes secrets
4. Configure Agent to use client certificate for mTLS

### Certificate Inspection

#### View Hub CA

```bash
# Get CA certificate
kubectl --context=$HUB_CTX get secret -n argocd argocd-agent-ca \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > hub-ca.crt

# Inspect
openssl x509 -in hub-ca.crt -text -noout

# Check validity
openssl x509 -in hub-ca.crt -noout -dates
```

#### View Spoke Client Certificate

```bash
# Get client certificate
kubectl --context=$SPOKE_CTX get secret -n argocd argocd-agent-client-cert \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > spoke-client.crt

# Inspect
openssl x509 -in spoke-client.crt -text -noout

# Verify it's signed by Hub CA
openssl verify -CAfile hub-ca.crt spoke-client.crt
```

## Certificate Rotation

### When to Rotate

Rotate certificates when:
- Certificate approaching expiration (< 30 days for client certs)
- Certificate compromised
- Changing CA policy (organization, key size, etc.)
- Regular security practice (annually for client certs)

### Rotation Process

#### Option 1: Taint and Reapply (Recommended)

This recreates certificates and automatically updates secrets:

```bash
# Taint certificate resources
terraform taint tls_self_signed_cert.hub_ca[0]
terraform taint tls_locally_signed_cert.spoke_client[0]

# Preview changes
terraform plan

# Apply
terraform apply
```

**Impact**:
- Brief Agent reconnection ( 10-30 seconds)
- No downtime for applications
- Pods automatically reload new certificates

#### Option 2: Update Validity Period

Increase validity and reapply:

```hcl
# terraform.tfvars
ca_validity_hours = 175200  # 20 years
client_cert_validity_hours = 17520  # 2 years
```

```bash
terraform apply
```

#### Option 3: Manual Secret Update

For emergency rotation without Terraform:

```bash
# Generate new cert manually
openssl genrsa -out new-client.key 4096
# ... (sign with CA, etc.)

# Update secret
kubectl --context=$SPOKE_CTX create secret tls argocd-agent-client-cert \
  --cert=new-client.crt \
  --key=new-client.key \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart Agent to pick up new cert
kubectl --context=$SPOKE_CTX rollout restart deployment/argocd-agent -n argocd
```

**Warning**: Manual changes will be overwritten on next `terraform apply`.

### Rotation for Multiple Spokes

Rotate all spoke certificates:

```bash
# If using workspaces
for spoke in spoke-01 spoke-02 spoke-03; do
  terraform workspace select $spoke
  terraform taint tls_locally_signed_cert.spoke_client[0]
  terraform apply -auto-approve
done

# If using separate directories
for dir in spoke-*-terraform; do
  cd $dir
  terraform taint tls_locally_signed_cert.spoke_client[0]
  terraform apply -auto-approve
  cd ..
done
```

## Certificate Expiration Monitoring

### Check Expiration Dates

```bash
# Hub CA expiration
kubectl --context=$HUB_CTX get secret -n argocd argocd-agent-ca \
  -o jsonpath='{.data.ca\.crt}' | base64 -d | \
  openssl x509 -noout -enddate

# Spoke client cert expiration
kubectl --context=$SPOKE_CTX get secret -n argocd argocd-agent-client-cert \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -noout -enddate
```

### Automated Monitoring

Create a CronJob to monitor certificate expiration:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cert-expiry-check
  namespace: argocd
spec:
  schedule: "0 0 * * *"  # Daily
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: check
            image: alpine/openssl
            command:
            - sh
            - -c
            - |
              CERT_FILE="/certs/tls.crt"
              EXPIRY=$(openssl x509 -in $CERT_FILE -noout -enddate | cut -d= -f2)
              EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
              NOW_EPOCH=$(date +%s)
              DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
              
              if [ $DAYS_LEFT -lt 30 ]; then
                echo "WARNING: Certificate expires in $DAYS_LEFT days!"
                exit 1
              else
                echo "Certificate valid for $DAYS_LEFT more days"
              fi
            volumeMounts:
            - name: cert
              mountPath: /certs
          volumes:
          - name: cert
            secret:
              secretName: argocd-agent-client-cert
          restartPolicy: OnFailure
```

## Security Best Practices

### Terraform State Security

Certificates are stored in Terraform state. **Secure your state file**:

```hcl
# Use encrypted remote state
terraform {
  backend "gcs" {
    bucket = "my-terraform-state"
    prefix = "argocd-agent"
    
    # Enable encryption
    encryption_key = "projects/my-project/locations/global/keyRings/terraform/cryptoKeys/state"
  }
}
```

Or use other encrypted backends (S3 with KMS AWS Secrets Manager, Azure Key Vault).

### Key Rotation Schedule

| Certificate | Recommended Rotation |
|-------------|---------------------|
| Hub CA | Every 5-10 years |
| Spoke Client Certs | Every 1 year |
| JWT Keys | Every 2 years |

### Access Control

Limit access to:
- Terraform state (contains private keys)
- Hub CA secret on cluster
- Spoke client cert secrets

```bash
# RBAC: Restrict secret access
kubectl create role secret-reader \
  --verb=get,list \
  --resource=secrets \
  --resource-name=argocd-agent-ca \
  -n argocd
```

## Troubleshooting Certificate Issues

### Agent Connection Fails with TLS Error

**Check certificate chain**:
```bash
# Verify Spoke has correct CA
kubectl --context=$SPOKE_CTX get secret -n argocd argocd-agent-client-cert \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > spoke-ca.crt

kubectl --context=$HUB_CTX get secret -n argocd argocd-agent-ca \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > hub-ca.crt

# Should be identical
diff spoke-ca.crt hub-ca.crt
```

### Certificate Expiring Soon

Follow rotation process above.

### Wrong Certificate Format

All certificates should be:
- Algorithm: RSA
- Key size: 4096 bits
- Format: PEM

**Verify**:
```bash
kubectl --context=$SPOKE_CTX get secret -n argocd argocd-agent-client-cert \
  -o jsonpath='{.data.tls\.key}' | base64 -d | \
  openssl rsa -text -noout | head -n1
# Should show: Private-Key: (4096 bit, 2 primes)
```

## References

- [Terraform TLS Provider](https://registry.terraform.io/providers/hashicorp/tls/latest/docs)
- [OpenSSL Commands](https://www.openssl.org/docs/man1.1.1/man1/)
- [Kubernetes TLS Secrets](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets)
