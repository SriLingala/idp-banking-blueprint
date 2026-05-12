SHELL := /usr/bin/env bash
ENV   ?= dev

ENVDIR := environments/$(ENV)

.PHONY: help init fmt validate plan apply destroy lint clean argocd-root helm-lint

help:
	@echo "Targets:"
	@echo "  make init     ENV=dev   - terraform init in environments/<env>"
	@echo "  make fmt                - terraform fmt -recursive on the whole repo"
	@echo "  make validate ENV=dev   - terraform validate"
	@echo "  make plan     ENV=dev   - terraform plan"
	@echo "  make apply    ENV=dev   - terraform apply (auto-approve OFF)"
	@echo "  make destroy  ENV=dev   - terraform destroy"
	@echo "  make lint               - tflint on modules and environments"
	@echo "  make helm-lint          - helm lint + template on helm/ charts"
	@echo "  make argocd-root        - one-time bootstrap of the Argo CD root app"
	@echo "  make clean              - remove .terraform/ and lockfiles"

init:
	cd $(ENVDIR) && terraform init

fmt:
	terraform fmt -recursive

validate:
	cd $(ENVDIR) && terraform init -backend=false && terraform validate

plan:
	cd $(ENVDIR) && terraform plan -out=tfplan

apply:
	cd $(ENVDIR) && terraform apply tfplan

destroy:
	cd $(ENVDIR) && terraform destroy

lint:
	@for d in modules/* environments/*; do \
		echo "==> $$d"; \
		(cd $$d && tflint --init && tflint --format compact) || exit 1; \
	done

clean:
	find . -type d -name ".terraform" -prune -exec rm -rf {} +
	find . -type f -name ".terraform.lock.hcl" -delete
	find . -type f -name "tfplan" -delete

helm-lint:
	@for c in helm/*/; do \
		echo "==> $$c"; \
		helm lint $$c || exit 1; \
		helm template ci-test $$c >/dev/null || exit 1; \
	done

# One-time Argo CD bootstrap. Run with cluster-admin creds; after this,
# Argo CD owns the rest via the app-of-apps in argocd/apps/.
argocd-root:
	kubectl apply -f argocd/projects/
	kubectl apply -f argocd/apps/root.yaml
