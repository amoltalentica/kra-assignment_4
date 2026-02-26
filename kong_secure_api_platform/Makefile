.PHONY: help build deploy test clean status logs

# Variables
NAMESPACE := api-platform
MINIKUBE_IP := $(shell minikube ip 2>/dev/null || echo "localhost")
KONG_PROXY := http://$(MINIKUBE_IP):30080
KONG_ADMIN := http://$(MINIKUBE_IP):30081

# Colors
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

help: ## Show this help message
	@echo "$(GREEN)Secure API Platform - Makefile Commands$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""

build: ## Build the microservice Docker image
	@echo "$(GREEN)Building microservice image...$(NC)"
	cd microservice && docker build -t user-service:latest .
	@if command -v minikube &> /dev/null; then \
		echo "$(GREEN)Loading image into Minikube...$(NC)"; \
		minikube image load user-service:latest; \
	fi
	@echo "$(GREEN)✓ Build complete$(NC)"

deploy: ## Deploy all components to Kubernetes
	@echo "$(GREEN)Deploying all components...$(NC)"
	chmod +x scripts/deploy-all.sh
	./scripts/deploy-all.sh

deploy-user-service: ## Deploy only the user service
	@echo "$(GREEN)Deploying user service...$(NC)"
	helm upgrade --install user-service helm/user-service \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--wait

deploy-kong: ## Deploy only Kong gateway
	@echo "$(GREEN)Deploying Kong gateway...$(NC)"
	cd helm/kong && helm dependency update && cd ../..
	helm upgrade --install kong-gateway helm/kong \
		--namespace $(NAMESPACE) \
		--create-namespace \
		--wait

deploy-envoy: ## Deploy Envoy proxy
	@echo "$(GREEN)Deploying Envoy proxy...$(NC)"
	kubectl apply -f k8s/envoy-simple.yaml
	@echo "$(GREEN)✓ Envoy deployed$(NC)"

test: ## Run API tests
	@echo "$(GREEN)Running API tests...$(NC)"
	chmod +x scripts/test-apis.sh
	./scripts/test-apis.sh

test-health: ## Test health endpoint
	@echo "Testing health endpoint..."
	@curl -s $(KONG_PROXY)/health | jq .

test-login: ## Test login endpoint
	@echo "Testing login endpoint..."
	@curl -s -X POST $(KONG_PROXY)/login \
		-H "Content-Type: application/json" \
		-d '{"username":"testuser","password":"testpassword"}' | jq .

test-rate-limit: ## Test rate limiting
	@echo "$(YELLOW)Testing rate limiting (15 requests)...$(NC)"
	@for i in $$(seq 1 15); do \
		echo -n "Request $$i: "; \
		curl -s -o /dev/null -w "%{http_code}\n" $(KONG_PROXY)/health; \
		sleep 0.5; \
	done

status: ## Show deployment status
	@echo "$(GREEN)Deployment Status:$(NC)"
	@echo ""
	@echo "$(YELLOW)Pods:$(NC)"
	@kubectl get pods -n $(NAMESPACE)
	@echo ""
	@echo "$(YELLOW)Services:$(NC)"
	@kubectl get svc -n $(NAMESPACE)
	@echo ""
	@echo "$(YELLOW)Access URLs:$(NC)"
	@echo "Kong Proxy:     $(KONG_PROXY)"
	@echo "Kong Admin:     $(KONG_ADMIN)"

logs: ## Show logs for all components
	@echo "$(YELLOW)Which component logs? (user-service/kong/envoy/all)$(NC)"
	@read component; \
	if [ "$$component" = "user-service" ]; then \
		kubectl logs -n $(NAMESPACE) -l app=user-service -f; \
	elif [ "$$component" = "kong" ]; then \
		kubectl logs -n $(NAMESPACE) -l app=kong -f; \
	elif [ "$$component" = "envoy" ]; then \
		kubectl logs -n $(NAMESPACE) -l app=envoy-proxy -f; \
	else \
		kubectl logs -n $(NAMESPACE) -l app=user-service --tail=10; \
		kubectl logs -n $(NAMESPACE) -l app=kong --tail=10; \
		kubectl logs -n $(NAMESPACE) -l app=envoy-proxy --tail=10; \
	fi

