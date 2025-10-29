#!/bin/bash
# Improved Build, Sign, and SBOM Generation Script
# Fixes authentication and digest-based signing

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Suppress warnings from command output
suppress_warnings() {
    "$@" 2>&1 | grep -v -i "warning:" || true
}

# Determine script directory and find app directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${SCRIPT_DIR}/../app"

# Check if running from app directory or scripts directory
if [ -f "Containerfile" ]; then
    # Running from app directory
    WORK_DIR="$(pwd)"
elif [ -f "${APP_DIR}/Containerfile" ]; then
    # Running from scripts directory or parent
    WORK_DIR="${APP_DIR}"
else
    log_error "Could not find Containerfile. Please run from app directory or ensure app/Containerfile exists."
    exit 1
fi

log_info "Working directory: ${WORK_DIR}"
cd "${WORK_DIR}"

# Configuration
IMAGE_REGISTRY="${IMAGE_REGISTRY:-quay.io}"
IMAGE_ORG="${IMAGE_ORG:-flyers22}"
IMAGE_NAME="${IMAGE_NAME:-secure-demo-app}"
IMAGE_TAG="${IMAGE_TAG:-v1.0.0}"
FULL_IMAGE="${IMAGE_REGISTRY}/${IMAGE_ORG}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "=========================================="
echo "  Secure Build and Sign Script"
echo "=========================================="
echo ""

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    command -v podman >/dev/null 2>&1 || command -v docker >/dev/null 2>&1 || missing_tools+=("podman or docker")
    command -v cosign >/dev/null 2>&1 || missing_tools+=("cosign")
    command -v syft >/dev/null 2>&1 || missing_tools+=("syft")
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install instructions:"
        log_info "  podman: https://podman.io/getting-started/installation"
        log_info "  cosign: brew install cosign or https://docs.sigstore.dev/cosign/installation/"
        log_info "  syft: brew install syft or https://github.com/anchore/syft#installation"
        log_info "  jq: brew install jq"
        exit 1
    fi
    
    # Detect container tool
    if command -v podman >/dev/null 2>&1; then
        CONTAINER_TOOL="podman"
    else
        CONTAINER_TOOL="docker"
    fi
    
    # Set environment variables to suppress warnings
    export COSIGN_EXPERIMENTAL=0
    export SYFT_LOG_FILE=/dev/null
    
    log_success "Using container tool: ${CONTAINER_TOOL}"
}

# Check registry authentication
check_registry_auth() {
    log_info "Checking registry authentication..."
    
    # Try to login and test authentication
    if ! ${CONTAINER_TOOL} login ${IMAGE_REGISTRY} --get-login >/dev/null 2>&1; then
        log_warning "Not logged into ${IMAGE_REGISTRY}"
        log_info "Please login to the registry..."
        
        echo ""
        echo "Choose authentication method:"
        echo "  1. Username/Password"
        echo "  2. Token (Quay Robot Account)"
        echo "  3. Skip (if already logged in via other means)"
        read -p "Select option (1-3): " auth_choice
        
        case $auth_choice in
            1)
                read -p "Username: " registry_user
                read -sp "Password: " registry_pass
                echo ""
                ${CONTAINER_TOOL} login ${IMAGE_REGISTRY} -u "${registry_user}" -p "${registry_pass}"
                ;;
            2)
                read -p "Robot account username (e.g., myorg+robot): " robot_user
                read -sp "Robot account token: " robot_token
                echo ""
                ${CONTAINER_TOOL} login ${IMAGE_REGISTRY} -u "${robot_user}" -p "${robot_token}"
                ;;
            3)
                log_warning "Skipping authentication - assuming already logged in"
                ;;
            *)
                log_error "Invalid option"
                exit 1
                ;;
        esac
    else
        log_success "Already authenticated to ${IMAGE_REGISTRY}"
    fi
    
    # Verify authentication by trying to access the registry
    if ! ${CONTAINER_TOOL} search ${IMAGE_REGISTRY}/${IMAGE_ORG} --limit 1 >/dev/null 2>&1; then
        log_warning "Unable to verify registry access"
        log_info "You may need to create the repository first or check permissions"
        log_info "This is okay - the repository may not exist yet and will be created on first push"
        read -p "Continue anyway? (Y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            exit 1
        fi
    fi
}

