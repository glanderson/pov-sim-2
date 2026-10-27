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

k8s-down:
	-helm uninstall grafana-k8s-monitoring -n monitoring
	-helm uninstall sample-chart
	minikube stop

.PHONY: up down backends backends-alloy backends-otelcol ui k8s-up k8s-down
