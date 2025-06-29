#!/bin/bash

# Standalone OAuth2 Proxy Deployment Script for Kagent
# This script deploys oauth2proxy as a separate service that proxies to Kagent UI

set -e

# Configuration
NAMESPACE="kagent"
RELEASE_NAME="kagent-oauth2proxy"
CHART_PATH="./oauth2proxy"
VALUES_FILE="values.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[ OK ]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

print_note() {
    echo -e "${CYAN}[NOTE]${NC} $1"
}

# Function to check if GitHub CLI is available and authenticated
check_github_cli() {
    if command -v gh &> /dev/null; then
        if gh auth status &> /dev/null; then
            return 0
        fi
    fi
    return 1
}

# Function to open URLs (cross-platform)
open_url() {
    local url="$1"
    if command -v open &> /dev/null; then
        open "$url"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "$url"
    elif command -v start &> /dev/null; then
        start "$url"
    else
        echo "Please open this URL manually: $url"
    fi
}

# Function to generate a secure cookie secret
generate_cookie_secret() {
    if command -v python3 &> /dev/null; then
        # Generate 32-byte URL-safe base64 encoded secret (recommended)
        # This produces a ~43 character string representing exactly 32 bytes
        python3 -c 'import secrets; print(secrets.token_urlsafe(32))'
    elif command -v openssl &> /dev/null; then
        # Generate 32-character base64-like secret (32 bytes)
        openssl rand -base64 32 | tr -d "=+/\n" | head -c 32
    else
        # Fallback: generate exactly 32 alphanumeric characters (32 bytes)
        LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32
    fi
}

# Function to load secrets from YAML file
load_secrets() {
    local secrets_file="secrets.yaml"
    
    if [[ ! -f "$secrets_file" ]]; then
        print_error "Secrets file '$secrets_file' not found!"
        print_note "Run '$0 setup-oauth' to create it, or copy from secrets.yaml.example"
        return 1
    fi
    
    print_status "Loading secrets from $secrets_file..."
    
    # Check if yq is available for YAML parsing
    if ! command -v yq &> /dev/null; then
        print_error "yq command not found!"
        print_note "yq is required for parsing YAML files. Please install it:"
        echo ""
        echo "  # On macOS:"
        echo "  brew install yq"
        echo ""
        echo "  # On Ubuntu/Debian:"
        echo "  sudo apt-get install yq"
        echo ""
        echo "  # On RHEL/CentOS/Fedora:"
        echo "  sudo yum install yq"
        echo ""
        echo "  # Or download from: https://github.com/mikefarah/yq/releases"
        echo ""
        return 1
    fi
    
    export OAUTH2_PROXY_CLIENT_ID=$(yq eval '.oauth2.clientId' "$secrets_file")
    export OAUTH2_PROXY_CLIENT_SECRET=$(yq eval '.oauth2.clientSecret' "$secrets_file")
    export OAUTH2_PROXY_COOKIE_SECRET=$(yq eval '.oauth2.cookieSecret' "$secrets_file")
    
    # Validate that we got the values
    if [[ -z "$OAUTH2_PROXY_CLIENT_ID" || "$OAUTH2_PROXY_CLIENT_ID" == "null" ]]; then
        print_error "Could not read clientId from $secrets_file"
        return 1
    fi
    
    if [[ -z "$OAUTH2_PROXY_CLIENT_SECRET" || "$OAUTH2_PROXY_CLIENT_SECRET" == "null" ]]; then
        print_error "Could not read clientSecret from $secrets_file"
        return 1
    fi
    
    if [[ -z "$OAUTH2_PROXY_COOKIE_SECRET" || "$OAUTH2_PROXY_COOKIE_SECRET" == "null" ]]; then
        print_error "Could not read cookieSecret from $secrets_file"
        return 1
    fi
    
    print_success "Secrets loaded successfully from $secrets_file"
    return 0
}