logs-user-service: ## Show user service logs
	@kubectl logs -n $(NAMESPACE) -l app=user-service -f

logs-kong: ## Show Kong logs
	@kubectl logs -n $(NAMESPACE) -l app=kong -f

logs-envoy: ## Show Envoy proxy logs
	@kubectl logs -n $(NAMESPACE) -l app=envoy-proxy -f

shell-user-service: ## Get shell in user service pod
	@kubectl exec -it -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app=user-service -o jsonpath='{.items[0].metadata.name}') -- /bin/sh

shell-kong: ## Get shell in Kong pod
	@kubectl exec -it -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app=kong -o jsonpath='{.items[0].metadata.name}') -- /bin/sh

shell-envoy: ## Get shell in Envoy pod
	@kubectl exec -it -n $(NAMESPACE) $$(kubectl get pod -n $(NAMESPACE) -l app=envoy-proxy -o jsonpath='{.items[0].metadata.name}') -- /bin/sh

envoy-stats: ## Show Envoy stats
	@curl -s http://$(MINIKUBE_IP):30091/stats | head -50

envoy-clusters: ## Show Envoy clusters
	@curl -s http://$(MINIKUBE_IP):30091/clusters

envoy-circuit-breaker: ## Show Envoy circuit breaker stats
	@curl -s http://$(MINIKUBE_IP):30091/stats | grep circuit_breakers

kong-status: ## Show Kong status via Admin API
	@curl -s $(KONG_ADMIN)/status | jq .

kong-services: ## List Kong services
	@curl -s $(KONG_ADMIN)/services | jq .

kong-routes: ## List Kong routes
	@curl -s $(KONG_ADMIN)/routes | jq .

kong-plugins: ## List Kong plugins
	@curl -s $(KONG_ADMIN)/plugins | jq .

clean: ## Remove all deployments
	@echo "$(YELLOW)Cleaning up...$(NC)"
	chmod +x scripts/cleanup.sh
	./scripts/cleanup.sh
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

rebuild: clean build deploy ## Clean, build, and redeploy everything

restart-user-service: ## Restart user service
	@kubectl rollout restart deployment/user-service -n $(NAMESPACE)
	@kubectl rollout status deployment/user-service -n $(NAMESPACE)

restart-kong: ## Restart Kong
	@kubectl rollout restart deployment/kong-gateway-kong -n $(NAMESPACE)
	@kubectl rollout status deployment/kong-gateway-kong -n $(NAMESPACE)

port-forward: ## Setup port forwarding for local access
	@echo "$(GREEN)Setting up port forwarding...$(NC)"
	@echo "Kong Proxy: http://localhost:8000"
	@echo "Kong Admin: http://localhost:8001"
	@echo "Press Ctrl+C to stop"
	@kubectl port-forward -n $(NAMESPACE) svc/kong-gateway-kong-proxy 8000:80 & \
	kubectl port-forward -n $(NAMESPACE) svc/kong-gateway-kong-admin 8001:8001

describe: ## Describe all resources
	@echo "$(YELLOW)Deployments:$(NC)"
	@kubectl describe deployments -n $(NAMESPACE)
	@echo ""
	@echo "$(YELLOW)Services:$(NC)"
	@kubectl describe services -n $(NAMESPACE)

validate-helm: ## Validate Helm charts
	@echo "$(GREEN)Validating Helm charts...$(NC)"
	@helm lint helm/user-service
	@helm lint helm/kong

helm-template: ## Generate Kubernetes manifests from Helm charts
	@helm template user-service helm/user-service --namespace $(NAMESPACE) > /tmp/user-service-manifest.yaml
	@helm template kong-gateway helm/kong --namespace $(NAMESPACE) > /tmp/kong-manifest.yaml
	@echo "$(GREEN)Manifests generated in /tmp/$(NC)"

minikube-start: ## Start Minikube cluster
	@minikube start --cpus=4 --memory=8192 --driver=docker

minikube-stop: ## Stop Minikube cluster
	@minikube stop

minikube-delete: ## Delete Minikube cluster
	@minikube delete
