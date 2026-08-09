.PHONY: up up-ai up-full down logs health clone-siblings sync-siblings

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

# Клон/обновление всех sibling-реп с origin/main (финальная ветка).
clone-siblings sync-siblings:
	@./scripts/clone-siblings.sh
