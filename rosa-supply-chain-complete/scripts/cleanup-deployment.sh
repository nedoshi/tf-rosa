#!/usr/bin/env bash
# Cleanup script for ROSA Supply Chain deployment

set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${YELLOW}⚠️  WARNING: This will delete all deployed components!${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Cleanup cancelled"
    exit 0
fi

echo ""
echo "Cleaning up namespaces..."

for ns in quay-enterprise stackrox trustification openshift-ai secure-supply-chain; do
    if oc get namespace "$ns" &>/dev/null; then
        echo "Deleting namespace: $ns"
        oc delete namespace "$ns" --wait=false || true
    fi
done

echo ""
echo -e "${GREEN}✅ Cleanup initiated${NC}"
echo "Note: Namespace deletion may take several minutes"