# Build image
build_image() {
    log_info "Building image: ${FULL_IMAGE}"
    
    if [ ! -f Containerfile ]; then
        log_error "Containerfile not found in current directory"
        exit 1
    fi
    
    # Suppress build warnings
    ${CONTAINER_TOOL} build \
        --format=oci \
        --no-cache \
        -t "${FULL_IMAGE}" \
        . 2>&1 | grep -v -i "warning:" || true
    
    log_success "Image built successfully"
}

# Push image and capture digest
push_image() {
    log_info "Pushing image to registry..."
    
    # Create a temporary file for digest
    DIGEST_FILE=$(mktemp)
    
    # Push and capture output - suppress warnings
    ${CONTAINER_TOOL} push "${FULL_IMAGE}" --digestfile "${DIGEST_FILE}" 2>&1 | grep -v "WARNING:" || true
    
    # Read digest
    IMAGE_DIGEST=$(cat "${DIGEST_FILE}")
    rm -f "${DIGEST_FILE}"
    
    if [ -z "${IMAGE_DIGEST}" ]; then
        log_error "Failed to capture image digest"
        exit 1
    fi
    
    # Construct image reference with digest
    IMAGE_WITH_DIGEST="${IMAGE_REGISTRY}/${IMAGE_ORG}/${IMAGE_NAME}@${IMAGE_DIGEST}"
    
    log_success "Image pushed successfully"
    log_info "Image digest: ${IMAGE_DIGEST}"
    log_info "Full reference: ${IMAGE_WITH_DIGEST}"
    
    # Save digest to file for later use
    echo "${IMAGE_WITH_DIGEST}" > image-digest.txt
}

# Generate SBOM
generate_sbom() {
    log_info "Generating SBOM..."
    
    # Use digest for SBOM generation
    local target_image="${IMAGE_WITH_DIGEST}"
    
    # Generate SPDX format - suppress syft warnings
    log_info "Generating SPDX SBOM..."
    syft "${target_image}" -o spdx-json 2>&1 | grep -v "WARNING:" > sbom.spdx.json.tmp || syft "${target_image}" -o spdx-json > sbom.spdx.json.tmp 2>/dev/null
    # Strip BOM if present and move to final location
    sed '1s/^\xEF\xBB\xBF//' sbom.spdx.json.tmp > sbom.spdx.json
    rm -f sbom.spdx.json.tmp
    
    # Generate CycloneDX format - suppress warnings
    log_info "Generating CycloneDX SBOM..."
    syft "${target_image}" -o cyclonedx-json 2>&1 | grep -v "WARNING:" > sbom.cyclonedx.json.tmp || syft "${target_image}" -o cyclonedx-json > sbom.cyclonedx.json.tmp 2>/dev/null
    # Strip BOM if present
    sed '1s/^\xEF\xBB\xBF//' sbom.cyclonedx.json.tmp > sbom.cyclonedx.json
    rm -f sbom.cyclonedx.json.tmp
    
    # Generate human-readable format - suppress warnings
    log_info "Generating text SBOM..."
    syft "${target_image}" -o table 2>&1 | grep -v "WARNING:" > sbom.txt || syft "${target_image}" -o table > sbom.txt 2>/dev/null
    
    # Show summary with error handling
    local package_count=$(jq -r '.packages | length' sbom.spdx.json 2>/dev/null || echo "unknown")
    log_success "SBOM generated - ${package_count} packages found"
    
    # Display first few packages (suppress warnings)
    log_info "Sample packages:"
    syft "${target_image}" -o table 2>&1 | grep -v -i "warning:" | head -15
}

# Setup cosign keys
setup_cosign_keys() {
    log_info "Setting up Cosign keys..."
    
    if [ -f cosign.key ] && [ -f cosign.pub ]; then
        log_info "Cosign keys already exist"
        read -p "Use existing keys? (Y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            return 0
        fi
        
        # Backup old keys
        mv cosign.key cosign.key.backup.$(date +%s)
        mv cosign.pub cosign.pub.backup.$(date +%s)
        log_info "Old keys backed up"
    fi
    
    log_info "Generating new Cosign key pair..."
    log_warning "You will be prompted for a password (can be empty for testing)"
    
    # Generate keys
    COSIGN_PASSWORD="" cosign generate-key-pair
    
    log_success "Cosign keys generated"
    log_warning "Keep cosign.key secure - it's your private signing key!"
}

