# Available images
BASE_IMAGES = ubuntu-bionic ubuntu-focal amazonlinux-2

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
unit-tests: $(BASE_IMAGES:=-unit)
	@echo ">>>>>>  COMPLETED $(words $^) UNITS"

# Run each image unit test, depends on image build
$(BASE_IMAGES:=-unit): %-unit: %
	@echo ">>>>>>  UNIT TEST $<"
	@docker run --rm -v "$$PWD:/app:ro" -w /app -e DOTFILES=/app ${<:=-test} sh -c "$(_unit_tests:.sh=.sh &&) true"

.PHONY: unit-test unit-tests $(_unit_tests:=-run) $(BASE_IMAGES:=-unit)

##
## SYSTEM TESTS
##

_systems_tests := $(shell find . -name 'test_*.system.sh')

# Run system tests on one image
system-test: $(firstword $(BASE_IMAGES))-system

# Run all unit and system tests on all images
system-tests: $(BASE_IMAGES:=-system)
	@echo ">>>>>>>>  COMPLETED $(words $^) SYSTEMS"

# Run each image system test, depends on image build and unit run
$(BASE_IMAGES:=-system):: %-system: % images %-unit
	@echo ">>>>>>>>  SYSTEM TESTS $<"
	@tests/run_system_test.sh $< $(_systems_tests)

.PHONY: system-tests $(BASE_IMAGES:=-system)

##
## DOCKER IMAGES
##

# Dockerfile location
vpath %.dockerfile ./tests/systems

_image_names := $(basename $(notdir $(wildcard tests/systems/*.dockerfile)))

# Just build all images
images: $(_image_names)

# Build main docker images
$(BASE_IMAGES): %: %.dockerfile
	@echo ">>  BUILD $@"
	@docker build -q -t ${@:=-test} -f $< .

# Build auxiliary docker images
$(filter-out $(BASE_IMAGES),$(_image_names)): %: %.dockerfile
	@echo ">>> BUILD $@"
	@docker build -q -t ${@:=-test} -f $< .

# Clean all cached images
clean-images:
	@for name in $(_image_names); do \
		docker rmi $${name}-test:latest || true; \
	done

.PHONY: images $(_image_names) clean-images