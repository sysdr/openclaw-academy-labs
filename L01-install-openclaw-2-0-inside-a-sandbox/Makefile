SHELL := /usr/bin/env bash
.PHONY: help bootstrap setup build run test verify demo stop clean

help:
	@echo "make bootstrap  check host prerequisites (Docker, Compose v2, port)"
	@echo "make setup      create .env, onboard OpenClaw inside the container"
	@echo "make build      pull the pinned image and validate compose"
	@echo "make run        start the sandboxed Gateway, wait until ready"
	@echo "make test       unit tests + mock end-to-end test (no OpenClaw needed)"
	@echo "make verify     prove the agent answers from inside the sandbox"
	@echo "make demo       60-second walkthrough to show someone"
	@echo "make stop       stop Gateway and related Docker services"
	@echo "make clean      stop containers (asks before deleting state)"

bootstrap: ; @bash scripts/bootstrap.sh
setup:     ; @bash scripts/setup.sh
build:     ; @bash scripts/build.sh
run:       ; @bash scripts/run.sh
test:      ; @bash scripts/test.sh
verify:    ; @bash scripts/verify.sh
demo:      ; @bash scripts/demo.sh
stop:      ; @bash scripts/stop.sh
clean:     ; @bash scripts/clean.sh
