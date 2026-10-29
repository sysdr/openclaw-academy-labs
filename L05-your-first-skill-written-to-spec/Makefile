.PHONY: bootstrap setup build run test verify demo clean

bootstrap: ## recreate the L03/L04 end state if you skipped them
	@bash scripts/bootstrap.sh
setup: ## install the skill into your workspace, register and start the probe model
	@bash scripts/setup.sh
build: ## lint the skill, validate JSON and Python, dry-run the config patch
	@bash scripts/build.sh
run: ## send one ordinary request through a real agent turn
	@bash scripts/run.sh
test: ## unit tests + verify.sh against the mock (no OpenClaw needed)
	@bash scripts/test.sh
verify: ## the PROOF: spec, discovery, activation test
	@bash scripts/verify.sh
demo: ## 60-second walkthrough
	@bash scripts/demo.sh
clean: ## stop the probe, remove local state (asks before touching your workspace)
	@bash scripts/clean.sh
