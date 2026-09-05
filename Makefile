SHELL := /bin/bash
.DEFAULT_GOAL := help

COMPOSE := docker compose
CATALOG_URL := postgresql://svcs:svcs@localhost:5433/catalog
TARGET_URL  := postgresql://app:app@localhost:5434/demo

# Row counts. ~2M rows is a few hundred MB; ~40M rows lands around 5GB with an index.
DEMO_ROWS ?= 2000000
BENCH_ROWS ?= 40000000

.PHONY: help demo up down restart rebuild logs sh ps \
        init-catalog seed-demo seed-bench psql-catalog psql-target \
        workload bench test test-unit test-int fmt lint check clean reset

## ---------------------------------------------------------------------------
## Getting started
## ---------------------------------------------------------------------------

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$|^## ' $(MAKEFILE_LIST) \
		| sed -e 's/^## //' -e 's/:.*## /\t/' \
		| awk -F'\t' '{ if (NF==1) print "\n\033[1m" $$1 "\033[0m"; \
		                else printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 }'

demo: up init-catalog seed-demo ## One command: start everything, seed the demo DB, open the app
	@echo ""
	@echo "  Ready → http://localhost:8000"
	@echo "  Demo target DB seeded with $(DEMO_ROWS) rows."
	@echo ""

## ---------------------------------------------------------------------------
## Day to day
## ---------------------------------------------------------------------------

up: ## Build and start app + catalog DB + target DB
	$(COMPOSE) up --build -d
	@$(COMPOSE) ps

down: ## Stop containers (keeps data)
	$(COMPOSE) down

restart: ## Restart just the app container
	$(COMPOSE) restart app

rebuild: ## Rebuild the app image from scratch (after a dependency change)
	$(COMPOSE) build --no-cache app && $(COMPOSE) up -d app

logs: ## Tail app logs
	$(COMPOSE) logs -f app

sh: ## Shell inside the app container
	$(COMPOSE) exec app bash

ps: ## Container status
	$(COMPOSE) ps

## ---------------------------------------------------------------------------
## Databases
## ---------------------------------------------------------------------------

init-catalog: ## Create the catalog schema (branches, commits, objects, jobs)
	$(COMPOSE) exec -T catalog_db psql -U svcs -d catalog < sql/catalog_schema.sql
	@echo "catalog schema applied"

seed-demo: ## Seed the target DB with $(DEMO_ROWS) rows (a few hundred MB)
	@ROWS=$(DEMO_ROWS) ./scripts/seed_target.sh
	@echo "target seeded: $(DEMO_ROWS) rows"

seed-bench: ## Seed the target DB with $(BENCH_ROWS) rows (~5GB — takes 15-30 min)
	@echo "Seeding $(BENCH_ROWS) rows. This is slow on purpose. Go make coffee."
	@ROWS=$(BENCH_ROWS) ./scripts/seed_target.sh
	@$(COMPOSE) exec -T target_db psql -U app -d demo \
		-c "select pg_size_pretty(pg_total_relation_size('orders')) as size;"

psql-catalog: ## psql into the catalog DB
	$(COMPOSE) exec catalog_db psql -U svcs -d catalog

psql-target: ## psql into the demo target DB
	$(COMPOSE) exec target_db psql -U app -d demo

## ---------------------------------------------------------------------------
## The proof
## ---------------------------------------------------------------------------

workload: ## Run continuous concurrent read/write traffic against the target DB
	python scripts/workload.py --dsn "$(TARGET_URL)" --rate 50

bench: ## Full 5GB benchmark: seed, run workload, migrate online, write bench/output/
	@mkdir -p bench/output
	$(MAKE) seed-bench
	./scripts/run_benchmark.sh 2>&1 | tee bench/output/run-$$(date +%Y%m%d-%H%M).log
	@echo "results → bench/output/"

## ---------------------------------------------------------------------------
## Quality
## ---------------------------------------------------------------------------

test: ## Run all tests
	pytest -q $(ARGS)

test-unit: ## Fast tests only — differ and merger, no database
	pytest -q tests/unit $(ARGS)

test-int: ## Integration tests against real Postgres containers
	pytest -q tests/integration $(ARGS)

fmt: ## Format and autofix
	ruff format . && ruff check --fix .

lint: ## Lint without changing files
	ruff format --check . && ruff check .

check: lint test ## What CI runs

## ---------------------------------------------------------------------------
## Cleanup
## ---------------------------------------------------------------------------

clean: ## Remove caches and build artifacts
	find . -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
	rm -rf .pytest_cache .ruff_cache

reset: ## DESTRUCTIVE — drop containers and all database volumes
	@read -p "Delete all local database data? [y/N] " ok && [ "$$ok" = "y" ]
	$(COMPOSE) down -v
	@echo "volumes removed"