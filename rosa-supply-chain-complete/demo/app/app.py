from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({
        "status": "healthy",
        "version": os.getenv("APP_VERSION", "1.0.0"),
        "signed": os.getenv("IMAGE_SIGNED", "true"),
        "sbom_available": True,
        "security_verified": True
    })

@app.route('/')
def home():
    return jsonify({
        "message": "Secure Supply Chain Demo - ROSA",
        "features": {
            "image_signing": "Cosign",
            "sbom": "Syft (SPDX/CycloneDX)",
            "vulnerability_scanning": "Trivy + Clair",
            "policy_enforcement": "Red Hat ACS",
            "sbom_analysis": "Trusted Profile Analyzer",
            "ci_cd": "Tekton Pipelines",
            "zero_trust": "Network Policies"
        },
        "integrations": [
            "Red Hat Quay",
            "Red Hat ACS",
            "Trusted Profile Analyzer",
            "OpenShift Pipelines",
            "MLflow (AI/ML)"
        ]
    })

@app.route('/security')
def security_info():
    return jsonify({
        "image_signature": {
            "signed": True,
            "algorithm": "cosign",
            "verified": True
        },
        "sbom": {
            "format": "SPDX 2.3",
            "attached": True,
            "signed": True
        },
        "vulnerabilities": {
            "scanned": True,
            "critical": 0,
            "high": 0,
            "policy_compliant": True
        },
        "compliance": {
            "standards": ["CIS", "PCI-DSS", "NIST SP 800-53"],
            "status": "COMPLIANT"
        }
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
