# Available enviroments
BASE_IMAGES = ubuntu-bionic ubuntu-focal

# Default target for make
all: unit-tests system-tests

##
## UNIT TESTS
##

_unit_test_files := $(wildcard tests/unit/*.sh tests/unit/*/*.sh)
_unit_test_runs := $(_unit_test_files:=-run)

# Run all unit tests and print summary
unit-tests: $(_unit_test_runs)
	@echo "Ran $(words $(_unit_test_runs)) test files."

# Removes the -run suffix and execute the file
$(_unit_test_runs):
	$(@:-run=)

##
## SYSTEM TESTS
##

_system_test_files := $(wildcard tests/system/*.sh tests/system/*/*.sh)
_system_test_runs := $(BASE_IMAGES:=-run)

# Run all system tests and print summary
system-tests: images $(_system_test_runs)
	@echo "Ran tests over $(words $(_system_test_runs)) systems."

# Run each system test
$(_system_test_runs):
	@echo "\n>>>>>>>>>>>>>>>>>>    $@    <<<<<<<<<<<<<<<<<<"
	@tests/system/run_system_test.sh ${@:-run=} tests/system/test_*

##
## DOCKER IMAGES
##

# Dockerfile location
vpath %.dockerfile ./tests/systems

_system_images := $(basename $(notdir $(wildcard tests/systems/*.dockerfile)))
_system_image_builds := $(_system_images:=-build)

# Alias to build all images
images: $(_system_image_builds)

# Build each docker image
$(_system_image_builds): %-build: %.dockerfile
	@echo "\n>>>>>>>>>>>>>>>>>>    $@    <<<<<<<<<<<<<<<<<<"
	docker build -t ${@:-build=-test} -f $< .

# Clean all cached system docker images
clean-images:
	@for name in $(_system_images); do \
		docker rmi $${name}-test:latest || true; \
	done

# Declare targets that don't produce files as phony, for safety and performance
.PHONY: all unit-tests $(_unit_test_runs)
.PHONY: system-tests $(_dockerfile_builds) $(_system_test_runs)
.PHONY: images clean-images