# BLIP — build & verification entry points.
#
# `make test` runs the whole suite; the targets below are the pieces. Generated
# artifacts live under microcode/build/ (gitignored); sim build artifacts go to /tmp.
# The timed test-benches run under Icarus -gspecify (D-47) and $fatal on failure, so
# `make test` is a real pass/fail gate (it stops at the first red).
#
# Needs the WSL toolchain: iverilog, verilator, yosys, python3. `make help` lists targets.

PYTHON := python3
# TOP selects which module the viz targets render. Empty default: `viz` renders every
# block, `digitaljs` renders uc_loader. Override per run, e.g. `make viz TOP=microsequencer`.
TOP    ?=
# MODE selects the logisim action: empty/auto (reconcile-if-exists), generate (buses by
# default), flat (1-bit generate), insert.
MODE   ?=

.NOTPARALLEL:
.PHONY: test image check lint sim cpu bench viz logisim logisim-test digitaljs clean help

## test:   run the whole suite (image, field-def check, both lints, tool + timed test-benches)
test: image check lint logisim-test sim
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
sim: cpu bench

## cpu:    boot copy (real loader + EEPROM -> WCS) then the microsequencer walk
##         (INC/JUMP/BRANCH/DISPATCH/WAIT) — the loader is proven on this standard path
cpu:
	bash sim/tb/cpu/run.sh

## bench:  two-engine throughput benchmark (Verilator vs timed Icarus)
bench:
	bash sim/bench/run.sh

## viz:    schematic SVG of every HDL block — Yosys -> netlistsvg (one via TOP=<module>)
viz:
	bash tools/viz/render.sh $(TOP)

## logisim: keep a Logisim Evolution 4.1.0 .circ in step with a block (Yosys -> logisim.py).
##          First run GENERATEs the .circ (multi-bit nets as buses + splitters); after that it
##          RECONCILEs (LVS diff vs the HDL, never overwrites your edits). MODE=generate forces
##          a fresh .circ, MODE=flat a 1-bit one, MODE=insert splices in chips the HDL added.
logisim:
	bash tools/viz/logisim.sh $(TOP) $(MODE)

## logisim-test: hermetic self-test of the logisim generator + LVS reconciler (no Yosys)
logisim-test:
	$(PYTHON) tools/viz/test_logisim.py

## digitaljs: interactive DigitalJS sim from the HDL — Yosys -> yosys2digitaljs
##            (default TOP=uc_loader; the whole cpu has a tri-state control-store
##            bus DigitalJS can't model — use `make viz` for the cpu schematic)
digitaljs:
	bash tools/viz/digitaljs.sh $(TOP)

## clean:  remove generated artifacts (keeps the hand-edited logisim/build/*.circ)
clean:
	rm -rf microcode/build tools/viz/build
	rm -f logisim/build/*.netlist.json

## help:   list these targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed -E 's/^## //'
