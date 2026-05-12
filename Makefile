SHELL := /usr/bin/env bash
ENV   ?= dev

ENVDIR := environments/$(ENV)

.PHONY: help init fmt validate plan apply destroy lint clean

help:
	@echo "Targets:"
	@echo "  make init     ENV=dev   - terraform init in environments/<env>"
	@echo "  make fmt                - terraform fmt -recursive on the whole repo"
	@echo "  make validate ENV=dev   - terraform validate"
	@echo "  make plan     ENV=dev   - terraform plan"
	@echo "  make apply    ENV=dev   - terraform apply (auto-approve OFF)"
	@echo "  make destroy  ENV=dev   - terraform destroy"
	@echo "  make lint               - tflint on modules and environments"
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