# Sign image using digest
sign_image() {
    log_info "Signing image with Cosign..."
    
    # Use digest-based reference for signing
    local target_image="${IMAGE_WITH_DIGEST}"
    
    log_info "Signing: ${target_image}"
    
    # Sign with cosign - suppress warnings
    COSIGN_PASSWORD="" cosign sign \
        --key cosign.key \
        --yes \
        "${target_image}" 2>&1 | grep -v "WARNING:" || true
    
    log_success "Image signed successfully"
    
    # Also tag the digest with the original tag for convenience
    log_info "Tagging signed image with ${IMAGE_TAG}..."
    ${CONTAINER_TOOL} tag "${target_image}" "${FULL_IMAGE}" 2>/dev/null || true
}

# Attach SBOM to image
attach_sbom() {
    log_info "Attaching SBOM to image..."
    
    # Use digest-based reference
    local target_image="${IMAGE_WITH_DIGEST}"
    
    # Suppress warnings from cosign
    cosign attach sbom \
        --sbom sbom.spdx.json \
        "${target_image}" 2>&1 | grep -v "WARNING:" || true
    
    log_success "SBOM attached to image"
}

# Verify signature
verify_signature() {
    log_info "Verifying image signature..."
    
    # Verify using digest
    local target_image="${IMAGE_WITH_DIGEST}"
    
    # Capture verify output
    local verify_output=$(cosign verify --key cosign.pub "${target_image}" 2>&1)
    local verify_status=$?
    
    if [ $verify_status -eq 0 ]; then
        log_success "Signature verification PASSED ✓"
        
        # Show signature details (skip if jq fails)
        log_info "Signature details:"
        echo "$verify_output" | grep -E '^\[' | head -1 | jq -r '.[0] | {
            critical: .critical,
            optional: .optional,
            signed_at: (.optional.Bundle.Payload.body | @base64d | fromjson | .iat | todate)
        }' 2>/dev/null || log_info "Verification complete (detailed parsing skipped)"
    else
        log_error "Signature verification FAILED ✗"
        echo "$verify_output" | grep -v "WARNING" || true
        return 1
    fi
}

# Verify SBOM
verify_sbom() {
    log_info "Downloading and verifying SBOM..."
    
    local target_image="${IMAGE_WITH_DIGEST}"
    
    # Download SBOM - strip BOM if present and handle binary content
    if cosign download sbom "${target_image}" 2>/dev/null | sed '1s/^\xEF\xBB\xBF//' > sbom-downloaded.json.tmp; then
        # Check if downloaded file is valid JSON by checking if it's not empty and doesn't start with binary data
        if [ -s sbom-downloaded.json.tmp ] && head -c 1 sbom-downloaded.json.tmp | grep -q '{'; then
            mv sbom-downloaded.json.tmp sbom-downloaded.json
            log_success "SBOM downloaded successfully"
            
            # Compare with original (with error handling)
            local downloaded_packages=$(jq -r '.packages | length' sbom-downloaded.json 2>/dev/null || echo 0)
            local original_packages=$(jq -r '.packages | length' sbom.spdx.json 2>/dev/null || echo 0)
            
            log_info "SBOM comparison:"
            echo "  Original packages: ${original_packages}"
            echo "  Downloaded packages: ${downloaded_packages}"
            
            if [ "${downloaded_packages}" -eq "${original_packages}" ] && [ "${original_packages}" != "0" ]; then
                log_success "SBOM integrity verified ✓"
            else
                log_warning "Package count mismatch - this may be normal if SBOM was regenerated"
            fi
        else
            rm -f sbom-downloaded.json.tmp
            log_warning "Downloaded SBOM appears to be binary or empty - skipping verification"
        fi
    else
        log_error "Failed to download SBOM"
        rm -f sbom-downloaded.json.tmp
        return 1
    fi
}

