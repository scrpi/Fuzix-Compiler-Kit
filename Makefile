# BLIP — build & verification entry points.
#
# `make test` runs the whole suite; the targets below are the pieces. Generated
# artifacts live under microcode/build/ (gitignored); sim build artifacts go to /tmp.
# The timed test-benches run under Icarus -gspecify (D-47) and $fatal on failure, so
# `make test` is a real pass/fail gate (it stops at the first red).
#
# Needs the WSL toolchain: iverilog, verilator, yosys, python3. `make help` lists targets.

PYTHON := python3
# TOP selects which module the viz targets render; each has its own default
# (viz -> cpu, digitaljs -> uc_loader). Override per run, e.g. `make viz TOP=uc_loader`.
TOP    ?=

.NOTPARALLEL:
.PHONY: test image check lint sim loader cpu bench viz digitaljs clean help

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

## cpu:    cpu microsequencer walk (boot -> real sequencer: INC/JUMP/BRANCH/DISPATCH/WAIT)
cpu:
	bash sim/tb/cpu/run.sh

## bench:  two-engine throughput benchmark (Verilator vs timed Icarus)
bench:
	bash sim/bench/run.sh

## viz:    schematic SVG of the HDL — Yosys -> netlistsvg (default TOP=cpu)
viz:
	bash tools/viz/render.sh $(TOP)

## digitaljs: interactive DigitalJS sim from the HDL — Yosys -> yosys2digitaljs
##            (default TOP=uc_loader; the whole cpu has a tri-state control-store
##            bus DigitalJS can't model — use `make viz` for the cpu schematic)
digitaljs:
	bash tools/viz/digitaljs.sh $(TOP)

## clean:  remove generated artifacts
clean:
	rm -rf microcode/build tools/viz/build

## help:   list these targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed -E 's/^## //'
