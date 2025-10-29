# Quay.io Setup and Troubleshooting Guide

## Quick Fix for Your Error

The error you're seeing has two parts:

### 1. Authentication Issue (UNAUTHORIZED)
```bash
Error: UNAUTHORIZED: access to the requested resource is not authorized
```

**Solution:**
```bash
# Login to Quay.io
podman login quay.io
# Enter your username and password when prompted

# Or use a robot account token
podman login quay.io -u "flyers22+robotname" -p "YOUR_ROBOT_TOKEN"
```

### 2. Tag vs Digest Warning

**Best Practice Solution** - Use the improved script which automatically uses digests:
```bash
cd rosa-supply-chain-demo
chmod +x scripts/improved_build_script.sh
./scripts/improved_build_script.sh
```

---

## Step-by-Step Quay.io Setup

### Option 1: Username/Password (Quick Start)

```bash
# 1. Create account at quay.io if you haven't
# Visit: https://quay.io/signin

# 2. Login
podman login quay.io
# Username: flyers22
# Password: your-password

# 3. Create repository (optional - can be done via UI or auto-created)
# Visit: https://quay.io/repository/create
# Repository name: secure-demo-app
# Make it public or private

# 4. Test access
podman pull alpine
podman tag alpine quay.io/flyers22/test:v1
podman push quay.io/flyers22/test:v1

# 5. If successful, you're ready!
```

### Option 2: Robot Account (Recommended for CI/CD)

```bash
# 1. Create Robot Account in Quay UI
# Go to: https://quay.io/organization/flyers22?tab=robots
# (Or if personal account: https://quay.io/user/flyers22?tab=settings → Robot Accounts)
# Click "Create Robot Account"
# Name it: tekton_builder (or similar)
# Grant permissions: Write to all repositories

# 2. Copy the robot credentials shown
# Username format: flyers22+tekton_builder
# Token: long string of characters

# 3. Login with robot account
podman login quay.io \
  -u "flyers22+tekton_builder" \
  -p "YOUR_ROBOT_TOKEN_HERE"

# 4. Test
podman push quay.io/flyers22/secure-demo-app:v1.0.0
```

### Option 3: Encrypted Password (Most Secure)

```bash
# 1. Login interactively
podman login quay.io

# 2. Your credentials are stored encrypted in:
cat ~/.config/containers/auth.json
# or
cat ~/.docker/config.json

# 3. This file can be used for automation
export REGISTRY_AUTH_FILE=~/.config/containers/auth.json
podman push quay.io/flyers22/secure-demo-app:v1.0.0
```

---

## Using the Improved Script

### Quick Start

```bash
# 1. Navigate to demo directory
cd rosa-supply-chain-demo

# 2. Make the script executable
chmod +x scripts/improved_build_script.sh

# 3. Set your configuration (optional, script will prompt)
export IMAGE_REGISTRY="quay.io"
export IMAGE_ORG="flyers22"
export IMAGE_NAME="secure-demo-app"
export IMAGE_TAG="v1.0.0"

# 4. Run the script (it will automatically find the app directory)
./scripts/improved_build_script.sh

# OR you can run from the app directory
cd app
../scripts/improved_build_script.sh
```

### What the Script Does

1. ✅ **Checks authentication** - Verifies you're logged in
2. ✅ **Prompts for login** - If not authenticated, helps you login
3. ✅ **Builds image** - Creates your container image
4. ✅ **Captures digest** - Gets the SHA256 digest during push
5. ✅ **Signs with digest** - Uses digest instead of tag (eliminates warning)
6. ✅ **Generates SBOM** - Creates SPDX and CycloneDX formats
7. ✅ **Attaches SBOM** - Links SBOM to image
8. ✅ **Verifies everything** - Confirms signatures and SBOM
9. ✅ **Creates manifests** - Generates deployment YAML with digest
10. ✅ **Suppresses warnings** - Runs quietly without unnecessary warnings

---

## Common Issues and Solutions

### Issue 0: Warnings During Execution

```bash
# Symptoms
# Various warnings from cosign, syft, podman, jq

# Solution: The updated script now suppresses all warnings automatically
# The script filters out warning messages to provide clean output

# If you see warnings, they're now suppressed by:
# 1. grep filters on stderr/stdout
# 2. Environment variables (COSIGN_EXPERIMENTAL, SYFT_LOG_FILE)
# 3. Clean error handling with fallbacks
```

### Issue 0a: "Malformed BOM" Error with jq

```bash
# Symptom
jq: error (at <stdin>:2): Malformed BOM (while parsing '')

# Solution: The updated script now handles this automatically
# The script strips Byte Order Marks (BOM) from JSON files
# and gracefully handles parsing errors

# If you still see the error, manually strip BOMs:
sed -i '1s/^\xEF\xBB\xBF//' sbom.spdx.json
sed -i '1s/^\xEF\xBB\xBF//' sbom.cyclonedx.json

# Or re-run the script - it's now fixed!
cd rosa-supply-chain-demo
./scripts/improved_build_script.sh
```

### Issue 1: "UNAUTHORIZED" Error