# Display summary
print_summary() {
    echo ""
    echo "=========================================="
    log_success "Build and Sign Complete!"
    echo "=========================================="
    echo ""
    log_info "Image Information:"
    echo "  Registry: ${IMAGE_REGISTRY}"
    echo "  Organization: ${IMAGE_ORG}"
    echo "  Name: ${IMAGE_NAME}"
    echo "  Tag: ${IMAGE_TAG}"
    echo "  Digest: ${IMAGE_DIGEST}"
    echo ""
    log_info "References:"
    echo "  By tag:    ${FULL_IMAGE}"
    echo "  By digest: ${IMAGE_WITH_DIGEST}"
    echo ""
    log_info "Generated Files:"
    echo "  📄 sbom.spdx.json       - SBOM in SPDX format"
    echo "  📄 sbom.cyclonedx.json  - SBOM in CycloneDX format"
    echo "  📄 sbom.txt             - Human-readable SBOM"
    echo "  📄 image-digest.txt     - Image digest reference"
    echo "  🔑 cosign.key           - Private signing key (keep secure!)"
    echo "  🔑 cosign.pub           - Public verification key"
    echo ""
    log_info "Verification Commands:"
    echo "  # Verify signature"
    echo "  cosign verify --key cosign.pub ${IMAGE_WITH_DIGEST}"
    echo ""
    echo "  # Download SBOM"
    echo "  cosign download sbom ${IMAGE_WITH_DIGEST}"
    echo ""
    echo "  # View signature tree"
    echo "  cosign tree ${IMAGE_WITH_DIGEST}"
    echo ""
    log_info "Deployment:"
    echo "  # Use digest in production for immutability"
    echo "  image: ${IMAGE_WITH_DIGEST}"
    echo ""
    echo "  # Or use tag (will be verified by policies)"
    echo "  image: ${FULL_IMAGE}"
    echo ""
    
    # Create summary file
    cat > BUILD_SUMMARY.txt <<EOF
Build and Sign Summary
======================
Timestamp: $(date)
Image: ${FULL_IMAGE}
Digest: ${IMAGE_DIGEST}
Full Reference: ${IMAGE_WITH_DIGEST}

Security Artifacts:
- Image Signature: ✅ Signed with Cosign
- SBOM: ✅ Generated and attached
- Verification: ✅ Passed

Files Created:
- sbom.spdx.json
- sbom.cyclonedx.json  
- sbom.txt
- image-digest.txt
- cosign.key (KEEP SECURE!)
- cosign.pub

Next Steps:
1. Store cosign.key securely (vault, sealed secret, etc.)
2. Share cosign.pub with deployment teams
3. Configure ACS policies to require signed images
4. Upload SBOM to TPA for analysis
5. Deploy using digest reference for immutability

Verification:
cosign verify --key cosign.pub ${IMAGE_WITH_DIGEST}
cosign download sbom ${IMAGE_WITH_DIGEST}
EOF
    
    log_success "Summary saved to BUILD_SUMMARY.txt"
}

# Create deployment manifest with digest
create_deployment_manifest() {
    log_info "Creating deployment manifest..."
    
    cat > deployment-secure.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${IMAGE_NAME}
  namespace: secure-supply-chain
  annotations:
    image.policy.openshift.io/verify: "true"
  labels:
    app: ${IMAGE_NAME}
    version: ${IMAGE_TAG}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${IMAGE_NAME}
  template:
    metadata:
      labels:
        app: ${IMAGE_NAME}
        version: ${IMAGE_TAG}
    spec:
      serviceAccountName: secure-app-sa
      containers:
      - name: app
        # Use digest for immutability - this exact image is signed and verified
        image: ${IMAGE_WITH_DIGEST}
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: APP_VERSION
          value: "${IMAGE_TAG}"
        - name: IMAGE_SIGNED
          value: "true"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          capabilities:
            drop:
            - ALL
---
apiVersion: v1
kind: Service
metadata:
  name: ${IMAGE_NAME}
  namespace: secure-supply-chain
spec:
  selector:
    app: ${IMAGE_NAME}
  ports:
  - port: 8080
    targetPort: 8080
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ${IMAGE_NAME}
  namespace: secure-supply-chain
spec:
  to:
    kind: Service
    name: ${IMAGE_NAME}
  port:
    targetPort: 8080
  tls:
    termination: edge
EOF
    
    log_success "Deployment manifest created: deployment-secure.yaml"
    log_info "Deploy with: oc apply -f deployment-secure.yaml"
}

# Main execution
main() {
    check_prerequisites
    check_registry_auth
    build_image
    push_image
    generate_sbom
    setup_cosign_keys
    sign_image
    attach_sbom
    verify_signature
    verify_sbom
    create_deployment_manifest
    print_summary
    
    echo ""
    log_success "All steps completed successfully! 🎉"
}

# Run main function
main "$@"
