SHELL := /usr/bin/env bash
ENV_FILE ?= .env

.PHONY: deploy undeploy

deploy:
	./scripts/deploy.sh $(ENV_FILE)

undeploy:
	./scripts/undeploy.sh $(ENV_FILE)
