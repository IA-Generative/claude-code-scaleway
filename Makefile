.PHONY: help install proxy up down logs check models tools env
.DEFAULT_GOAL := help

-include .env
export

PROXY_PORT ?= 4000
PROXY_KEY  ?= sk-local-dev-1234
MODEL      ?= glm-5.2

help:  ## Affiche cette aide
	@grep -hE '^[a-z-]+:.*?## .*$$' $(firstword $(MAKEFILE_LIST)) | awk 'BEGIN{FS=":.*?## "};{printf "  \033[1m%-10s\033[0m %s\n", $$1, $$2}'

install:  ## Installe LiteLLM (pip)
	pip install 'litellm[proxy]'

proxy:  ## Lance le proxy LiteLLM au premier plan
	litellm --config config.yaml --port $(PROXY_PORT)

up:  ## Lance le proxy via Docker
	docker compose up -d

down:  ## Arrête le proxy Docker
	docker compose down

logs:  ## Suit les logs du proxy Docker
	docker compose logs -f

check:  ## Diagnostic complet de la chaîne
	@./scripts/check.sh all

models:  ## Liste les modèles servis par Scaleway
	@./scripts/check.sh models

tools:  ## Teste le tool calling (le test déterminant)
	@./scripts/check.sh tools

env:  ## Affiche les exports à coller pour lancer Claude Code
	@echo 'export ANTHROPIC_BASE_URL=http://0.0.0.0:$(PROXY_PORT)'
	@echo 'export ANTHROPIC_AUTH_TOKEN=$(PROXY_KEY)'
	@echo 'export ANTHROPIC_API_KEY=""'
	@echo '# puis :  claude --model $(MODEL)'
