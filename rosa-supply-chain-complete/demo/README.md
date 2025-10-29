# Demo Application

A sample Flask application demonstrating secure supply chain practices.

## Building the Image

```bash
cd demo/app
podman build -t secure-demo:1.0.0 .
```

## Pushing to Quay

```bash
QUAY_HOST=$(oc get route secure-registry-quay -n quay-enterprise -o jsonpath='{.spec.host}')
podman tag secure-demo:1.0.0 ${QUAY_HOST}/myorg/secure-demo:1.0.0
podman push ${QUAY_HOST}/myorg/secure-demo:1.0.0
```

## Signing the Image

```bash
cosign sign --key cosign.key ${QUAY_HOST}/myorg/secure-demo:1.0.0
```

## Generating SBOM

```bash
syft ${QUAY_HOST}/myorg/secure-demo:1.0.0 -o spdx-json > sbom.json
```

## Running Locally

```bash
python app.py
# Access at http://localhost:8080
```

## Endpoints

- `GET /` - Application info
- `GET /health` - Health check
- `GET /security` - Security compliance info
