.PHONY: up up-ai up-full down logs health clone-siblings sync-siblings swagger rebuild rebuild-ai rebuild-full

up:
	./up.sh

up-ai:
	./up.sh --ai

up-full:
	./up.sh --full

# После обновления в git: pull platform + siblings main, down, образы --no-cache, up.
rebuild:
	./up.sh --rebuild

rebuild-ai:
	./up.sh --ai --rebuild

rebuild-full:
	./up.sh --full --rebuild

down:
	./up.sh --down

logs:
	./up.sh --logs

health:
	./up.sh --health

# Клон/обновление всех sibling-реп с origin/main (финальная ветка).
clone-siblings sync-siblings:
	@./scripts/clone-siblings.sh

# Swagger UI for contracts/openapi/openapi.yaml → http://localhost:8081
swagger:
	@echo "Swagger UI: http://localhost:8081  (Ctrl+C to stop)"
	docker run --rm -p 8081:8080 \
		-e SWAGGER_JSON=/specs/openapi.yaml \
		-e BASE_URL=/ \
		-v "$(CURDIR)/contracts/openapi:/specs:ro" \
		swaggerapi/swagger-ui
