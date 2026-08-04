.PHONY: up up-ai up-full down logs health clone-siblings

COMPOSE ?= docker compose

up:
	$(COMPOSE) up -d --build postgres parser core customer gateway

up-ai:
	$(COMPOSE) --profile ai up -d --build

up-full:
	$(COMPOSE) --profile ai --profile redis --profile kafka up -d --build

down:
	$(COMPOSE) --profile ai --profile redis --profile kafka down

logs:
	$(COMPOSE) logs -f --tail=200

health:
	@./scripts/health.sh

clone-siblings:
	@./scripts/clone-siblings.sh
