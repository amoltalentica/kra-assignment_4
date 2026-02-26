#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Cleaning up Secure API Platform deployment...${NC}"
echo ""

# Delete Helm releases
echo -e "${YELLOW}Removing Helm releases...${NC}"
helm uninstall user-service -n api-platform 2>/dev/null || echo "user-service not found"
helm uninstall kong-gateway -n api-platform 2>/dev/null || echo "kong-gateway not found"
echo -e "${GREEN}✓ Helm releases removed${NC}"
echo ""

# Delete Kubernetes resources
echo -e "${YELLOW}Removing Kubernetes resources...${NC}"
kubectl delete -f k8s/crowdsec.yaml -n api-platform 2>/dev/null || echo "CrowdSec resources not found"
kubectl delete -f k8s/deployment.yaml 2>/dev/null || echo "Base deployments not found"
echo -e "${GREEN}✓ Kubernetes resources removed${NC}"
echo ""

# Delete namespace
echo -e "${YELLOW}Removing namespace...${NC}"
read -p "Do you want to delete the api-platform namespace? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl delete namespace api-platform
    echo -e "${GREEN}✓ Namespace deleted${NC}"
else
    echo -e "${YELLOW}Namespace retained${NC}"
fi

echo ""
echo -e "${GREEN}Cleanup complete!${NC}"
