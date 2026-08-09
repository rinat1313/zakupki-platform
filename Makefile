.PHONY: up up-ai up-full down logs health clone-siblings sync-siblings swagger

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

# Swagger UI for contracts/openapi/openapi.yaml → http://localhost:8081
swagger:
	@echo "Swagger UI: http://localhost:8081  (Ctrl+C to stop)"
	docker run --rm -p 8081:8080 \
		-e SWAGGER_JSON=/specs/openapi.yaml \
		-e BASE_URL=/ \
		-v "$(CURDIR)/contracts/openapi:/specs:ro" \
		swaggerapi/swagger-ui
