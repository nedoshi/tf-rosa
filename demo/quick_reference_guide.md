# Quick Reference Guide - ROSA Supply Chain Security

## 🚀 Quick Start (5 Minutes)

```bash
# 1. Login to ROSA cluster
oc login --server=https://api.rosa.example.com:6443 --token=YOUR_TOKEN

# 2. Run complete deployment script
chmod +x complete-deployment.sh
./complete-deployment.sh

# 3. Wait for deployment (20-30 minutes)
# Components will be deployed automatically

# 4. Run tests
cd rosa-supply-chain-complete
./scripts/test-e2e.sh
```

---

## 📦 Component Quick Access

### Red Hat Quay
```bash
# Get Quay URL
oc get route secure-registry-quay -n quay-enterprise -o jsonpath='{.spec.host}'

# Access Quay UI
https://$(oc get route secure-registry-quay -n quay-enterprise -o jsonpath='{.spec.host}')

# Check Quay health
curl -k https://$(oc get route secure-registry-quay -n quay-enterprise -o jsonpath='{.spec.host}')/health/instance
```

### Red Hat ACS (Advanced Cluster Security)
```bash
# Get ACS Central URL
oc get route central -n stackrox -o jsonpath='{.spec.host}'

# Get admin password
oc get secret central-htpasswd -n stackrox -o jsonpath='{.data.password}' | base64 -d

# Generate API token (after login to UI)
# Settings → Integrations → API Token → Generate Token
```

### Trusted Profile Analyzer
```bash
# Get TPA URL
oc get route tpa-service -n trustification -o jsonpath='{.spec.host}'

# Upload SBOM
curl -X POST https://$(oc get route tpa-service -n trustification -o jsonpath='{.spec.host}')/api/v1/sbom \
  -H "Content-Type: application/json" \
  -d @sbom.spdx.json
```

### MLflow Model Registry
```bash
# Get MLflow URL
oc get route mlflow-server -n openshift-ai -o jsonpath='{.spec.host}'

# Access MLflow UI
https://$(oc get route mlflow-server -n openshift-ai -o jsonpath='{.spec.host}')
```

---

## 🔐 Image Signing Workflow

### 1. Build Image
```bash
podman build -t quay.io/myorg/myapp:v1.0.0 .
```

### 2. Generate SBOM
```bash
# SPDX format
syft quay.io/myorg/myapp:v1.0.0 -o spdx-json > sbom.spdx.json

# CycloneDX format
syft quay.io/myorg/myapp:v1.0.0 -o cyclonedx-json > sbom.cyclonedx.json

# Human-readable
syft quay.io/myorg/myapp:v1.0.0 -o table
```

### 3. Push Image
```bash
podman push quay.io/myorg/myapp:v1.0.0
```

### 4. Sign Image
```bash
# Sign with Cosign
cosign sign --key cosign.key quay.io/myorg/myapp:v1.0.0

# Or keyless signing (requires OIDC)
cosign sign quay.io/myorg/myapp:v1.0.0
```

### 5. Attach SBOM
```bash
cosign attach sbom --sbom sbom.spdx.json quay.io/myorg/myapp:v1.0.0
```

### 6. Verify
```bash
# Verify signature
cosign verify --key cosign.pub quay.io/myorg/myapp:v1.0.0

# Download SBOM
cosign download sbom quay.io/myorg/myapp:v1.0.0 | jq .

# View signature details
cosign tree quay.io/myorg/myapp:v1.0.0
```

---

## 🔍 Vulnerability Scanning

### Scan with Trivy
```bash
# Scan image
trivy image quay.io/myorg/myapp:v1.0.0

# Scan and filter by severity
trivy image --severity HIGH,CRITICAL quay.io/myorg/myapp:v1.0.0

# Generate JSON report
trivy image --format json --output report.json quay.io/myorg/myapp:v1.0.0

# Fail on critical vulnerabilities
trivy image --exit-code 1 --severity CRITICAL quay.io/myorg/myapp:v1.0.0
```

### Scan with ACS
```bash
# Install roxctl CLI
# Download from ACS Central UI or:
curl -O https://mirror.openshift.com/pub/rhacs/assets/latest/bin/Linux/roxctl
chmod +x roxctl

# Configure roxctl
export ROX_CENTRAL_ADDRESS=$(oc get route central -n stackrox -o jsonpath='{.spec.host}'):443
export ROX_API_TOKEN="your-api-token"

# Scan image
roxctl image check --image quay.io/myorg/myapp:v1.0.0

# Check deployment
roxctl deployment check --file deployment.yaml
```

