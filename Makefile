.PHONY: up up-ai up-full down logs health clone-siblings

up:
	./up.sh

up-ai:
	./up.sh --ai

up-full:
	./up.sh --full

down:
	./up.sh --down

logs:
	./up.sh --logs

health:
	./up.sh --health

clone-siblings:
	@./scripts/clone-siblings.sh
