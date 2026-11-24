SH_FILES = bin/orchestra install.sh lib/*.sh adapters/*.sh

.PHONY: check lint test schemas

check: lint schemas test

lint:
	shellcheck -s sh $(SH_FILES)

schemas:
	check-jsonschema --check-metaschema schemas/*.schema.json

test:
	bats test/
