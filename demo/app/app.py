from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({
        "status": "healthy",
        "version": os.getenv("APP_VERSION", "1.0.0"),
        "signed": os.getenv("IMAGE_SIGNED", "true"),
        "sbom_available": True
    })

@app.route('/')
def home():
    return jsonify({
        "message": "Secure Supply Chain Demo - ROSA",
        "security_features": [
            "✅ Image Signing with Cosign",
            "✅ SBOM Generation with Syft",
            "✅ Policy Enforcement with ACS",
            "✅ Zero Trust Network Policies"
        ]
    })

@app.route('/security')
def security_info():
    return jsonify({
        "image_signed": True,
        "signature_verified": True,
        "sbom_format": "SPDX",
        "compliance": ["CIS", "PCI-DSS", "NIST"],
        "zero_trust": True
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
