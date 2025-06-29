# Standalone OAuth2 Proxy for Kagent (github)

This directory contains a standalone OAuth2 Proxy Helm chart that provides authentication for Kagent UI. The oauth2proxy runs as a completely separate deployment and proxies authenticated requests to the Kagent service.

The aim is to have working login via Github. Other providers were not considered at this stage but will work with correct config.


## Architecture

```
User → OAuth2 Proxy (port 8090) → Kagent Web UI Service (kagent.kagent.svc.cluster.local:80)
```

- **OAuth2 Proxy**: Handles GitHub authentication and authorization
- **Kagent**: Runs independently without any authentication logic
- **Clean Separation**: OAuth2 Proxy and Kagent are completely independent deployments

## Quick Start

### Option 1: Interactive Setup (Recommended)

```bash
# Interactive OAuth app setup wizard (creates secrets.yaml)
./kagent-oauth2proxy.sh setup-oauth

# Check secret configuration status
./kagent-oauth2proxy.sh secret-status

# Deploy OAuth2 Proxy
./kagent-oauth2proxy.sh deploy

# Access the application
./kagent-oauth2proxy.sh port-forward
```

### Option 2: Manual Setup

### 1. Prerequisites

- Kubernetes cluster with Helm installed
- kubectl configured to access your cluster
- `yq` YAML processor installed (`brew install yq` or see [yq installation guide](https://github.com/mikefarah/yq))
- GitHub OAuth App: wizard provided. Also see [OAUTH_SETUP_GUIDE.md](OAUTH_SETUP_GUIDE.md) for detailed instructions)

### 2. Create GitHub OAuth App

1. Go to [GitHub Settings > Developer settings > OAuth Apps](https://github.com/settings/applications/new)
2. Fill in the application details:
   - **Application name**: `Kagent OAuth2 Proxy`
   - **Homepage URL**: `http://localhost:8090`
   - **Authorization callback URL**: `http://localhost:8090/oauth2/callback`
3. Click "Register application"
4. Note down the **Client ID** and **Client Secret**

### 3. Configure Credentials

Create a `secrets.yaml` file with your OAuth credentials:

```bash
# Copy the example file
cp secrets.yaml.example secrets.yaml

# Edit with your actual credentials
# secrets.yaml:
oauth2:
  clientId: "your_github_client_id"
  clientSecret: "your_github_client_secret"
  cookieSecret: "generated_cookie_secret"
```

**Alternative**: Set environment variables:

```bash
export OAUTH2_PROXY_CLIENT_ID="your_github_client_id"
export OAUTH2_PROXY_CLIENT_SECRET="your_github_client_secret"
export OAUTH2_PROXY_COOKIE_SECRET=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')
```

### 4. Deploy OAuth2 Proxy

```bash
./kagent-oauth2proxy.sh deploy
```

### 5. Access the Application

```bash
# Start port forwarding
./kagent-oauth2proxy.sh port-forward

# In another terminal, access the application
open http://localhost:8090
```

## Configuration

### Single Configuration File

All configuration is done in `oauth2proxy/values.yaml`. This file contains:
- OAuth provider settings (GitHub, Google, Azure, OIDC)
- Security and cookie configuration  
- Upstream service configuration
- Branding and templates
- All other settings

**Key sections to customize:**

#### 1. GitHub OAuth2 Configuration
```yaml
oauth2:
  provider: "github"
  github:
    org: "your-org-name"  # CHANGE THIS: If you use GitHub organization
    team: ""              # Optional: specific team within org
    users: []             # Optional: specific users (e.g., ["user1", "user2"]) also use with your personal github account
```

#### 2. Production Settings
```yaml
cookie:
  secure: true          # Set to true for HTTPS production
  domain: ".yourdomain.com"  # Set your domain

security:
  forceHttps: true      # Set to true for production

extraArgs:
  - "--redirect-url=https://kagent.yourdomain.com/oauth2/callback"  # Production URL
```

#### 3. Upstream Configuration
```yaml
upstream:
  kagent:
    service: "kagent.kagent.svc.cluster.local"  # Adjust if needed
    port: 80
```

### Configuration Examples

The `oauth2proxy/examples/README.md` file contains detailed examples for:
- Different OAuth providers (GitHub, Google, Azure)
- Development vs Production settings
- Custom domain configurations

**No separate values files needed** - just edit the main `values.yaml` file!

## Secret Management

### 🔒 **Security First**
- **NEVER put secrets in values.yaml** - this is a security risk!
- Secrets are managed separately from configuration
- The deployment script validates that values.yaml doesn't contain secrets

### 📋 **Secret Management Methods**

#### 1. **Deployment Script** (Recommended)
```bash
./kagent-oauth2proxy.sh setup-oauth  # Interactive setup
./kagent-oauth2proxy.sh secret-status # Check status
```

#### 2. **Environment Variables**
```bash
export OAUTH2_PROXY_CLIENT_ID="your_client_id"
export OAUTH2_PROXY_CLIENT_SECRET="your_client_secret"
export OAUTH2_PROXY_COOKIE_SECRET="your_cookie_secret"
```

#### 3. **secrets.yaml File**
```bash
cp secrets.yaml.example secrets.yaml
# Edit secrets.yaml with your credentials
```

#### 4. **External Secrets** (Production)
```yaml
# In values.yaml
externalSecrets:
  enabled: true
  secretName: "oauth2proxy-secrets"
```

### 🔍 **How It Works**
1. **Configuration** is in `values.yaml` (OAuth provider, domains, etc.)
2. **Secrets** are in Kubernetes secrets (created by deployment script)
3. **Templates** reference secrets via `secretKeyRef`
4. **Validation** ensures no secrets leak into configuration files

## Deployment Script Commands

The `kagent-oauth2proxy.sh` script provides several commands:

### Basic Commands
```bash
# Interactive OAuth app setup wizard
./kagent-oauth2proxy.sh setup-oauth

# Deploy oauth2proxy
./kagent-oauth2proxy.sh deploy

# Check deployment status
./kagent-oauth2proxy.sh status

# View logs (follows)
./kagent-oauth2proxy.sh logs

# Port forward (default port 8090)
./kagent-oauth2proxy.sh port-forward

# Port forward on custom port
./kagent-oauth2proxy.sh port-forward 9090

# Clean up everything
./kagent-oauth2proxy.sh cleanup

# Show help
./kagent-oauth2proxy.sh help
```

### Secret Management Commands
```bash
# Check secret configuration status
./kagent-oauth2proxy.sh secret-status

# Validate secrets.yaml matches Kubernetes secret
./kagent-oauth2proxy.sh secret-validate

# Update Kubernetes secret with secrets.yaml values
./kagent-oauth2proxy.sh secret-update
```

### Troubleshooting with Secret Commands

The secret management commands are particularly useful for troubleshooting authentication issues:

#### `secret-status` - Configuration Overview
Shows current secret configuration and validates setup:
- ✅ Checks if secrets.yaml exists and is valid
- ✅ Shows Kubernetes secret status
- ✅ Displays partial secret values (first 10 chars for verification)
- ✅ Validates OAuth2 Proxy pod configuration

#### `secret-validate` - Sync Verification
Compares secrets.yaml with deployed Kubernetes secret:
- ✅ Detects configuration drift between file and cluster
- ✅ Identifies mismatched client ID, client secret, or cookie secret
- ✅ Helps troubleshoot authentication failures due to outdated secrets

#### `secret-update` - Quick Sync
Updates Kubernetes secret with current secrets.yaml values:
- ✅ Safely updates deployed secrets without full redeployment
- ✅ Faster than full `deploy` command when only secrets changed
- ✅ Validates secrets before applying changes
- ✅ Shows confirmation of updated values

**Common troubleshooting workflow:**
```bash
# 1. Check current configuration
./kagent-oauth2proxy.sh secret-status

# 2. If secrets don't match, validate the difference
./kagent-oauth2proxy.sh secret-validate

# 3. Update secrets if needed
./kagent-oauth2proxy.sh secret-update

# 4. Restart deployment to pick up new secrets
kubectl rollout restart deployment/kagent-oauth2proxy -n kagent
```

## Security Features

### GitHub Authentication
- **GitHub Organization**: Only members of specified GitHub organization can access
- **GitHub Team Restrictions**: Optional restriction to specific teams within organization
- **GitHub User Allowlist**: Optional allowlist of specific GitHub users

### Session Management
- **Secure Cookies**: HTTP-only cookies with CSRF protection
- **Session Expiry**: Configurable session and refresh intervals
- **Cookie Encryption**: Strong encryption for session cookies

### Request Headers
- **User Information**: Passes authenticated user information to upstream
- **Request Logging**: Comprehensive logging of authentication events
- **Health Endpoints**: Health checks bypass authentication

## Monitoring

### Metrics
OAuth2 Proxy exposes Prometheus metrics on port 44180:
- Authentication success/failure rates
- Request latency and throughput
- Session statistics

### Health Checks
- **Liveness**: `/ping` endpoint
- **Readiness**: `/ready` endpoint
- **Metrics**: `/metrics` endpoint (Prometheus format)

### Logging
Configurable logging levels with structured output:
- Request logging
- Authentication events
- Error tracking

## Production Deployment

### HTTPS Configuration
```yaml
cookie:
  secure: true
security:
  forceHttps: true
extraArgs:
  - "--redirect-url=https://yourdomain.com/oauth2/callback"
```

### External Secrets
```yaml
externalSecrets:
  enabled: true
  secretName: "oauth2proxy-secrets"
  keys:
    clientId: "client-id"
    clientSecret: "client-secret"
    cookieSecret: "cookie-secret"
```

### Ingress Configuration (disabled by default)
```yaml
ingress:
  enabled: true
  className: "nginx"
  annotations:
    kubernetes.io/tls-acme: "true"
  hosts:
    - host: kagent.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: kagent-tls
      hosts:
        - kagent.yourdomain.com
```

## Troubleshooting

### Common Issues

#### 1. Secret Configuration Issues
**Error**: `Invalid client` or authentication failures
**Solution**: 
- Run `./kagent-oauth2proxy.sh secret-status` to check configuration
- Ensure secrets are NOT in values.yaml (security risk!)
- Use `./kagent-oauth2proxy.sh setup-oauth` for interactive setup
- Verify environment variables or secrets.yaml are properly set

#### 2. OAuth Callback URL Mismatch
**Error**: `redirect_uri_mismatch`
**Solution**: Ensure GitHub OAuth App callback URL matches your deployment URL

#### 3. Organization Access Denied
**Error**: `403 Forbidden`
**Solution**: Verify user is member of specified GitHub organization

#### 4. Cookie Issues
**Error**: Authentication loop
**Solution**: Check cookie domain and secure settings

#### 5. Upstream Connection Failed
**Error**: `502 Bad Gateway`
**Solution**: Verify Kagent service is running and accessible

#### 6. Secrets in Values.yaml (Security Issue)
**Error**: Script validation fails with security warning
**Solution**: 
- NEVER put secrets directly in values.yaml
- Remove any clientId, clientSecret, or cookieSecret from values.yaml
- Use the deployment script or environment variables instead

#### 7. Missing yq Command
**Error**: `yq command not found!`
**Solution**: Install the yq YAML processor:
```bash
# On macOS:
brew install yq

# On Ubuntu/Debian:
sudo apt-get install yq

# On RHEL/CentOS/Fedora:
sudo yum install yq

# Or download from: https://github.com/mikefarah/yq/releases
```

### Debug Commands

```bash
# Check pod status
kubectl get pods -n oauth2proxy

# View detailed pod information
kubectl describe pod -n oauth2proxy -l app.kubernetes.io/name=oauth2proxy

# Check service endpoints
kubectl get endpoints -n oauth2proxy

# View configuration
kubectl get configmap -n oauth2proxy -o yaml

# Check secrets
kubectl get secrets -n oauth2proxy
```

### Log Analysis

```bash
# Follow logs in real-time
./kagent-oauth2proxy.sh logs

# Check for authentication errors
kubectl logs -n oauth2proxy -l app.kubernetes.io/name=oauth2proxy | grep -i error

# Monitor authentication events
kubectl logs -n oauth2proxy -l app.kubernetes.io/name=oauth2proxy | grep -i auth
```

## Development

### Testing Different Providers

1. Edit the main `oauth2proxy/values.yaml` file
2. Change the provider configuration:
   ```yaml
   oauth2:
     provider: "google"  # or "azure", "oidc", etc.
   ```
3. Deploy with the updated configuration:
   ```bash
   ./kagent-oauth2proxy.sh deploy
   ```

### Local Development

1. Use port forwarding for local testing
2. Set `cookie.secure: false` for HTTP testing
3. Use `localhost` URLs in OAuth app configuration

### Chart Development

```bash
# Validate chart
helm lint ./oauth2proxy

# Render templates
helm template oauth2proxy ./oauth2proxy --values values.yaml

# Debug deployment
helm install oauth2proxy ./oauth2proxy --dry-run --debug
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with different configurations
5. Submit a pull request

## License

Apache 2.0
