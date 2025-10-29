#!/bin/bash
# Registry Authentication Helper
# Helps setup authentication for Quay.io and other registries

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

echo "=========================================="
echo "  Registry Authentication Helper"
echo "=========================================="
echo ""

# Detect container tool
if command -v podman >/dev/null 2>&1; then
    CONTAINER_TOOL="podman"
elif command -v docker >/dev/null 2>&1; then
    CONTAINER_TOOL="docker"
else
    log_error "Neither podman nor docker found. Please install one."
    exit 1
fi

log_info "Using: ${CONTAINER_TOOL}"
echo ""

# Main menu
echo "Select registry type:"
echo "  1. Quay.io (public)"
echo "  2. Red Hat Quay (on ROSA)"
echo "  3. Other registry"
echo ""
read -p "Enter choice (1-3): " registry_choice

case $registry_choice in
    1)
        REGISTRY="quay.io"
        ;;
    2)
        read -p "Enter Quay hostname (e.g., quay-registry.apps.cluster.com): " REGISTRY
        ;;
    3)
        read -p "Enter registry hostname: " REGISTRY
        ;;
    *)
        log_error "Invalid choice"
        exit 1
        ;;
esac

echo ""
log_info "Selected registry: ${REGISTRY}"
echo ""

# Authentication method
echo "Select authentication method:"
echo "  1. Username and Password"
echo "  2. Robot Account (Quay)"
echo "  3. Token"
echo ""
read -p "Enter choice (1-3): " auth_choice

case $auth_choice in
    1)
        # Username/Password
        read -p "Username: " username
        read -sp "Password: " password
        echo ""
        
        log_info "Attempting login..."
        if ${CONTAINER_TOOL} login "${REGISTRY}" -u "${username}" -p "${password}"; then
            log_success "Successfully authenticated to ${REGISTRY}"
        else
            log_error "Authentication failed"
            exit 1
        fi
        ;;
        
    2)
        # Robot Account (Quay specific)
        log_info "Quay Robot Account Authentication"
        echo ""
        echo "To create a robot account in Quay:"
        echo "  1. Login to Quay UI"
        echo "  2. Go to your Organization"
        echo "  3. Click 'Robot Accounts' tab"
        echo "  4. Click 'Create Robot Account'"
        echo "  5. Give it a name (e.g., 'tekton_builder')"
        echo "  6. Grant 'Write' permissions to repositories"
        echo ""
        
        read -p "Robot account username (format: org+robotname): " robot_user
        read -sp "Robot account token: " robot_token
        echo ""
        
        log_info "Attempting login with robot account..."
        if ${CONTAINER_TOOL} login "${REGISTRY}" -u "${robot_user}" -p "${robot_token}"; then
            log_success "Successfully authenticated to ${REGISTRY}"
            
            # Save credentials for Kubernetes secret
            log_info "Creating Kubernetes secret YAML..."
            cat > quay-robot-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: quay-robot-secret
  namespace: secure-supply-chain
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $(cat ~/.${CONTAINER_TOOL}/auth.json | base64 -w 0)
---
# Alternative: using username/password format
apiVersion: v1
kind: Secret
metadata:
  name: quay-credentials
  namespace: secure-supply-chain
type: Opaque
stringData:
  username: ${robot_user}
  password: ${robot_token}
EOF
            log_success "Secret YAML created: quay-robot-secret.yaml"
            log_info "Apply with: oc apply -f quay-robot-secret.yaml"
        else
            log_error "Authentication failed"
            exit 1
        fi
        ;;
        
    3)
        # Token authentication
        read -p "Username (or leave empty): " username
        read -sp "Token: " token
        echo ""
        
        if [ -z "${username}" ]; then
            username="token"
        fi
        
        log_info "Attempting login with token..."
        if ${CONTAINER_TOOL} login "${REGISTRY}" -u "${username}" -p "${token}"; then
            log_success "Successfully authenticated to ${REGISTRY}"
        else
            log_error "Authentication failed"
            exit 1
        fi
        ;;
esac

echo ""
log_info "Verifying authentication..."

# Test authentication by trying to access registry
if ${CONTAINER_TOOL} login "${REGISTRY}" --get-login >/dev/null 2>&1; then
    current_user=$(${CONTAINER_TOOL} login "${REGISTRY}" --get-login)
    log_success "Currently logged in as: ${current_user}"
else
    log_warning "Unable to verify login status"
