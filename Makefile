.ONESHELL:
.SHELL := /usr/bin/bash
RANDOM := $(shell bash -c 'echo $$RANDOM')
BACKEND?=../../smart-backend
ENV?=dev

# cnf ?= .env
# include $(cnf)
# export $(shell sed 's/=.*//' $(cnf))

# Get the latest tag
TAG=$(shell git describe --tags --abbrev=0)
GIT_COMMIT=$(shell git log -1 --format=%h)
DOCS_VERSION='0.16.0'

CASE?=case

ifneq ($(shell test -e $(INCLUDE_MAKEFILE) && echo -n yes),yes)
	ifdef REMOTE_MAKEFILE
		REMOTE_MAKEFILE_RESULT := $(shell curl ${REMOTE_MAKEFILE} -o ${INCLUDE_MAKEFILE})
	else
		ERROR := $(error REMOTE_MAKEFILE not provided, look for your .env file)
	endif
endif

ifdef INCLUDE_MAKEFILE
	include ${INCLUDE_MAKEFILE}	
endif

.PHONY: help

help: ## This help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

install:
	@echo Install Terraform docs
	@curl -sLo /tmp/terraform-docs.tar.gz https://github.com/terraform-docs/terraform-docs/releases/download/v${DOCS_VERSION}/terraform-docs-v${DOCS_VERSION}-$$(uname)-cd .tar.gz 
	@tar -xzf /tmp/terraform-docs.tar.gz -C /tmp/
	@chmod +x /tmp/terraform-docs
	@sudo mv /tmp/terraform-docs /usr/local/bin/terraform-docs
	@echo Installed terraform docs
	@curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash

	
setup: 
	@cat>./.git/hooks/pre-commit<<EOF
	#!/bin/bash
	cd "$$PWD"
	make docs
	make lint
	git add README.md
	EOF
	@chmod +x .git/hooks/pre-commit

lint:
	@terraform fmt -check -diff -recursive
	@tflint --disable-rule=terraform_module_pinned_source

docs:
	@terraform-docs . > README.md
	@printf "\n\033[35;1mUpdating the following READMEs with terraform-docs\033[0m\n\n"
#	@find . -name README.md -exec rm {} +

backend:
	@echo "# The name of your Terraform Cloud organization." > ${ENV}.tfvars
	@echo 'organization = "hubitsecurity"' >> ${ENV}.tfvars
	@echo 'workspaces {' >> ${ENV}.tfvars
	@echo '    name = "base-infra-${ENV}"' >> ${ENV}.tfvars
	@echo '}'>> ${ENV}.tfvars
	

prd: 
	@$(MAKE) backend ENV=prd
	@terraform init -backend-config=prd.tfvars