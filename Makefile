COLLECTOR ?= alloy
K8S_VALUES ?= helm-charts/k8s-monitoring-values.local.yaml
K8S_NS ?= test-pov
K8S_RELEASE ?= grafana-cloud
K8S_CLUSTER ?= pov-sim-kube
K8S_CHART_VERSION ?= 4.5.5

up:
	docker compose up --build

backends:
	OTLP_GATEWAY=$(COLLECTOR) docker compose --profile backends --profile $(COLLECTOR) up --build

backends-alloy:
	$(MAKE) backends COLLECTOR=alloy

backends-otelcol:
	$(MAKE) backends COLLECTOR=otelcol

down:
	docker compose --profile backends --profile ui --profile alloy --profile otelcol down --remove-orphans

ui:
	docker compose --profile ui up --build


# ---- Kubernetes (minikube): `make k8s-up` brings the whole app up, `make k8s-down` tears it down ----
# Needs a populated .env (see .env_EXAMPLE). Set GC_FLEET_* there to also install Kubernetes Monitoring.

k8s-up:
	$(MAKE) k8s-start
	$(MAKE) k8s-monitoring
	$(MAKE) k8s-apps
	$(MAKE) k8s-wait
	$(MAKE) k8s-forward
	@echo ""
	@echo "Frontend:  http://localhost:3000"
	@echo "Airlines:  http://localhost:8080/airlines"
	@echo "Flights:   http://localhost:5001/health"
	@echo "Stop with: make k8s-down"

k8s-start:
	minikube start --driver=docker --cpus=4 --memory=6g

# Optional: Kubernetes Monitoring chart. Fleet URL/user/token come from .env (never written to a file).
k8s-monitoring:
	@set -a; . ./.env; set +a; \
	if [ -z "$$GC_FLEET_TOKEN" ]; then echo "GC_FLEET_TOKEN not set in .env: skipping the Kubernetes Monitoring chart"; exit 0; fi; \
	helm repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true; \
	helm repo update >/dev/null; \
	helm upgrade --install $(K8S_RELEASE) grafana/k8s-monitoring --version $(K8S_CHART_VERSION) \
		--namespace $(K8S_NS) --create-namespace \
		--set "cluster.name=$(K8S_CLUSTER)" \
		--set "collectorCommon.alloy.remoteConfig.enabled=true" \
		--set-string "collectorCommon.alloy.remoteConfig.url=$$GC_FLEET_URL" \
		--set-string "collectorCommon.alloy.remoteConfig.auth.username=$$GC_FLEET_USERNAME" \
		--set-string "collectorCommon.alloy.remoteConfig.auth.password=$$GC_FLEET_TOKEN" \
		-f $(K8S_VALUES)

# Build app images straight into minikube (containerd runtime, so docker-env doesn't apply; no registry needed).
# Skips images that already exist; force a rebuild with `make k8s-build REBUILD=1`.
k8s-build:
	@for img in airlines flights frontend; do \
		if [ -z "$(REBUILD)" ] && minikube image ls 2>/dev/null | grep -q "/$$img:local"; then \
			echo "$$img:local already in minikube (REBUILD=1 to force)"; \
		else \
			minikube image build -t $$img:local $$img || exit 1; \
		fi; \
	done

# Pyroscope creds only (not the OTLP creds); .env values are quoted so source it rather than --from-env-file
k8s-secret:
	@set -a; . ./.env; set +a; kubectl create secret generic pyroscope \
		--from-literal=PYROSCOPE_SERVER_ADDRESS="$$PYROSCOPE_SERVER_ADDRESS" \
		--from-literal=PYROSCOPE_BASIC_AUTH_USER="$$PYROSCOPE_BASIC_AUTH_USER" \
		--from-literal=PYROSCOPE_BASIC_AUTH_PASSWORD="$$PYROSCOPE_BASIC_AUTH_PASSWORD" \
		--dry-run=client -o yaml | kubectl apply -f -

# Collector config + OTLP creds for the in-cluster OTel Collector (creds sourced from .env, never written to a file)
k8s-collector-config:
	@kubectl create configmap otel-collector-config --from-file=config.yaml=otel-collector/config.k8s.yaml \
		--dry-run=client -o yaml | kubectl apply -f -
	@set -a; . ./.env; set +a; kubectl create secret generic otlp-credentials \
		--from-literal=CLOUD_OTLP_ENDPOINT="$$CLOUD_OTLP_ENDPOINT" \
		--from-literal=CLOUD_OTLP_USERNAME="$$CLOUD_OTLP_USERNAME" \
		--from-literal=CLOUD_OTLP_PASSWORD="$$CLOUD_OTLP_PASSWORD" \
		--dry-run=client -o yaml | kubectl apply -f -

# Browser-side settings for the frontend (Faro URL + API URLs); sourced from .env, never written to a file
k8s-frontend-secret:
	@set -a; . ./.env; set +a; kubectl create secret generic frontend-config \
		--from-literal=REACT_APP_AIRLINES_API_URL="$$REACT_APP_AIRLINES_API_URL" \
		--from-literal=REACT_APP_FLIGHTS_API_URL="$$REACT_APP_FLIGHTS_API_URL" \
		--from-literal=REACT_APP_FARO_URL="$$REACT_APP_FARO_URL" \
		--dry-run=client -o yaml | kubectl apply -f -

k8s-apps: k8s-build k8s-secret k8s-collector-config k8s-frontend-secret
	kubectl apply -f k8s/

k8s-wait:
	kubectl rollout status deploy/otel-collector deploy/airlines deploy/flights deploy/frontend --timeout=300s

# Background port-forwards so the browser can reach the pods; PIDs kept in .k8s-forward.pids
k8s-forward: k8s-stop-forward
	@for p in airlines:8080 flights:5001 frontend:3000; do \
		svc=$${p%%:*}; port=$${p##*:}; \
		nohup kubectl port-forward svc/$$svc $$port:$$port >/dev/null 2>&1 & echo $$! >> .k8s-forward.pids; \
	done
	@sleep 2

k8s-stop-forward:
	@if [ -f .k8s-forward.pids ]; then xargs kill < .k8s-forward.pids 2>/dev/null || true; fi; rm -f .k8s-forward.pids

k8s-status:
	@minikube status 2>&1 | head -4; kubectl get pods -A 2>/dev/null | grep -v kube-system

k8s-apps-down:
	-kubectl delete -f k8s/

# Full teardown: apps, credentials, monitoring chart, sample chart, then stop the cluster
k8s-down: k8s-stop-forward
	-kubectl delete -f k8s/
	-kubectl delete secret pyroscope otlp-credentials frontend-config
	-kubectl delete configmap otel-collector-config
	-helm uninstall $(K8S_RELEASE) -n $(K8S_NS)
	-helm uninstall sample-chart
	minikube stop

.PHONY: up down backends backends-alloy backends-otelcol ui k8s-up k8s-start k8s-monitoring k8s-build k8s-secret k8s-collector-config k8s-frontend-secret k8s-apps k8s-wait k8s-forward k8s-stop-forward k8s-status k8s-apps-down k8s-down
