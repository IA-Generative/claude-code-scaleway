.PHONY: help install proxy up down logs check models tools env vscode shell repair
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

shell:  ## Sous-shell GLM, rien n'est ecrit (make shell DIR=~/dev/projet)
	@./scripts/shell.sh $(DIR)

vscode:  ## Fenetre VS Code sur GLM (make vscode DIR=~/dev/projet)
	@./scripts/vscode.sh $(DIR)

repair:  ## Repare Claude Code disparu de VS Code (make repair FIX=--fix)
	@./scripts/repair-vscode.sh $(FIX)

env:  ## Exports pour Claude Code - usage : eval "$$(make -s env)"
	@echo 'export ANTHROPIC_BASE_URL=http://127.0.0.1:$(PROXY_PORT)'
	@echo 'export ANTHROPIC_AUTH_TOKEN=$(PROXY_KEY)'
	@echo 'export ANTHROPIC_API_KEY=""'
	@echo 'export ANTHROPIC_MODEL=$(MODEL)'
	@echo 'puis :  claude --model $(MODEL)' >&2
