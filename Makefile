# Available enviroments
DOCKERFILES = ubuntu-bionic ubuntu-focal

# Default target for make
all: unit-tests system-tests

##
## UNIT TESTS
##

files_unit_test := $(wildcard tests/unit/*.sh tests/unit/*/*.sh)
runs_unit_test := $(files_unit_test:=-run)

unit-tests: $(runs_unit_test)
	@echo "Run $(words $(runs_unit_test)) test files."

$(runs_unit_test):
  # Removes the -run suffix and execute the file
	$(@:-run=)

##
## SYSTEM TESTS
##

# Dockerfile location
vpath %.dockerfile ./tests/systems

files_system_test := $(wildcard tests/system/*.sh tests/system/*/*.sh)

dockerfile_builds := $(DOCKERFILES:=-build)
dockerfile_runs := $(DOCKERFILES:=-run)

system-tests: $(dockerfile_runs)
	@echo "All system tests run."

$(dockerfile_runs): %-run: %-build
	@echo "\n>>>>>>>>>>>>>>>>>>    $@    <<<<<<<<<<<<<<<<<<"
	@for file in $(files_system_test); do \
		docker run --rm -v "${PWD}:/app" ${@:-run=-test} "app/$$file"; \
	done

$(dockerfile_builds): %-build: %.dockerfile
	@echo "\n>>>>>>>>>>>>>>>>>>    $@    <<<<<<<<<<<<<<<<<<"
	docker build -t ${@:-build=-test} -f $< .

clean-images:
	@for name in $(DOCKERFILES); do \
		docker rmi $${name}-test:latest || true; \
	done

# Declare targets that don't produce files as phony, for safety and performance
.PHONY: all unit-tests $(runs_unit_test)
.PHONY: $(dockerfile_builds) $(dockerfile_runs) system-tests
.PHONY: clean-images