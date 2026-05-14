
# Available images for testing
_image_names := $(basename $(notdir $(wildcard tests/systems/*.dockerfile)))

# Print this help
help:
	@echo "Targets:"
	@sed -nE '/^# (.+)/{ s//   \1/;h;n; /^([a-z][a-z0-9-]*):.*/ { s//  make \1/;p;g;p } }' Makefile
	@echo ""
	@echo "Per-image targets (one per dockerfile in tests/systems/):"
	@for n in $(_image_names); do echo "  make unit-$$n   make system-$$n"; done
	@echo ""
	@echo "Filters (work with any target):"
	@echo "   FILE=path/to/test.sh   Run only tests in this file"
	@echo "   TEST=case_name         Run only the named test case"
	@echo ""
	@echo "Options:"
	@echo "   DEBUG=1                Show verbose outputs during builds and tests"

# Run all tests on all images (units + systems)
all: unit-tests system-tests

.PHONY: help all

##
## TEST FILE DISCOVERY (honors FILE= filter)
##

_unit_tests    := $(shell find . -name 'test_*.sh' -a \! -name '*system.sh')
_system_tests  := $(shell find . -name 'test_*.system.sh')
_unit_files    := $(if $(FILE),$(FILE),$(_unit_tests))
_system_files  := $(if $(FILE),$(FILE),$(_system_tests))

##
## UNIT TESTS
##

# Shell snippet: invokes tests/run_unit_tests.sh with the resolved file list and filter
_run_units = tests/run_unit_tests.sh $(if $(TEST),-t $(TEST)) $(_unit_files)

# Run all unit tests locally
unit:
	@$(_run_units)

# Run all unit tests on all docker images
unit-tests: $(addprefix unit-,$(_image_names))
	@echo ">>>>>>  COMPLETED $(words $^) UNIT RUNS"

# Run unit tests in a specific docker image (e.g. make unit-ubuntu)
$(addprefix unit-,$(_image_names)): unit-%: %
	@echo ">>>>>>  UNIT TESTS in $*"
	@docker run --rm -v "$$PWD:/app:ro" -w /app $*-test:base sh -c '$(_run_units)'

.PHONY: unit unit-tests $(addprefix unit-,$(_image_names))

##
## SYSTEM TESTS
##

# Run all system tests on all docker images
system-tests: $(addprefix system-,$(_image_names))
	@echo ">>>>>>>>  COMPLETED $(words $^) SYSTEM RUNS"

# Run system tests in a specific docker image (e.g. make system-ubuntu)
$(addprefix system-,$(_image_names)): system-%: %
	@echo ">>>>>>>>  SYSTEM TESTS in $*"
	@tests/run_system_test.sh $(if $(TEST),-t $(TEST)) $* $(_system_files)

.PHONY: system-tests $(addprefix system-,$(_image_names))

##
## DOCKER IMAGES
##

# Dockerfile location
vpath %.dockerfile ./tests/systems

# Build each stage in the dockerfile and tag as {image_name}-test:{stage}
$(_image_names): %: %.dockerfile
	@echo ">>  BUILD $@ targets"
	@sed -nE '/^FROM.* AS (.+)/I s//\1/p' $< |\
		xargs -I {} docker build $(if $(DEBUG),,-q) --target "{}" -t $@-test:"{}" -f $< .

# Clean all cached test images
clean-images:
	@for name in $(_image_names); do \
		docker rmi $${name}-test || true; \
	done

.PHONY: $(_image_names) clean-images
