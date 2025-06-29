# GitHub OAuth App Setup Guide

This guide explains how to create a GitHub OAuth application for use with the Kagent OAuth2 Proxy.

## Quick Setup (Recommended)

Use the interactive setup wizard:

```bash
./kagent-oauth2proxy.sh setup-oauth
```

This will guide you through the entire process step-by-step.

## Manual Setup

If you prefer to set up the OAuth app manually, follow these steps:

### Step 1: Create GitHub OAuth Application

1. **Go to GitHub OAuth Apps page**
   - Visit: https://github.com/settings/applications/new
   - Or navigate: GitHub Settings → Developer settings → OAuth Apps → New OAuth App

2. **Fill in the application details:**

   | Field | Value |
   |-------|-------|
   | **Application name** | `Kagent OAuth2 Proxy` |
   | **Homepage URL** | `http://localhost:8090` (for local dev) |
   | **Application description** | `OAuth2 Proxy for Kagent UI authentication` |
   | **Authorization callback URL** | `http://localhost:8090/oauth2/callback` |

3. **Click "Register application"**

4. **Note your credentials:**
   - Copy the **Client ID** (20 characters)
   - Generate and copy the **Client Secret**

### Step 2: Configure Environment Variables

```bash
# Set OAuth credentials
export OAUTH2_PROXY_CLIENT_ID="your_20_char_client_id"
export OAUTH2_PROXY_CLIENT_SECRET="your_client_secret"

# Generate secure cookie secret
export OAUTH2_PROXY_COOKIE_SECRET="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
```

### Step 3: Deploy OAuth2 Proxy

```bash
./kagent-oauth2proxy.sh deploy
```

### Step 4: Access the Application

```bash
# Start port forwarding
./kagent-oauth2proxy.sh port-forward

# Access in browser
open http://localhost:8090
```

## Production Configuration

For production deployments, update the OAuth app settings:

| Environment | Homepage URL | Callback URL |
|-------------|--------------|--------------|
| **Local Development** | `http://localhost:8090` | `http://localhost:8090/oauth2/callback` |
| **Production (HTTPS)** | `https://kagent.yourdomain.com` | `https://kagent.yourdomain.com/oauth2/callback` |
| **Production (HTTP)** | `http://kagent.yourdomain.com` | `http://kagent.yourdomain.com/oauth2/callback` |

## Organization Access

If your GitHub organization has OAuth app restrictions:

1. **Request approval** from organization owners
2. **Or create the OAuth app** under the organization account instead of personal account
3. **Configure organization restrictions** in GitHub Settings → Organizations → Third-party access

## Environment Variables Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `OAUTH2_PROXY_CLIENT_ID` | GitHub OAuth App Client ID (exactly 20 chars) | `Iv1..` |
| `OAUTH2_PROXY_CLIENT_SECRET` | GitHub OAuth App Client Secret | `16C7e4......` |
| `OAUTH2_PROXY_COOKIE_SECRET` | Random secret for cookie encryption (32+ chars) | `v2zfVCNHh8l..........` |

## Validation Commands

```bash
# Check OAuth app configuration
./kagent-oauth2proxy.sh check-oauth

# Validate environment variables
echo "Client ID: ${OAUTH2_PROXY_CLIENT_ID}"
echo "Client Secret: ${OAUTH2_PROXY_CLIENT_SECRET:0:8}..." 
echo "Cookie Secret: ${OAUTH2_PROXY_COOKIE_SECRET:0:8}..."
```

## Common Issues & Solutions

### 🔴 "Invalid client" error
- **Cause**: Wrong Client ID or Client Secret
- **Solution**: Double-check credentials from GitHub OAuth app settings

### 🔴 "Callback URL mismatch" error  
- **Cause**: OAuth app callback URL doesn't match deployment URL
- **Solution**: Update callback URL in GitHub OAuth app settings to match your deployment

### 🔴 "Access denied" error
- **Cause**: User not member of allowed GitHub organization
- **Solution**: Update `oauth2proxy/examples/github-example-values.yaml` with correct GitHub organization

### 🔴 Cookie/session errors
- **Cause**: Invalid or too short cookie secret
- **Solution**: Regenerate cookie secret with at least 32 characters

### 🔴 Organization access blocked
- **Cause**: GitHub organization has OAuth app restrictions
- **Solution**: Request approval or create app under organization account

## Security Best Practices

1. **Use HTTPS in production**
   ```yaml
   cookie:
     secure: true
   security:
     forceHttps: true
   ```

2. **Restrict to specific GitHub organization**
   ```yaml
   oauth2:
     github:
       org: "your-github-organization"
   ```

3. **Limit to specific GitHub teams** (optional)
   ```yaml
   oauth2:
     github:
       org: "your-github-organization"
       team: "kagent-users"
   ```

4. **Use strong cookie secrets**
   ```bash
   # Generate cryptographically secure secret
   python3 -c 'import secrets; print(secrets.token_urlsafe(32))'
   ```

## Advanced Configuration

### Multiple Environments

Create separate GitHub OAuth apps for different environments:

- `Kagent OAuth2 Proxy - Development`
- `Kagent OAuth2 Proxy - Staging`  
- `Kagent OAuth2 Proxy - Production`

### Custom GitHub Organization/Team Restrictions

Edit `oauth2proxy/examples/github-example-values.yaml`:

```yaml
oauth2:
  provider: "github"
  github:
    org: "your-company"           # Required: GitHub organization
    team: "engineering"           # Optional: Specific team within org
    users: ["admin1", "admin2"]   # Optional: Individual GitHub users
```

### External Secrets Management

For production, consider using Kubernetes secrets or external secret management:

```yaml
externalSecrets:
  enabled: true
  secretName: "oauth2proxy-secrets"
```

## Troubleshooting Commands

```bash
# Check deployment status
./kagent-oauth2proxy.sh status

# View logs
./kagent-oauth2proxy.sh logs

# Validate OAuth configuration
./kagent-oauth2proxy.sh check-oauth

# Test GitHub CLI access (if available)
gh api user

# Clean up and retry
./kagent-oauth2proxy.sh cleanup
./kagent-oauth2proxy.sh deploy
```

## Support

If you encounter issues:

1. Check the [troubleshooting section](#common-issues--solutions) above
2. Run `./kagent-oauth2proxy.sh check-oauth` for validation
3. Review the OAuth2 Proxy logs: `./kagent-oauth2proxy.sh logs`
4. Verify GitHub OAuth app settings match your deployment URLs 
5. If all fails - find Marcin on [kagent discord](https://discord.gg/Fu3k65f2k3)