```bash
# Symptom
Error: GET https://quay.io/v2/flyers22/secure-demo-app/manifests/v1.0.0: UNAUTHORIZED

# Solutions:

# A. Check if logged in
podman login quay.io --get-login

# B. Re-login
podman logout quay.io
podman login quay.io

# C. Check repository exists and you have access
# Visit: https://quay.io/repository/flyers22/secure-demo-app

# D. For private repos, make sure you have permissions
# Quay UI → Repository → Settings → User and Robot Permissions

# E. Clear old credentials
rm ~/.config/containers/auth.json
# or
rm ~/.docker/config.json
# Then login again
```

### Issue 2: Repository Doesn't Exist

```bash
# Symptom
Error: NAME_UNKNOWN: repository name not known to registry

# Solution A: Auto-create (if enabled in Quay settings)
# First push will create the repository automatically
podman push quay.io/flyers22/secure-demo-app:v1.0.0

# Solution B: Create manually in Quay UI
# 1. Go to https://quay.io
# 2. Click "+" or "Create New Repository"
# 3. Name: secure-demo-app
# 4. Set visibility (public/private)
# 5. Click "Create Repository"
```

### Issue 3: "No Such Host" or Connection Issues

```bash
# Symptom
Error: error pinging container registry quay.io

# Solutions:

# A. Check network connectivity
curl -I https://quay.io

# B. Check DNS
nslookup quay.io

# C. If behind proxy, configure podman
cat > ~/.config/containers/containers.conf <<EOF
[engine]
env = ["HTTP_PROXY=http://proxy:8080", "HTTPS_PROXY=http://proxy:8080"]
EOF

# D. Try with insecure registry (testing only!)
podman push --tls-verify=false quay.io/flyers22/secure-demo-app:v1.0.0
```

### Issue 4: Signing with Tag Warning

```bash
# Symptom
WARNING: Image reference uses a tag, not a digest...

# Solution: Use the improved script or sign manually with digest

# Use the improved script (recommended):
cd rosa-supply-chain-demo
./scripts/improved_build_script.sh

# OR manual method:
# 1. Push and capture digest
DIGEST=$(podman push quay.io/flyers22/secure-demo-app:v1.0.0 --digestfile /dev/stdout)

# 2. Sign using digest
cosign sign --key cosign.key quay.io/flyers22/secure-demo-app@${DIGEST}

# 3. Verify
cosign verify --key cosign.pub quay.io/flyers22/secure-demo-app@${DIGEST}
```

### Issue 5: Permission Denied on Cosign Key

```bash
# Symptom
Error: permission denied: cosign.key

# Solution:
chmod 600 cosign.key
# Only owner can read/write private key
```

---

## Manual Step-by-Step (If Script Fails)

### 1. Authenticate

```bash
# Login to Quay
podman login quay.io -u flyers22
# Enter password when prompted

# Verify
podman login quay.io --get-login
# Should show: flyers22
```

### 2. Build Image

```bash
# Build
podman build -t quay.io/flyers22/secure-demo-app:v1.0.0 .

# Verify build
podman images | grep secure-demo-app
```

### 3. Push and Capture Digest

```bash
# Create digest file
DIGEST_FILE=$(mktemp)

# Push with digest capture
podman push quay.io/flyers22/secure-demo-app:v1.0.0 --digestfile "${DIGEST_FILE}"

# Read digest
DIGEST=$(cat "${DIGEST_FILE}")
echo "Image digest: ${DIGEST}"

# Full reference with digest
IMAGE_WITH_DIGEST="quay.io/flyers22/secure-demo-app@${DIGEST}"
echo "${IMAGE_WITH_DIGEST}" > image-digest.txt
```

### 4. Generate SBOM

```bash
# Using digest reference
syft "${IMAGE_WITH_DIGEST}" -o spdx-json > sbom.spdx.json
syft "${IMAGE_WITH_DIGEST}" -o cyclonedx-json > sbom.cyclonedx.json
syft "${IMAGE_WITH_DIGEST}" -o table
```

### 5. Generate Cosign Keys (if needed)

```bash
# Generate keys
COSIGN_PASSWORD="" cosign generate-key-pair

# This creates:
# - cosign.key (private - keep secure!)
# - cosign.pub (public - share this)
```

### 6. Sign Image with Digest

```bash
# Sign using digest
COSIGN_PASSWORD="" cosign sign --key cosign.key --yes "${IMAGE_WITH_DIGEST}"

# Should see:
# tlog entry created with index: ...
# Pushing signature to: quay.io/flyers22/secure-demo-app
```

### 7. Attach SBOM

```bash
# Attach SBOM
cosign attach sbom --sbom sbom.spdx.json "${IMAGE_WITH_DIGEST}"
```

### 8. Verify

```bash
# Verify signature
cosign verify --key cosign.pub "${IMAGE_WITH_DIGEST}"

# Download SBOM
cosign download sbom "${IMAGE_WITH_DIGEST}" > sbom-downloaded.json

# View signature tree
cosign tree "${IMAGE_WITH_DIGEST}"
```

---

## Verification Checklist

