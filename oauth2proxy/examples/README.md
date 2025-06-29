# OAuth2 Proxy Configuration Examples

This directory contains configuration examples for different OAuth2 providers and scenarios.

## Quick Start

All configuration is done in the main `values.yaml` file. Simply:

1. Edit `oauth2proxy/values.yaml` 
2. Configure your OAuth provider settings
3. Set up your secrets (see below) - **NEVER in values.yaml!**
4. Check configuration: `./kagent-oauth2proxy.sh secret-status`
5. Deploy with `./kagent-oauth2proxy.sh deploy`

## Key Configuration Areas

### 1. OAuth Provider Settings

Edit the `oauth2.provider` and provider-specific sections in `values.yaml`:

```yaml
oauth2:
  provider: "github"  # or "google", "azure", "oidc"
  
  # For GitHub
  github:
    org: "your-org-name"  # CHANGE THIS
    team: ""              # Optional: specific team
    users: []             # Optional: specific users
```

### 2. Domain and Security Settings

```yaml
cookie:
  domain: ""        # Set for production: ".yourdomain.com"
  secure: false     # Set to true for HTTPS production

security:
  forceHttps: false # Set to true for production

extraArgs:
  - "--redirect-url=http://localhost:8090/oauth2/callback"  # CHANGE for production
```

### 3. Upstream Configuration

```yaml
upstream:
  kagent:
    service: "kagent.kagent.svc.cluster.local"  # Adjust if needed
    port: 80
```

## Common Configurations

### GitHub Organization Access
```yaml
oauth2:
  provider: "github"
  github:
    org: "mycompany"
    team: "developers"  # Optional: restrict to team
```

### Google Workspace
```yaml
oauth2:
  provider: "google"
  google:
    hostedDomain: "mycompany.com"
```

### Production HTTPS
```yaml
cookie:
  secure: true
  domain: ".mycompany.com"

security:
  forceHttps: true

extraArgs:
  - "--redirect-url=https://kagent.mycompany.com/oauth2/callback"
```

## Secrets Management

Secrets are handled separately from configuration:

1. **Using the setup script** (recommended):
   ```bash
   ./kagent-oauth2proxy.sh setup-oauth
   ```

2. **Using secrets.yaml file**:
   ```bash
   cp secrets.yaml.example secrets.yaml
   # Edit secrets.yaml with your OAuth credentials
   ```

3. **Using environment variables**:
   ```bash
   export OAUTH2_PROXY_CLIENT_ID="your_client_id"
   export OAUTH2_PROXY_CLIENT_SECRET="your_client_secret"
   export OAUTH2_PROXY_COOKIE_SECRET="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
   ```

## Need Help?

Run `./kagent-oauth2proxy.sh help` for detailed deployment instructions and troubleshooting tips. 