### Check with Quay/Clair
```bash
# Get scan results via API
curl -X GET \
  "https://quay.io/api/v1/repository/myorg/myapp/manifest/sha256:abc123/security" \
  -H "Authorization: Bearer $QUAY_TOKEN" | jq .
```

---

## 🔬 SBOM Analysis with TPA

### Upload SBOM
```bash
TPA_URL=$(oc get route tpa-service -n trustification -o jsonpath='{.spec.host}')

# Upload
SBOM_ID=$(curl -X POST "https://${TPA_URL}/api/v1/sbom" \
  -H "Content-Type: application/json" \
  -d @sbom.spdx.json | jq -r '.sbom_id')

echo "SBOM ID: ${SBOM_ID}"
```

### Analyze Vulnerabilities
```bash
# Get vulnerabilities
curl "https://${TPA_URL}/api/v1/sbom/${SBOM_ID}/vulnerabilities" | jq .

# Filter critical
curl "https://${TPA_URL}/api/v1/sbom/${SBOM_ID}/vulnerabilities" | \
  jq '[.vulnerabilities[] | select(.severity=="CRITICAL")]'
```

### Check License Compliance
```bash
# Get license info
curl "https://${TPA_URL}/api/v1/sbom/${SBOM_ID}/licenses" | jq .

# Find non-compliant licenses
curl "https://${TPA_URL}/api/v1/sbom/${SBOM_ID}/licenses" | \
  jq '[.licenses[] | select(.compliance_status!="COMPLIANT")]'
```

### Risk Assessment
```bash
# Get risk score
curl "https://${TPA_URL}/api/v1/sbom/${SBOM_ID}/risk-score" | jq .
```

---

## 🚦 Tekton Pipeline Operations

### List Pipelines
```bash
tkn pipeline list -n secure-supply-chain
```

### Run Pipeline
```bash
tkn pipeline start secure-supply-chain-pipeline \
  --param GIT_REPO=https://github.com/myorg/myapp \
  --param GIT_REVISION=main \
  --param IMAGE_NAME=myapp \
  --param IMAGE_TAG=v1.0.0 \
  --param QUAY_NAMESPACE=myorg \
  --param ACS_CENTRAL_ENDPOINT=central.stackrox.svc:443 \
  --param TPA_ENDPOINT=https://tpa-service-trustification.apps.rosa.example.com \
  --workspace name=shared-workspace,volumeClaimTemplateFile=workspace-pvc.yaml \
  --workspace name=cosign-keys,secret=cosign-keys \
  --workspace name=quay-credentials,secret=quay-robot-secret \
  --workspace name=acs-token,secret=acs-api-token \
  --showlog
```

### Monitor Pipeline Run
```bash
# List runs
tkn pipelinerun list -n secure-supply-chain

# Watch logs
tkn pipelinerun logs <pipelinerun-name> -f -n secure-supply-chain

# Describe run
tkn pipelinerun describe <pipelinerun-name> -n secure-supply-chain
```

### Cancel Pipeline Run
```bash
tkn pipelinerun cancel <pipelinerun-name> -n secure-supply-chain
```

---

## 🤖 AI/ML Model Security

### Register Model in MLflow
```python
import mlflow

mlflow.set_tracking_uri("https://mlflow-server-openshift-ai.apps.rosa.example.com")

with mlflow.start_run(run_name="my-model-v1") as run:
    # Log model
    mlflow.log_artifact("model/", artifact_path="model")
    
    # Log SBOM
    mlflow.log_artifact("model-sbom.json")
    
    # Log signature
    mlflow.log_artifact("model.sig")
    
    # Set security tags
    mlflow.set_tags({
        "security.signed": "true",
        "security.sbom": "true",
        "security.scanned": "true"
    })
    
    # Register model
    model_uri = f"runs:/{run.info.run_id}/model"
    mlflow.register_model(model_uri, "my-model")
```

### Sign Model
```bash
# Create model tarball
tar -czf model.tar.gz model/

# Sign
cosign sign-blob \
  --key cosign.key \
  --output-signature model.sig \
  --output-certificate model.crt \
  model.tar.gz

# Sign SBOM
cosign sign-blob \
  --key cosign.key \
  --output-signature model-sbom.sig \
  model-sbom.json
```

### Verify Model
```bash
# Verify model signature
cosign verify-blob \
  --key cosign.pub \
  --signature model.sig \
  model.tar.gz

# Verify SBOM signature
cosign verify-blob \
  --key cosign.pub \
  --signature model-sbom.sig \
  model-sbom.json
```