After running the script or manual steps, verify:

```bash
# ✓ Check 1: Image exists in Quay
curl -s https://quay.io/api/v1/repository/flyers22/secure-demo-app | jq .

# ✓ Check 2: Can pull image
podman pull quay.io/flyers22/secure-demo-app:v1.0.0

# ✓ Check 3: Signature exists
cosign tree quay.io/flyers22/secure-demo-app:v1.0.0

# ✓ Check 4: Signature verifies
cosign verify --key cosign.pub quay.io/flyers22/secure-demo-app@${DIGEST}

# ✓ Check 5: SBOM attached
cosign download sbom quay.io/flyers22/secure-demo-app@${DIGEST}

# ✓ Check 6: Can deploy
oc create deployment test --image=quay.io/flyers22/secure-demo-app@${DIGEST}
```

---

## Best Practices

### 1. Always Use Digests in Production

```yaml
# ❌ Bad - uses mutable tag
image: quay.io/flyers22/secure-demo-app:v1.0.0

# ✅ Good - uses immutable digest
image: quay.io/flyers22/secure-demo-app@sha256:abc123...

# ✅ Better - digest with tag for readability
image: quay.io/flyers22/secure-demo-app:v1.0.0@sha256:abc123...
```

### 2. Store Keys Securely

```bash
# ❌ Bad
git add cosign.key
git commit -m "added keys"

# ✅ Good - Store in vault
# HashiCorp Vault
vault kv put secret/cosign-keys private-key=@cosign.key

# ✅ Good - Kubernetes sealed secret
kubeseal --format yaml < cosign-secret.yaml > cosign-sealed.yaml

# ✅ Good - OpenShift secret
oc create secret generic cosign-keys \
  --from-file=cosign.key=cosign.key \
  --from-file=cosign.pub=cosign.pub \
  -n secure-supply-chain
```

### 3. Automate Signing in CI/CD

```yaml
# Tekton Pipeline example
- name: sign-image
  taskRef:
    name: cosign-sign
  params:
  - name: IMAGE
    value: $(tasks.build.results.IMAGE_DIGEST)
  workspaces:
  - name: cosign-keys
    workspace: signing-keys
```

### 4. Regular Key Rotation

```bash
# Every 90 days:
# 1. Generate new keys
cosign generate-key-pair -n new

# 2. Re-sign critical images
for img in $(cat critical-images.txt); do
  cosign sign --key new-cosign.key "${img}"
done

# 3. Update secrets
oc create secret generic cosign-keys \
  --from-file=cosign.key=new-cosign.key \
  --from-file=cosign.pub=new-cosign.pub \
  --dry-run=client -o yaml | oc apply -f -

# 4. Archive old keys
mv cosign.key cosign.key.$(date +%Y%m%d)
```

### 5. Audit Trail

```bash
# Track all signed images
cosign verify --key cosign.pub quay.io/flyers22/secure-demo-app@${DIGEST} | \
  jq -r '{image: .critical.image."docker-manifest-digest", signed_at: .optional.timestamp}' \
  >> signing-audit.log
```

---

## Quick Reference Commands

```bash
# Login
podman login quay.io

# Check auth
podman login quay.io --get-login

# Logout
podman logout quay.io

# Build
podman build -t quay.io/flyers22/app:tag .

# Push with digest
podman push quay.io/flyers22/app:tag --digestfile digest.txt

# Sign with digest
cosign sign --key cosign.key quay.io/flyers22/app@$(cat digest.txt)

# Verify
cosign verify --key cosign.pub quay.io/flyers22/app@$(cat digest.txt)

# Generate SBOM
syft quay.io/flyers22/app@$(cat digest.txt) -o spdx-json > sbom.json

# Attach SBOM
cosign attach sbom --sbom sbom.json quay.io/flyers22/app@$(cat digest.txt)

# Download SBOM
cosign download sbom quay.io/flyers22/app@$(cat digest.txt)

# View tree
cosign tree quay.io/flyers22/app:tag
```

---

## Getting Help

### Quay.io Support
- Documentation: https://docs.quay.io
- Status: https://status.quay.io
- Support: https://access.redhat.com/products/red-hat-quay

### Cosign Support
- Documentation: https://docs.sigstore.dev/cosign
- GitHub: https://github.com/sigstore/cosign
- Slack: https://sigstore.slack.com

### Community
- OpenShift Commons: https://commons.openshift.org
- CNCF Slack: https://cloud-native.slack.com
- Stack Overflow: Tag with `quay`, `cosign`, `sbom`

---

## Summary

To fix your immediate error:

```bash
# 1. Navigate to demo directory
cd rosa-supply-chain-demo

# 2. Ensure you're authenticated (if not already)
podman login quay.io
# Follow prompts to login to quay.io

# 3. Run the improved build script
chmod +x scripts/improved_build_script.sh
./scripts/improved_build_script.sh
# This will use digests automatically and find the app directory

# 4. Deploy (after script completes successfully)
# cd app && oc apply -f deployment-secure.yaml
```

The improved script handles all authentication checks and uses digest-based signing automatically, eliminating both errors you encountered!