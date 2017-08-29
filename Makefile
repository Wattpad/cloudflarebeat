# expect makefiles that include this to define the following variables
# go_version - must be a fully specified go version that matches a docker image (1.7.3, not 1.7)
# extra_build_deps - list of extra targets as dependencies for the build stage (eg, generate)
# target_binary - filename to use as the output binary, if not specified will default to the directory name

default: test

go_version ?= 1.8.1
build_image ?= true
is_library ?= false

docker_registry = 723255503624.dkr.ecr.us-east-1.amazonaws.com

project_dir := $(dir $(abspath $(firstword $(MAKEFILE_LIST))))
builder_image := golang:${go_version}-alpine
project_name ?= $(shell basename $(project_dir))
git_hash := $(shell git describe --long --tags --dirty --always)
output_image := "$(project_name):$(shell git rev-parse HEAD)"
devvm_image := $(docker_registry)/$(project_name):dev-vm

target_binary ?= ${project_name}

go_ldflags := -ldflags "-X main.Version=${git_hash}"

highlander_root := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
work_dir := $(shell perl -e 'use File::Spec; print File::Spec->abs2rel(@ARGV) . "\n"' ${project_dir} ${highlander_root})

# docker argument support:
# older versions require --force while newer versions don't support the tag
docker_tag_force_arg := $(shell docker tag --help | grep -q -e "--force" && echo "--force")
# older versions don't support labeling from the CLI
docker_build_label_arg := $(shell docker build --help | grep -q -e "--label" && echo "--label=\"git_hash=$(git_hash)\"")

# if the project does not want images built, hack to avoid build target as a dependency
ifneq ($(is_library),false)
	build_binary = false
else ifeq ($(MAKECMDGOALS),build)
	build_binary = true
else ifeq ($(build_image),true)
	build_binary = true
endif

# disable building images if there is no Dockerfile
ifeq ($(wildcard Dockerfile),)
	build_image = false
endif

########## TARGETS ##########

## BUILD
build: clean ${extra_build_deps}
ifeq ($(build_binary),true)
	docker run --rm -v ${highlander_root}:/highlander \
		-w /highlander/${work_dir} \
		-e GOPATH=/highlander/vendor:/highlander/wattpad \
		${builder_image} go build ${go_ldflags} -o ${target_binary} .
else
	@echo "binary building disabled for ${project_name}"
endif

## CLEAN
clean:
	rm -f ${target_binary}

## IMAGE
image: build
ifeq ($(build_image),true)
	docker build $(docker_build_label_arg) -t ${output_image} .
	docker tag $(docker_tag_force_arg) $(output_image) $(devvm_image)
else
	@echo "image building disabled for ${project_name}"
endif

## PUSH_IMAGE
push_image: image
ifeq ($(build_image),true)
	docker tag $(docker_tag_force_arg) ${output_image} ${docker_registry}/${output_image}
	docker push ${docker_registry}/${output_image}
	docker push $(devvm_image)
else
	@echo "image building disabled for ${project_name}"
endif

## TEST
ifneq ($(is_library),false)
	unused_flag="-exported"
endif
test: ${extra_build_deps}
	docker run --rm -v ${highlander_root}:/highlander \
		-w /highlander/${work_dir} \
		-e GOPATH=/highlander/vendor:/highlander/wattpad \
		-e GOBIN=/go/bin \
		-e CGO_ENABLED=0 \
		-e WATTPAD_ENV=local \
		-e SECURE_PATH=/dev/null \
		-e CONFIG_PATH=/highlander/testconfig.cfg \
		-e AWS_SECRET_ACCESS_KEY=secret \
		-e AWS_ACCESS_KEY_ID=key \
		${builder_image} /bin/sh -c "go version ; \
			go install honnef.co/go/staticcheck/cmd/staticcheck ; \
			go install honnef.co/go/unused/cmd/unused ; \
			go install github.com/HewlettPackard/gas ; \
			go vet ./... && \
			staticcheck ./... && \
			unused ${unused_flag} ./... && \
			/highlander/ci/run_gas.sh && \
			go test ./..."

## VARS
vars:
	@echo "project_dir: ${project_dir}"
	@echo "work_dir: ${work_dir}"
	@echo "highlander_root: ${highlander_root}"
	@echo "output_image: ${output_image}"
	@echo "target_binary: ${target_binary}"
	@echo "git_hash: ${git_hash}"BEATNAME=cloudflarebeat

ES_BEATS?=./vendor/github.com/elastic/beats


# Path to the libbeat Makefile
-include $(ES_BEATS)/libbeat/scripts/Makefile
