COLLECTOR ?= alloy
K8S_VALUES ?= helm-charts/k8s-monitoring-values.local.yaml

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

k8s-up:
	minikube start --driver=docker --cpus=4 --memory=6g
	helm upgrade --install sample-chart helm-charts/sample-chart
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo update
	helm upgrade --install grafana-k8s-monitoring grafana/k8s-monitoring \
		--namespace monitoring --create-namespace \
		-f $(K8S_VALUES)

# Build app images straight into minikube (containerd runtime, so docker-env doesn't apply; no registry needed)
k8s-build:
	minikube image build -t airlines:local airlines
	minikube image build -t flights:local flights
	minikube image build -t frontend:local frontend

# Pyroscope creds only (not the OTLP creds); .env values are quoted so source it rather than --from-env-file
k8s-secret:
	set -a && . ./.env && set +a && kubectl create secret generic pyroscope \
		--from-literal=PYROSCOPE_SERVER_ADDRESS="$$PYROSCOPE_SERVER_ADDRESS" \
		--from-literal=PYROSCOPE_BASIC_AUTH_USER="$$PYROSCOPE_BASIC_AUTH_USER" \
		--from-literal=PYROSCOPE_BASIC_AUTH_PASSWORD="$$PYROSCOPE_BASIC_AUTH_PASSWORD" \
		--dry-run=client -o yaml | kubectl apply -f -

# Collector config + OTLP creds for the in-cluster OTel Collector (creds sourced from .env, never written to a file)
k8s-collector-config:
	kubectl create configmap otel-collector-config --from-file=config.yaml=otel-collector/config.k8s.yaml \
		--dry-run=client -o yaml | kubectl apply -f -
	set -a && . ./.env && set +a && kubectl create secret generic otlp-credentials \
		--from-literal=CLOUD_OTLP_ENDPOINT="$$CLOUD_OTLP_ENDPOINT" \
		--from-literal=CLOUD_OTLP_USERNAME="$$CLOUD_OTLP_USERNAME" \
		--from-literal=CLOUD_OTLP_PASSWORD="$$CLOUD_OTLP_PASSWORD" \
		--dry-run=client -o yaml | kubectl apply -f -

# Browser-side settings for the frontend (Faro URL + API URLs); sourced from .env, never written to a file
k8s-frontend-secret:
	set -a && . ./.env && set +a && kubectl create secret generic frontend-config \
		--from-literal=REACT_APP_AIRLINES_API_URL="$$REACT_APP_AIRLINES_API_URL" \
		--from-literal=REACT_APP_FLIGHTS_API_URL="$$REACT_APP_FLIGHTS_API_URL" \
		--from-literal=REACT_APP_FARO_URL="$$REACT_APP_FARO_URL" \
		--dry-run=client -o yaml | kubectl apply -f -

k8s-apps: k8s-build k8s-secret k8s-collector-config k8s-frontend-secret
	kubectl apply -f k8s/

k8s-apps-down:
	-kubectl delete -f k8s/

k8s-down:
	-kubectl delete -f k8s/
	-helm uninstall grafana-k8s-monitoring -n monitoring
	-helm uninstall sample-chart
	minikube stop

.PHONY: up down backends backends-alloy backends-otelcol ui k8s-up k8s-down k8s-build k8s-secret k8s-apps k8s-apps-down k8s-collector-config k8s-frontend-secret