### Secure Inference
```bash
INFERENCE_URL=$(oc get route secure-ai-inference -n openshift-ai -o jsonpath='{.spec.host}')

# Validate model before inference
curl -X POST "https://${INFERENCE_URL}/validate" \
  -H "Content-Type: application/json" \
  -d '{
    "model_name": "my-model",
    "model_version": "1"
  }' | jq .

# Run inference (only works with verified models)
curl -X POST "https://${INFERENCE_URL}/predict" \
  -H "Content-Type: application/json" \
  -d '{
    "model_name": "my-model",
    "model_version": "1",
    "prompt": "Your inference input"
  }' | jq .
```

---

## 📊 Policy Management (ACS)

### List Policies
```bash
roxctl --endpoint=$ROX_CENTRAL_ADDRESS policy list
```

### Import Policy
```bash
# From JSON file
roxctl --endpoint=$ROX_CENTRAL_ADDRESS policy import --file policy.json

# Multiple policies
roxctl --endpoint=$ROX_CENTRAL_ADDRESS policy import --dir policies/
```

### Export Policy
```bash
roxctl --endpoint=$ROX_CENTRAL_ADDRESS policy export --name "Policy Name" > policy.json
```

### Check Policy Violations
```bash
# For specific deployment
roxctl deployment check --file deployment.yaml

# For specific image
roxctl image check --image quay.io/myorg/myapp:v1.0.0
```

---

## 🔧 Troubleshooting Commands

### Check All Components
```bash
# Quay
oc get pods -n quay-enterprise
oc get quayregistry -n quay-enterprise

# ACS
oc get pods -n stackrox
oc get central -n stackrox
oc get securedcluster -n stackrox

# TPA
oc get pods -n trustification
oc get route tpa-service -n trustification

# Tekton
oc get pods -n openshift-pipelines
tkn pipeline list -n secure-supply-chain

# MLflow
oc get pods -n openshift-ai
oc get route mlflow-server -n openshift-ai
```

### View Logs
```bash
# Quay
oc logs -n quay-enterprise deployment/quay-app -f

# ACS Central
oc logs -n stackrox deployment/central -f

# ACS Scanner
oc logs -n stackrox deployment/scanner -f

# TPA
oc logs -n trustification deployment/tpa-service -f

# Tekton Pipeline Run
tkn pipelinerun logs <run-name> -f -n secure-supply-chain
```

### Restart Components
```bash
# Quay
oc rollout restart deployment/quay-app -n quay-enterprise

# ACS Central
oc rollout restart deployment/central -n stackrox

# TPA
oc rollout restart deployment/tpa-service -n trustification

# MLflow
oc rollout restart deployment/mlflow-server -n openshift-ai
```

### Check Admission Controller (ACS)
```bash
# Check if admission controller is running
oc get validatingwebhookconfiguration stackrox

# Check admission controller logs
oc logs -n stackrox deployment/admission-control -f

# Temporarily disable admission controller
oc patch securedcluster rosa-production -n stackrox \
  --type merge \
  -p '{"spec":{"admissionControl":{"dynamic":{"enforceOnCreates":false}}}}'
```

---

## 📈 Monitoring and Metrics

### Check Image Signature Verification Rate
```bash
# Query Prometheus
oc exec -n openshift-monitoring prometheus-k8s-0 -- \
  promtool query instant \
  'sum(rate(image_signature_verified{verified="true"}[5m])) / sum(rate(image_deployments_total[5m])) * 100'
```

### View ACS Alerts
```bash
# Get active alerts
curl -k "https://${ROX_CENTRAL_ADDRESS}/v1/alerts" \
  -H "Authorization: Bearer ${ROX_API_TOKEN}" | jq '.alerts[] | {name: .policy.name, severity: .policy.severity}'
```

### Compliance Report
```bash
# Generate compliance report for PCI-DSS
roxctl --endpoint=$ROX_CENTRAL_ADDRESS \
  compliance export \
  --standard PCI-DSS \
  --output pci-dss-report.csv
```

---

## 🔄 CI/CD Integration Examples

