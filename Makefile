# Available images for testing
_image_names := $(basename $(notdir $(wildcard tests/systems/*.dockerfile)))

# Print this help
help:
	@echo "Usage:"
	@sed -nE '/^# (.+)/{ s//   \1/;h;n; /^([a-z-]+):.*/ { s// make \1/;p;g;p } }' Makefile

# Run all tests (alias to system-tests)
all: system-tests

# Declare non-file targets as phony, for safety and performance
.PHONY: help all

##
## UNIT TESTS
##

_unit_tests := $(shell find . -name 'test_*.sh' -a \! -name '*system.sh')

# Run all unit tests locally
unit-test: $(_unit_tests:=-run)
	@echo "Ran $(words $^) test files."

# Removes the -run suffix and execute each file
$(_unit_tests:=-run):
	$(@:-run=)

# Run all unit tests on all base images
unit-tests: $(_image_names:=-unit)
	@echo ">>>>>>  COMPLETED $(words $^) UNITS"

# Run each image unit test, depends on image build
$(_image_names:=-unit): %-unit: %
	@echo ">>>>>>  UNIT TEST $<"
	@docker run --rm -v "$$PWD:/app:ro" -w /app -e DOTFILES=/app ${<:=-test}:base sh -c "$(_unit_tests:.sh=.sh &&) true"

.PHONY: unit-test unit-tests $(_unit_tests:=-run) $(_image_names:=-unit)

##
## SYSTEM TESTS
##

_systems_tests := $(shell find . -name 'test_*.system.sh')

# Run system tests on one image
system-test: $(firstword $(_image_names))-system

# Run all unit and system tests on all images
system-tests: $(_image_names:=-system)
	@echo ">>>>>>>>  COMPLETED $(words $^) SYSTEMS"

# Run each image system test, depends on image build and unit run
$(_image_names:=-system): %-system: % %-unit
	@echo ">>>>>>>>  SYSTEM TESTS $<"
	@tests/run_system_test.sh $< $(_systems_tests)

.PHONY: system-test system-tests $(_image_names:=-system)

##
## DOCKER IMAGES
##

# Dockerfile location
vpath %.dockerfile ./tests/systems

# Build each stage in the dockerfile and tag as {image_name}-test:{stage}
$(_image_names): %: %.dockerfile
	@echo ">>  BUILD $@ targets"
	@sed -nE '/^FROM.* AS (.+)/I s//\1/p' $< |\
		xargs -I {} docker build -q --target "{}" -t $@-test:"{}" -f $< .

# Clean all cached images
clean-images:
	@for name in $(_image_names); do \
		docker rmi $${name}-test || true; \
	done

.PHONY: $(_image_names) clean-images