SH_FILES = bin/orchestra install.sh lib/*.sh adapters/*.sh
EXAMPLE = examples/blog-api

.PHONY: check lint test schemas

check: lint schemas test

lint:
	shellcheck -s sh $(SH_FILES)

# Schemas are valid, and the shipped templates + example conform to them.
schemas:
	check-jsonschema --check-metaschema schemas/*.schema.json
	check-jsonschema --schemafile schemas/config.schema.json templates/orchestra.config.json $(EXAMPLE)/orchestra.config.json
	check-jsonschema --schemafile schemas/plan.schema.json templates/plan.json $(EXAMPLE)/plan.json
	check-jsonschema --schemafile schemas/traceability.schema.json templates/traceability.json $(EXAMPLE)/traceability.json
	check-jsonschema --schemafile schemas/verdict.schema.json $(EXAMPLE)/samples/verdict-*.json
	check-jsonschema --schemafile schemas/confirmation.schema.json $(EXAMPLE)/samples/confirmation-*.json

test:
	bats test/
