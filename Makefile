SH_FILES = bin/orchestra install.sh lib/*.sh adapters/*.sh $(WORKSPACE)/*.sh
EXAMPLE = examples/blog-api
WORKSPACE = examples/workspace

.PHONY: check lint test schemas

check: lint schemas test

# SC2016 is excluded: single-quoted `$x` here is always a jq variable or a
# markdown backtick, never a missed shell expansion.
lint:
	shellcheck -s sh -e SC2016 $(SH_FILES)

# Schemas are valid, and the shipped templates + example conform to them.
schemas:
	check-jsonschema --check-metaschema schemas/*.schema.json
	check-jsonschema --schemafile schemas/config.schema.json templates/orchestra.config.json $(EXAMPLE)/orchestra.config.json $(WORKSPACE)/orchestra.config.json
	check-jsonschema --schemafile schemas/plan.schema.json templates/plan.json $(EXAMPLE)/plan.json $(WORKSPACE)/plan.json
	check-jsonschema --schemafile schemas/traceability.schema.json templates/traceability.json $(EXAMPLE)/traceability.json $(WORKSPACE)/traceability.json
	check-jsonschema --schemafile schemas/verdict.schema.json $(EXAMPLE)/samples/verdict-*.json
	check-jsonschema --schemafile schemas/confirmation.schema.json $(EXAMPLE)/samples/confirmation-*.json

test:
	bats test/