### GitHub Actions
```yaml
name: Secure Build and Deploy
on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build image
        run: podman build -t quay.io/myorg/myapp:${{ github.sha }} .
      
      - name: Generate SBOM
        run: syft quay.io/myorg/myapp:${{ github.sha }} -o spdx-json > sbom.json
      
      - name: Push image
        run: podman push quay.io/myorg/myapp:${{ github.sha }}
      
      - name: Sign image
        run: cosign sign --key ${{ secrets.COSIGN_KEY }} quay.io/myorg/myapp:${{ github.sha }}
      
      - name: Attach SBOM
        run: cosign attach sbom --sbom sbom.json quay.io/myorg/myapp:${{ github.sha }}
      
      - name: Verify with ACS
        run: roxctl image check --image quay.io/myorg/myapp:${{ github.sha }}
```

### GitLab CI
```yaml
stages:
  - build
  - scan
  - sign
  - deploy

build:
  stage: build
  script:
    - podman build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - podman push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA

scan:
  stage: scan
  script:
    - syft $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA -o spdx-json > sbom.json
    - trivy image --exit-code 1 --severity CRITICAL $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA

sign:
  stage: sign
  script:
    - cosign sign --key $COSIGN_KEY $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
    - cosign attach sbom --sbom sbom.json $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
```

---

## 🎯 Common Use Cases

### Deploy Signed Image
```bash
# 1. Verify image is signed
cosign verify --key cosign.pub quay.io/myorg/myapp:v1.0.0

# 2. Create deployment
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: production
  annotations:
    image.policy.openshift.io/verify: "true"
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: quay.io/myorg/myapp:v1.0.0
        ports:
        - containerPort: 8080
EOF
```

### Block Unsigned Images
```bash
# ACS will automatically block unsigned images if policy is enabled
# Check if image passes policies:
roxctl image check --image quay.io/myorg/myapp:v1.0.0

# If it fails, check which policies:
roxctl image check --image quay.io/myorg/myapp:v1.0.0 --json | \
  jq '.alerts[] | {policy: .policy.name, violation: .violations[]}'
```

### Rotate Signing Keys
```bash
# 1. Generate new keys
cosign generate-key-pair -n new

# 2. Re-sign all images
for image in $(oc get deployment -A -o jsonpath='{.items[*].spec.template.spec.containers[*].image}' | tr ' ' '\n' | sort -u); do
  echo "Re-signing: $image"
  cosign sign --key new-cosign.key $image
done

# 3. Update secret
oc create secret generic cosign-keys \
  --from-file=cosign.key=new-cosign.key \
  --from-file=cosign.pub=new-cosign.pub \
  -n secure-supply-chain \
  --dry-run=client -o yaml | oc apply -f -

# 4. Archive old keys securely
mv cosign.key cosign.key.old.$(date +%Y%m%d)
mv cosign.pub cosign.pub.old.$(date +%Y%m%d)
```

---

## 📚 Additional Resources

### Documentation
- **Red Hat Quay**: https://docs.quay.io
- **Red Hat ACS**: https://docs.openshift.com/acs
- **Sigstore/Cosign**: https://docs.sigstore.dev/cosign
- **Syft**: https://github.com/anchore/syft
- **OpenShift Pipelines**: https://docs.openshift.com/pipelines
- **MLflow**: https://mlflow.org/docs

### Standards & Compliance
- **SLSA Framework**: https://slsa.dev
- **NIST SP 800-53**: https://csrc.nist.gov/publications/detail/sp/800-53/rev-5/final
- **CIS Benchmarks**: https://www.cisecurity.org/cis-benchmarks
- **SBOM Standards**: https://www.cisa.gov/sbom

### Community
- **Sigstore**: https://www.sigstore.dev
- **CNCF Supply Chain Security**: https://tag-security.cncf.io
- **OpenSSF**: https://openssf.org

---

## 🆘 Getting Help

### Check Status
```bash
# Run comprehensive health check
./scripts/test-e2e.sh

# Check specific component
oc get all -n <namespace>
```

### Common Issues

**Issue**: Cosign verification fails
```bash
# Solution: Check if image was actually signed
cosign tree quay.io/myorg/myapp:tag
# Re-sign if necessary
cosign sign --key cosign.key quay.io/myorg/myapp:tag
```

**Issue**: ACS blocks valid deployments
```bash
# Solution: Check which policy is failing
roxctl deployment check --file deployment.yaml
# Review policy or create exception
```

**Issue**: Pipeline fails
```bash
# Solution: Check pipeline run logs
tkn pipelinerun logs <run-name> -f
# Check task-specific issues
oc describe pipelinerun <run-name>
```

### Support Contacts
- Red Hat Support: https://access.redhat.com/support
- OpenShift Support: Submit case through Red Hat Portal
- Community Forums: https://discuss.openshift.com

---

**Last Updated**: October 2025  
**Version**: 1.0  
**Tested On**: ROSA 4.14+