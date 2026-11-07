# Entry point for everything in this repo: `make help`. CI calls the same targets.

TAG ?=
SH_FILES := $(shell find build plugin tests -name '*.sh') plugin/src/etc/rc.d/warpgate
XML_FILES := $(shell find plugin -name '*.xml')
PHP_FILES := $(shell find plugin tests -name '*.php' -o -name '*.inc')
PY_FILES := $(shell find plugin tests -name '*.py')

.DEFAULT_GOAL := help
.PHONY: help binary genkey lint test

help: ## list targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

## build / release

binary: ## cross-build warpgate for FreeBSD into out/dist (TAG=vX.Y.Z, default: latest upstream)
	build/warpgate/build.sh $(TAG)

genkey: ## create the signing key pair (once)
	build/genkey.sh

test: ## behaviour tests: config/secrets, certificate export, model validation, bootstrap (TAG=vX.Y.Z)
	tests/run.sh $(TAG)

lint: ## shellcheck, php -l, python syntax, XML well-formedness (in Docker)
	docker run --rm -v "$(CURDIR):/mnt:ro" -w /mnt koalaman/shellcheck:stable $(SH_FILES)
	docker run --rm -v "$(CURDIR):/mnt:ro" -w /mnt php:8.4-cli sh -c \
	  'for f in $(PHP_FILES); do php -l "$$f" >/dev/null || exit 1; done; \
	   php -r "foreach (array_slice(\$$argv, 1) as \$$f) if (!simplexml_load_file(\$$f)) exit(1);" $(XML_FILES)'
	docker run --rm -v "$(CURDIR):/mnt:ro" -w /mnt python:3.13-slim python -c \
	  'import ast, sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]' $(PY_FILES)
	@echo lint ok