fi

# Check if we can search
log_info "Testing registry access..."
if ${CONTAINER_TOOL} search "${REGISTRY}/library/alpine" --limit 1 >/dev/null 2>&1; then
    log_success "Registry is accessible"
else
    log_warning "Unable to search registry (this is normal for some registries)"
fi

echo ""
log_info "Authentication Details:"
echo "  Registry: ${REGISTRY}"
echo "  Auth file: ~/.${CONTAINER_TOOL}/auth.json"
echo ""

# Create helper scripts
log_info "Creating helper scripts..."

# Script to test push access
cat > test-registry-push.sh <<'EOFTEST'
#!/bin/bash
# Test if we can push to the registry

REGISTRY="${1:-quay.io}"
TEST_ORG="${2:-$(whoami)}"
TEST_IMAGE="${REGISTRY}/${TEST_ORG}/test-push:$(date +%s)"

echo "Testing push access to: ${TEST_IMAGE}"

# Create a tiny test image
cat > Dockerfile.test <<EOF
FROM alpine:latest
CMD ["echo", "test"]
EOF

# Build
if command -v podman >/dev/null 2>&1; then
    TOOL="podman"
else
    TOOL="docker"
fi

${TOOL} build -t "${TEST_IMAGE}" -f Dockerfile.test .

# Try to push
if ${TOOL} push "${TEST_IMAGE}"; then
    echo "✅ Successfully pushed to registry"
    echo "✅ Push access confirmed"
    
    # Cleanup
    ${TOOL} rmi "${TEST_IMAGE}"
    rm Dockerfile.test
    
    exit 0
else
    echo "❌ Failed to push to registry"
    echo "Check:"
    echo "  1. Organization/namespace exists"
    echo "  2. You have write permissions"
    echo "  3. Authentication is valid"
    exit 1
fi
EOFTEST

chmod +x test-registry-push.sh

log_success "Created test-registry-push.sh"
log_info "Test push access with: ./test-registry-push.sh ${REGISTRY} your-org"

# Create script to create OpenShift secret
cat > create-registry-secret.sh <<EOFSECRET
#!/bin/bash
# Create OpenShift secret from current auth

NAMESPACE="\${1:-secure-supply-chain}"
SECRET_NAME="\${2:-registry-credentials}"

if command -v podman >/dev/null 2>&1; then
    AUTH_FILE=~/.${CONTAINER_TOOL}/auth.json
elif command -v docker >/dev/null 2>&1; then
    AUTH_FILE=~/.docker/config.json
else
    echo "No container tool found"
    exit 1
fi

if [ ! -f "\${AUTH_FILE}" ]; then
    echo "❌ Auth file not found: \${AUTH_FILE}"
    exit 1
fi

echo "Creating secret '\${SECRET_NAME}' in namespace '\${NAMESPACE}'..."

oc create secret generic "\${SECRET_NAME}" \\
    --from-file=.dockerconfigjson="\${AUTH_FILE}" \\
    --type=kubernetes.io/dockerconfigjson \\
    --namespace="\${NAMESPACE}" \\
    --dry-run=client -o yaml | oc apply -f -

echo "✅ Secret created successfully"
echo ""
echo "Link to service account:"
echo "  oc secrets link default \${SECRET_NAME} --for=pull -n \${NAMESPACE}"
echo "  oc secrets link builder \${SECRET_NAME} -n \${NAMESPACE}"
EOFSECRET

chmod +x create-registry-secret.sh

log_success "Created create-registry-secret.sh"
log_info "Create OpenShift secret with: ./create-registry-secret.sh [namespace] [secret-name]"

echo ""
echo "=========================================="
log_success "Authentication Setup Complete!"
echo "=========================================="
echo ""
log_info "Next Steps:"
echo "  1. Test push access: ./test-registry-push.sh ${REGISTRY} your-org"
echo "  2. Create OpenShift secret: ./create-registry-secret.sh"
echo "  3. Build and sign your image with the improved script"
echo ""
log_info "Troubleshooting:"
echo "  View auth config: cat ~/.${CONTAINER_TOOL}/auth.json"
echo "  Re-login: ${CONTAINER_TOOL} logout ${REGISTRY} && ${CONTAINER_TOOL} login ${REGISTRY}"
echo "  Check credentials: ${CONTAINER_TOOL} login ${REGISTRY} --get-login"
echo ""