# Function to validate OAuth app configuration
validate_oauth_config() {
    local client_id="$1"
    local callback_url="$2"
    
    print_status "Validating OAuth app configuration..."
    
    if [[ ${#client_id} -ne 20 ]]; then
        print_error "GitHub OAuth Client ID should be exactly 20 characters long"
        return 1
    fi
    
    if [[ ! "$callback_url" =~ ^https?://.*oauth2/callback$ ]]; then
        print_warning "Callback URL should end with '/oauth2/callback'"
    fi
    
    print_success "OAuth app configuration looks valid"
    return 0
}

# Function to setup GitHub OAuth app with interactive guidance
setup_oauth_app() {
    clear
    echo "=========================================="
    echo "  GitHub OAuth App Setup Wizard"
    echo "=========================================="
    echo ""
    
    print_step "Step 1: Create GitHub OAuth Application"
    echo ""
    echo "We'll guide you through creating a GitHub OAuth app for Kagent authentication."
    echo ""
    
    # Check if GitHub CLI is available
    if check_github_cli; then
        print_success "GitHub CLI detected and authenticated"
        local github_user=$(gh api user --jq '.login')
        print_note "Authenticated as: $github_user"
    else
        print_warning "GitHub CLI not available or not authenticated"
        print_note "We'll use the web interface instead"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
    
    # Determine callback URL
    echo ""
    print_step "Step 2: Determine Callback URL"
    echo ""
    echo "Choose your deployment type:"
    echo "1) Local development (localhost:8090)"
    echo "2) Custom domain/port"
    echo ""
    read -p "Select option [1-2]: " deployment_choice
    
    case $deployment_choice in
        1)
            CALLBACK_URL="http://localhost:8090/oauth2/callback"
            HOMEPAGE_URL="http://localhost:8090"
            ;;
        2)
            read -p "Enter your domain (e.g., kagent.example.com): " custom_domain
            read -p "Enter port (default: 80): " custom_port
            custom_port=${custom_port:-80}
            
            if [[ "$custom_port" == "443" ]]; then
                CALLBACK_URL="https://${custom_domain}/oauth2/callback"
                HOMEPAGE_URL="https://${custom_domain}"
            elif [[ "$custom_port" == "80" ]]; then
                CALLBACK_URL="http://${custom_domain}/oauth2/callback"
                HOMEPAGE_URL="http://${custom_domain}"
            else
                CALLBACK_URL="http://${custom_domain}:${custom_port}/oauth2/callback"
                HOMEPAGE_URL="http://${custom_domain}:${custom_port}"
            fi
            ;;
        *)
            print_error "Invalid option"
            return 1
            ;;
    esac
    
    print_success "Callback URL: $CALLBACK_URL"
    print_success "Homepage URL: $HOMEPAGE_URL"
    
    echo ""
    read -p "Press Enter to continue..."
    
    # Open GitHub OAuth app creation page
    echo ""
    print_step "Step 3: Create OAuth App on GitHub"
    echo ""
    print_status "Opening GitHub OAuth app creation page..."
    
    open_url "https://github.com/settings/applications/new"
    
    echo ""
    echo "Please fill in the following information on GitHub:"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ Application name: Kagent OAuth2 Proxy                       │"
    echo "│ Homepage URL: $HOMEPAGE_URL                                 |"
    echo "│ Application description: OAuth2 Proxy for Kagent UI         │"
    echo "│ Authorization callback URL: $CALLBACK_URL                   |"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    
    read -p "Press Enter after you've created the OAuth app..."
    
    # Collect OAuth app credentials
    echo ""
    print_step "Step 4: Enter OAuth App Credentials"
    echo ""
    
    read -p "Enter Client ID: " client_id
    read -s -p "Enter Client Secret: " client_secret
    echo ""
    
    # Validate configuration
    if ! validate_oauth_config "$client_id" "$CALLBACK_URL"; then
        print_error "OAuth configuration validation failed"
        return 1
    fi
    
    # Generate cookie secret
    print_status "Generating secure cookie secret..."
    cookie_secret=$(generate_cookie_secret)
    
    # Create secrets YAML file
    echo ""
    print_step "Step 5: Save Configuration"
    echo ""
    
    local secrets_file="secrets.yaml"
    cat > "$secrets_file" << EOF
# OAuth2 Proxy Secrets Configuration
# Generated on $(date)
# WARNING: This file contains sensitive credentials - do not commit to git!

# GitHub OAuth App Credentials
oauth2:
  clientId: "$client_id"
  clientSecret: "$client_secret"
  cookieSecret: "$cookie_secret"

# Configuration used:
# Callback URL: $CALLBACK_URL
# Homepage URL: $HOMEPAGE_URL
EOF
    
    print_success "Configuration saved to: $secrets_file"
    
    # Check if file is properly ignored by git
    if command -v git &> /dev/null && git status --porcelain "$secrets_file" 2>/dev/null | grep -q "^??"; then
        print_warning "Secrets file is not in .gitignore - adding it now"
        echo "" >> .gitignore
        echo "# OAuth secrets files (auto-added)" >> .gitignore
        echo "$secrets_file" >> .gitignore
        print_success "Added $secrets_file to .gitignore"
    elif command -v git &> /dev/null; then
        print_success "Secrets file is properly ignored by git"
    fi
    
    echo ""
    print_step "Step 6: Next Steps"
    echo ""
    echo "Your OAuth credentials have been saved to: $secrets_file"
    echo ""
    print_success "OAuth app setup completed!"
    echo ""
    echo "Next steps:"
    echo "1. Run: $0 deploy"
    echo "2. Run: $0 port-forward"
    echo "3. Access: $HOMEPAGE_URL"
    echo ""
}

# Function to check GitHub OAuth app via API
check_oauth_app() {
    if [[ -z "${OAUTH2_PROXY_CLIENT_ID:-}" ]]; then
        print_error "OAUTH2_PROXY_CLIENT_ID not set. Run '$0 setup-oauth' first."
        return 1
    fi
    
    print_status "Checking OAuth app configuration..."
    
    if check_github_cli; then
        # Try to get app info via GitHub CLI
        local app_info
        if app_info=$(gh api "/applications/$OAUTH2_PROXY_CLIENT_ID" 2>/dev/null); then
            local app_name=$(echo "$app_info" | jq -r '.name')
            local callback_url=$(echo "$app_info" | jq -r '.callback_url')
            
            print_success "OAuth App found: $app_name"
            print_note "Callback URL: $callback_url"
            
            # Check if callback URL matches expected pattern
            if [[ "$callback_url" =~ oauth2/callback$ ]]; then
                print_success "Callback URL format is correct"
            else
                print_warning "Callback URL should end with '/oauth2/callback'"
            fi
        else
            print_warning "Could not retrieve OAuth app details via GitHub API"
            print_note "This might be normal if the app is private or API access is restricted"
        fi
    else
        print_note "GitHub CLI not available - skipping OAuth app validation"
    fi
    
    # Validate environment variables
    if [[ ${#OAUTH2_PROXY_CLIENT_ID} -eq 20 ]]; then
        print_success "Client ID format looks correct"
    else
        print_warning "Client ID should be 20 characters long"
    fi
    
    if [[ -n "${OAUTH2_PROXY_CLIENT_SECRET:-}" ]]; then
        print_success "Client Secret is set"
    else
        print_error "Client Secret is not set"
        return 1
    fi
    
    if [[ -n "${OAUTH2_PROXY_COOKIE_SECRET:-}" ]]; then
        print_success "Cookie Secret is set"
    else
        print_error "Cookie Secret is not set"
        return 1
    fi
}

# Function to validate values.yaml doesn't contain secrets
validate_values_file() {
    local values_path="$CHART_PATH/$VALUES_FILE"
    
    if [[ ! -f "$values_path" ]]; then
        print_error "Values file not found: $values_path"
        return 1
    fi
    
    # Check if yq is available for YAML parsing
    if ! command -v yq &> /dev/null; then
        print_error "yq command not found!"
        print_note "yq is required for validating YAML files. Please install it:"
        echo ""
        echo "  # On macOS:"
        echo "  brew install yq"
        echo ""
        echo "  # On Ubuntu/Debian:"
        echo "  sudo apt-get install yq"
        echo ""
        echo "  # On RHEL/CentOS/Fedora:"
        echo "  sudo yum install yq"
        echo ""
        echo "  # Or download from: https://github.com/mikefarah/yq/releases"
        echo ""
        return 1
    fi
    
    # Check if secrets are accidentally set in values.yaml
    local client_id=$(yq eval '.oauth2.clientId' "$values_path" 2>/dev/null)
    local client_secret=$(yq eval '.oauth2.clientSecret' "$values_path" 2>/dev/null)
    local cookie_secret=$(yq eval '.oauth2.cookieSecret' "$values_path" 2>/dev/null)
    
    if [[ -n "$client_id" && "$client_id" != "null" && "$client_id" != '""' && "$client_id" != "" ]]; then
        print_error "Security Issue: clientId is set in values.yaml!"
        print_warning "Secrets should NEVER be stored in values.yaml"
        print_note "Please remove clientId from $values_path and use the deployment script instead"
        return 1
    fi
    
    if [[ -n "$client_secret" && "$client_secret" != "null" && "$client_secret" != '""' && "$client_secret" != "" ]]; then
        print_error "Security Issue: clientSecret is set in values.yaml!"
        print_warning "Secrets should NEVER be stored in values.yaml"
        print_note "Please remove clientSecret from $values_path and use the deployment script instead"
        return 1
    fi
    
    if [[ -n "$cookie_secret" && "$cookie_secret" != "null" && "$cookie_secret" != '""' && "$cookie_secret" != "" ]]; then
        print_error "Security Issue: cookieSecret is set in values.yaml!"
        print_warning "Secrets should NEVER be stored in values.yaml"
        print_note "Please remove cookieSecret from $values_path and use the deployment script instead"
        return 1
    fi
    
    print_success "Values file validation passed - no secrets found in values.yaml"
    return 0
}

# Function to check required environment variables
check_env_vars() {
    print_status "Checking required environment variables..."
    
    # First try to load from secrets.yaml if environment variables are not set
    if [[ -z "${OAUTH2_PROXY_CLIENT_ID:-}" ]] || [[ -z "${OAUTH2_PROXY_CLIENT_SECRET:-}" ]] || [[ -z "${OAUTH2_PROXY_COOKIE_SECRET:-}" ]]; then
        if [[ -f "secrets.yaml" ]]; then
            print_note "Environment variables not set, trying to load from secrets.yaml..."
            if ! load_secrets; then
                print_error "Failed to load secrets from secrets.yaml"
                exit 1
            fi
        fi
    fi
    
    local missing_vars=()
    
    if [[ -z "${OAUTH2_PROXY_CLIENT_ID:-}" ]]; then
        missing_vars+=("OAUTH2_PROXY_CLIENT_ID")
    fi
    
    if [[ -z "${OAUTH2_PROXY_CLIENT_SECRET:-}" ]]; then
        missing_vars+=("OAUTH2_PROXY_CLIENT_SECRET")
    fi
    
    if [[ -z "${OAUTH2_PROXY_COOKIE_SECRET:-}" ]]; then
        missing_vars+=("OAUTH2_PROXY_COOKIE_SECRET")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_error "Missing required credentials:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        echo ""
        echo "Please provide credentials using one of these methods:"
        echo ""
        print_note "Option 1: Run interactive setup (Recommended)"
        echo "  $0 setup-oauth"
        echo ""
        print_note "Option 2: Create secrets.yaml file"
        echo "  cp secrets.yaml.example secrets.yaml"
        echo "  # Edit secrets.yaml with your OAuth credentials"
        echo ""
        print_note "Option 3: Set environment variables manually"
        echo "  export OAUTH2_PROXY_CLIENT_ID=\"your_github_client_id\""
        echo "  export OAUTH2_PROXY_CLIENT_SECRET=\"your_github_client_secret\""
        echo "  export OAUTH2_PROXY_COOKIE_SECRET=\"your_cookie_secret\""
        echo ""
        print_warning "IMPORTANT: Never put secrets directly in values.yaml!"
        echo "To generate a cookie secret, run:"
        echo "python3 -c 'import secrets; print(secrets.token_urlsafe(32))'"
        exit 1
    fi
    
    print_success "All required credentials are available"
}

# Function to create namespace
create_namespace() {
    print_status "Creating namespace '$NAMESPACE'..."
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace '$NAMESPACE' ready"
}

# Function to create secret
create_secret() {
    print_status "Creating oauth2proxy secret..."
    kubectl create secret generic "${RELEASE_NAME}-secrets" \
        --namespace="$NAMESPACE" \
        --from-literal=client-id="$OAUTH2_PROXY_CLIENT_ID" \
        --from-literal=client-secret="$OAUTH2_PROXY_CLIENT_SECRET" \
        --from-literal=cookie-secret="$OAUTH2_PROXY_COOKIE_SECRET" \
        --dry-run=client -o yaml | kubectl apply -f -
    print_success "Secret created successfully"
}

# Function to deploy oauth2proxy
deploy_oauth2proxy() {
    print_status "Deploying oauth2proxy..."
    helm upgrade --install "$RELEASE_NAME" "$CHART_PATH" \
        --namespace "$NAMESPACE" \
        --values "$CHART_PATH/$VALUES_FILE" \
        --wait \
        --timeout=300s
    print_success "OAuth2 Proxy deployed successfully"
}

# Function to check deployment status
check_status() {
    print_status "Checking deployment status..."
    kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=oauth2proxy"
    kubectl get services -n "$NAMESPACE" -l "app.kubernetes.io/name=oauth2proxy"
}

# Function to show logs
show_logs() {
    print_status "Showing oauth2proxy logs..."
    kubectl logs -n "$NAMESPACE" -l "app.kubernetes.io/name=oauth2proxy" --tail=50 -f
}

# Function to port forward
port_forward() {
    local port=${1:-8090}
    print_status "Setting up port forwarding on port $port..."
    print_warning "Access oauth2proxy at: http://localhost:$port"
    print_warning "This will proxy authenticated requests to Kagent UI"
    print_warning "Press Ctrl+C to stop port forwarding"
    kubectl port-forward -n "$NAMESPACE" service/"$RELEASE_NAME" "$port":8090
}

# Function to cleanup
cleanup() {
    print_status "Cleaning up oauth2proxy deployment..."
    helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" || true
    kubectl delete secret "${RELEASE_NAME}-secrets" -n "$NAMESPACE" || true
    print_success "Cleanup completed"
}

# Function to show secret status (without revealing values)
show_secret_status() {
    print_status "Checking secret configuration status..."
    
    # Check if secrets are available via environment variables
    local env_secrets=()
    if [[ -n "${OAUTH2_PROXY_CLIENT_ID:-}" ]]; then
        env_secrets+=("OAUTH2_PROXY_CLIENT_ID")
    fi
    if [[ -n "${OAUTH2_PROXY_CLIENT_SECRET:-}" ]]; then
        env_secrets+=("OAUTH2_PROXY_CLIENT_SECRET")
    fi
    if [[ -n "${OAUTH2_PROXY_COOKIE_SECRET:-}" ]]; then
        env_secrets+=("OAUTH2_PROXY_COOKIE_SECRET")
    fi
    
    # Check if secrets.yaml exists
    local secrets_file_exists=false
    if [[ -f "secrets.yaml" ]]; then
        secrets_file_exists=true
    fi
    
    # Check if K8s secret exists
    local k8s_secret_exists=false
    if kubectl get secret "${RELEASE_NAME}-secrets" -n "$NAMESPACE" &>/dev/null; then
        k8s_secret_exists=true
    fi
    
    # Display status
    echo ""
    echo "=== Secret Configuration Status ==="
    echo ""
    
    if [[ ${#env_secrets[@]} -gt 0 ]]; then
        print_success "Environment variables configured:"
        for var in "${env_secrets[@]}"; do
            echo "  ✓ $var"
        done
    else
        print_warning "No environment variables set"
    fi
    
    echo ""
    if [[ "$secrets_file_exists" == true ]]; then
        print_success "✓ secrets.yaml file found"
    else
        print_note "✗ secrets.yaml file not found"
    fi
    
    echo ""
    if [[ "$k8s_secret_exists" == true ]]; then
        print_success "✓ Kubernetes secret exists: ${RELEASE_NAME}-secrets"
        echo "Secret keys:"
        kubectl get secret "${RELEASE_NAME}-secrets" -n "$NAMESPACE" -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null | sed 's/^/  - /' || echo "  (unable to list keys)"
    else
        print_note "✗ Kubernetes secret not found: ${RELEASE_NAME}-secrets"
    fi
    
    echo ""
    if [[ ${#env_secrets[@]} -eq 3 ]] || [[ "$secrets_file_exists" == true ]]; then
        print_success "Configuration: Ready to deploy"
    else
        print_warning "Configuration: Missing secrets - run '$0 setup-oauth' first"
    fi
    
    echo ""
    print_note "Secret management methods (in order of precedence):"
    echo "  1. Environment variables (current session)"
    echo "  2. secrets.yaml file (persistent)"
    echo "  3. Kubernetes secrets (deployed)"
    echo ""
    print_note "Values.yaml should NEVER contain secrets!"
}

# Function to validate secrets.yaml matches Kubernetes secret
validate_secrets_match() {
    print_status "Validating secrets.yaml matches Kubernetes secret..."
    
    # Check if secrets.yaml exists
    if [[ ! -f "secrets.yaml" ]]; then
        print_error "secrets.yaml file not found"
        return 1
    fi
    
    # Check if K8s secret exists
    if ! kubectl get secret "${RELEASE_NAME}-secrets" -n "$NAMESPACE" &>/dev/null; then
        print_error "Kubernetes secret '${RELEASE_NAME}-secrets' not found in namespace '$NAMESPACE'"
        print_note "Run '$0 deploy' to create the secret"
        return 1
    fi
    
    # Load values from secrets.yaml
    local yaml_client_id=$(yq eval '.oauth2.clientId' secrets.yaml 2>/dev/null)
    local yaml_client_secret=$(yq eval '.oauth2.clientSecret' secrets.yaml 2>/dev/null)
    local yaml_cookie_secret=$(yq eval '.oauth2.cookieSecret' secrets.yaml 2>/dev/null)
    
    # Get values from Kubernetes secret
    local k8s_client_id=$(kubectl get secret "${RELEASE_NAME}-secrets" -n "$NAMESPACE" -o jsonpath='{.data.client-id}' 2>/dev/null | base64 -d 2>/dev/null)
    local k8s_client_secret=$(kubectl get secret "${RELEASE_NAME}-secrets" -n "$NAMESPACE" -o jsonpath='{.data.client-secret}' 2>/dev/null | base64 -d 2>/dev/null)
    local k8s_cookie_secret=$(kubectl get secret "${RELEASE_NAME}-secrets" -n "$NAMESPACE" -o jsonpath='{.data.cookie-secret}' 2>/dev/null | base64 -d 2>/dev/null)
    
    # Validate values are not empty
    if [[ -z "$yaml_client_id" || "$yaml_client_id" == "null" ]]; then
        print_error "clientId not found in secrets.yaml"
        return 1
    fi
    
    if [[ -z "$yaml_client_secret" || "$yaml_client_secret" == "null" ]]; then
        print_error "clientSecret not found in secrets.yaml"
        return 1
    fi
    
    if [[ -z "$yaml_cookie_secret" || "$yaml_cookie_secret" == "null" ]]; then
        print_error "cookieSecret not found in secrets.yaml"
        return 1
    fi
    
    # Compare values
    local mismatches=()
    
    if [[ "$yaml_client_id" != "$k8s_client_id" ]]; then
        mismatches+=("client-id")
    fi
    
    if [[ "$yaml_client_secret" != "$k8s_client_secret" ]]; then
        mismatches+=("client-secret")
    fi
    
    if [[ "$yaml_cookie_secret" != "$k8s_cookie_secret" ]]; then
        mismatches+=("cookie-secret")
    fi
    
    # Display results
    echo ""
    echo "=== Secret Validation Results ==="
    echo ""
    
    if [[ ${#mismatches[@]} -eq 0 ]]; then
        print_success "✓ All secrets match between secrets.yaml and Kubernetes"
        echo "  ✓ client-id: matches"
        echo "  ✓ client-secret: matches"
        echo "  ✓ cookie-secret: matches"
        return 0
    else
        print_error "✗ Secret mismatches found:"
        for secret in "${mismatches[@]}"; do
            echo "  ✗ $secret: secrets.yaml differs from Kubernetes"
        done
        echo ""
        print_warning "To update Kubernetes secret with secrets.yaml values:"
        echo "  $0 deploy"
        echo ""
        print_note "Or to see current secret status:"
        echo "  $0 secret-status"
        return 1
    fi
}

# Function to update Kubernetes secret with values from secrets.yaml
update_secret() {
    print_status "Updating Kubernetes secret with secrets.yaml values..."
    
    # Check if secrets.yaml exists
    if [[ ! -f "secrets.yaml" ]]; then
        print_error "secrets.yaml file not found"
        print_note "Create secrets.yaml first or run '$0 setup-oauth'"
        return 1
    fi
    
    # Load values from secrets.yaml
    local yaml_client_id=$(yq eval '.oauth2.clientId' secrets.yaml 2>/dev/null)
    local yaml_client_secret=$(yq eval '.oauth2.clientSecret' secrets.yaml 2>/dev/null)
    local yaml_cookie_secret=$(yq eval '.oauth2.cookieSecret' secrets.yaml 2>/dev/null)
    
    # Validate values are not empty
    if [[ -z "$yaml_client_id" || "$yaml_client_id" == "null" ]]; then
        print_error "clientId not found in secrets.yaml"
        return 1
    fi
    
    if [[ -z "$yaml_client_secret" || "$yaml_client_secret" == "null" ]]; then
        print_error "clientSecret not found in secrets.yaml"
        return 1
    fi
    
    if [[ -z "$yaml_cookie_secret" || "$yaml_cookie_secret" == "null" ]]; then
        print_error "cookieSecret not found in secrets.yaml"
        return 1
    fi
    
    # Set environment variables for create_secret function
    export OAUTH2_PROXY_CLIENT_ID="$yaml_client_id"
    export OAUTH2_PROXY_CLIENT_SECRET="$yaml_client_secret"
    export OAUTH2_PROXY_COOKIE_SECRET="$yaml_cookie_secret"
    
    # Check if secret already exists
    if kubectl get secret "${RELEASE_NAME}-secrets" -n "$NAMESPACE" &>/dev/null; then
        print_status "Kubernetes secret exists, updating..."
        kubectl delete secret "${RELEASE_NAME}-secrets" -n "$NAMESPACE"
    else
        print_status "Creating new Kubernetes secret..."
    fi
    
    # Create the secret
    create_secret
    
    # Verify the update
    if kubectl get secret "${RELEASE_NAME}-secrets" -n "$NAMESPACE" &>/dev/null; then
        print_success "Kubernetes secret updated successfully"
        echo ""
        print_note "Secret updated with values from secrets.yaml:"
        echo "  ✓ client-id: ${yaml_client_id:0:10}..."
        echo "  ✓ client-secret: ${yaml_client_secret:0:10}..."
        echo "  ✓ cookie-secret: ${yaml_cookie_secret:0:10}..."
        echo ""
        print_warning "If oauth2proxy is running, restart it to use new secrets:"
        echo "  kubectl rollout restart deployment/$RELEASE_NAME -n $NAMESPACE"
    else
        print_error "Failed to update Kubernetes secret"
        return 1
    fi
}

# Function to show help
show_help() {
    echo "Standalone Kagent OAuth2 Proxy Deployment Script"
    echo ""
    echo "USAGE:"
    echo "  $0 <command> [options]"
    echo ""
    echo "COMMANDS:"
    echo "  setup-oauth     Interactive GitHub OAuth app setup wizard"
    echo "  check-oauth     Validate OAuth app configuration"
    echo "  secret-status   Show current secret configuration status"
    echo "  secret-validate Validate secrets.yaml matches Kubernetes secret"
    echo "  secret-update   Update Kubernetes secret with secrets.yaml values"
    echo "  deploy          Deploy oauth2proxy with all dependencies"
    echo "  status          Check deployment status"
    echo "  logs            Show oauth2proxy logs (follows)"
    echo "  port-forward [port]  Set up port forwarding (default: 8090)"
    echo "  cleanup         Remove oauth2proxy deployment"
    echo "  help            Show this help message"
    echo ""
    echo "SETUP WORKFLOW:"
    echo "  1. $0 setup-oauth       # Interactive OAuth app creation"
    echo "  2. $0 deploy            # Deploy oauth2proxy"
    echo "  3. $0 port-forward      # Access via localhost"
    echo ""
    echo "EXAMPLES:"
    echo "  $0 setup-oauth            # Setup GitHub OAuth app interactively"
    echo "  $0 secret-status          # Check secret configuration"
    echo "  $0 deploy                 # Deploy oauth2proxy"
    echo "  $0 port-forward           # Port forward on default port 8090"
    echo "  $0 port-forward 9090      # Port forward on port 9090"
    echo "  $0 logs                   # Show and follow logs"
    echo "  $0 cleanup                # Remove everything"
    echo ""
    echo "MANUAL OAUTH APP SETUP:"
    echo "  If you prefer to create the OAuth app manually:"
    echo ""
    echo "  1. Go to: https://github.com/settings/applications/new"
    echo "  2. Fill in:"
    echo "     - Application name: Kagent OAuth2 Proxy"
    echo "     - Homepage URL: http://localhost:8090"
    echo "     - Authorization callback URL: http://localhost:8090/oauth2/callback"
    echo "  3. Click 'Register application'"
    echo "  4. Note the Client ID and Client Secret"
    echo "  5. Create secrets.yaml file:"
    echo "     cp secrets.yaml.example secrets.yaml"
    echo "     # Edit secrets.yaml with your OAuth credentials"
    echo ""
    echo "  Alternative: Set environment variables:"
    echo "     export OAUTH2_PROXY_CLIENT_ID=\"your_client_id\""
    echo "     export OAUTH2_PROXY_CLIENT_SECRET=\"your_client_secret\""
    echo "     export OAUTH2_PROXY_COOKIE_SECRET=\"\$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')\""
    echo ""
    echo "REQUIREMENTS:"
    echo "  yq                          YAML processor (install: brew install yq)"
    echo "  kubectl                     Kubernetes CLI"
    echo "  helm                        Helm package manager"
    echo ""
    echo "REQUIRED CREDENTIALS:"
    echo "  OAUTH2_PROXY_CLIENT_ID      GitHub OAuth App Client ID (20 chars)"
    echo "  OAUTH2_PROXY_CLIENT_SECRET  GitHub OAuth App Client Secret"
    echo "  OAUTH2_PROXY_COOKIE_SECRET  Random secret for cookie encryption (32+ chars)"
    echo ""
    echo "GITHUB OAUTH APP CONFIGURATION:"
    echo "  For local development:"
    echo "    Homepage URL: http://localhost:8090"
    echo "    Callback URL: http://localhost:8090/oauth2/callback"
    echo ""
    echo "  For production:"
    echo "    Homepage URL: https://yourdomain.com"
    echo "    Callback URL: https://yourdomain.com/oauth2/callback"
    echo ""
    echo "TROUBLESHOOTING:"
    echo "  - OAuth callback URL mismatch: Ensure GitHub OAuth app callback URL ends with '/oauth2/callback'"
    echo "  - 'Invalid client' error: Check GitHub OAuth CLIENT_ID and CLIENT_SECRET are correct"
    echo "  - Cookie errors: Regenerate COOKIE_SECRET with sufficient length (32+ chars)"
    echo "  - GitHub org access: Ensure GitHub OAuth app is approved by your organization"
}

# Main script logic
case "${1:-}" in
    "setup-oauth")
        setup_oauth_app
        ;;
    "check-oauth")
        check_oauth_app
        ;;
    "secret-status")
        show_secret_status
        ;;
    "secret-validate")
        validate_secrets_match
        ;;
    "secret-update")
        update_secret
        ;;
    "deploy")
        validate_values_file
        check_env_vars
        check_oauth_app
        create_secret
        deploy_oauth2proxy
        check_status
        echo ""
        print_success "OAuth2 Proxy deployed successfully!"
        print_warning "Next steps:"
        echo "  1. Run: $0 port-forward"
        echo "  2. Access: http://localhost:8090"
        echo "  3. Authenticate with GitHub"
        ;;
    "status")
        check_status
        ;;
    "logs")
        show_logs
        ;;
    "port-forward")
        port_forward "${2:-8090}"
        ;;
    "cleanup")
        cleanup
        ;;
    "help"|"--help"|"-h")
        show_help
        ;;
    *)
        print_error "Unknown command: ${1:-}"
        echo ""
        show_help
        exit 1
        ;;
esac 
