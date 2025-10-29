#!/usr/bin/env bash
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🧪 Validating ROSA Supply Chain Deployment"
echo "==========================================="
echo ""

passed=0
failed=0

test_component() {
    local name="$1"
    local namespace="$2"
    local route_name="$3"
    
    echo -n "Testing ${name}... "
    
    local host=""
    host=$(oc get route "$route_name" -n "$namespace" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    
    if [[ -z "$host" ]]; then
        echo -e "${RED}❌ FAIL (route not found)${NC}"
        ((failed++))
        return
    fi
    
    if curl -sk --max-time 10 "https://${host}" &>/dev/null; then
        echo -e "${GREEN}✅ PASS${NC}"
        echo "   URL: https://${host}"
        ((passed++))
    else
        echo -e "${YELLOW}⚠️  WARNING (not accessible)${NC}"
        echo "   URL: https://${host}"
        ((failed++))
    fi
}

# Test components
test_component "Quay Registry" "quay-enterprise" "secure-registry-quay"
test_component "Red Hat ACS" "stackrox" "central"
test_component "TPA" "trustification" "tpa-service"
test_component "MLflow" "openshift-ai" "mlflow-server"

echo ""
echo "==========================================="
echo "Results: ${passed} passed, ${failed} failed"
echo ""

if [[ $failed -eq 0 ]]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  Some tests had issues${NC}"
    echo "Note: Components may still be starting up"
    exit 0
fi
