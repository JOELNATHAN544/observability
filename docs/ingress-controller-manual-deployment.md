# Manual NGINX Ingress Controller Deployment (Helm)

This guide explains how to manually deploy the **NGINX Ingress Controller** using Helm.

## Prerequisites

- **Helm** 3.x installed
- **kubectl** installed and configured

## 1. Verify Context

Ensure you are targeting the correct Kubernetes cluster:

```bash
kubectl config current-context
```

## 2. Installation

1. **Add the Kubernetes Ingress Nginx repository**:
   ```bash
   helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
   helm repo update
   ```

2. **Install the Controller**:
   ```bash
   helm install nginx-monitoring ingress-nginx/ingress-nginx \
     --namespace ingress-nginx \ # You can change this to your preferred namespace
     --create-namespace \
     --version 4.14.1 \
     --set controller.ingressClassResource.name=nginx \
     --set controller.ingressClass=nginx \
     --set controller.ingressClassResource.controllerValue=k8s.io/nginx \
     --set controller.ingressClassResource.enabled=true \
     --set controller.ingressClassByName=true
   ```

## 3. Verification

1. **Check Pods**:
   ```bash
   kubectl get pods -n ingress-nginx # Adjust namespace if changed above
   ```

2. **Check LoadBalancer Service**:
   ```bash
   kubectl get svc -n ingress-nginx # Adjust namespace if changed above
   ```
   Wait for the `EXTERNAL-IP` to be assigned.
