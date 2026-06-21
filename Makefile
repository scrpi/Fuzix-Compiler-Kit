# BLIP — build & verification entry points.
#
# `make test` runs the whole suite; the targets below are the pieces. Generated
# artifacts live under microcode/build/ (gitignored); sim build artifacts go to /tmp.
# The timed test-benches run under Icarus -gspecify (D-47) and $fatal on failure, so
# `make test` is a real pass/fail gate (it stops at the first red).
#
# Needs the WSL toolchain: iverilog, verilator, yosys, python3. `make help` lists targets.

PYTHON := python3

.NOTPARALLEL:
.PHONY: test image check lint sim loader cpu bench clean help

## test:   run the whole suite (image, field-def check, both lints, timed test-benches)
test: image check lint sim
	@echo "=== ALL GREEN ==="

## image:  assemble the microcode into the single EEPROM image (microcode/build/)
image:
	$(PYTHON) tools/uasm/uasm.py

## check:  validate the 88-bit control-word field definition
check:
	$(PYTHON) microcode/check_fields.py

## lint:   structural-only gate (R-SIM-5) + timing-presence gate (D-47)
lint:
	$(PYTHON) tools/lint/structural_lint.py
	$(PYTHON) tools/lint/timing_lint.py

## sim:    the timed, self-checking test-benches
sim: loader cpu bench

## loader: boot-loader test-bench (EEPROM -> 13 control-store SRAMs)
loader: image
	bash sim/tb/loader/run.sh

## cpu:    cpu top-level scaffold (boot -> run handoff; micro-PC reads the store)
cpu: image
	bash sim/tb/cpu/run.sh

## bench:  two-engine throughput benchmark (Verilator vs timed Icarus)
bench:
	bash sim/bench/run.sh

## clean:  remove generated artifacts
clean:
	rm -rf microcode/build

## help:   list these targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed -E 's/^## //'
