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
.PHONY: test image browser check lint sim cpu reg regfile alu right cc ccx mem lane lanex uloop irqx ldz prog fetch exec bench viz logisim logisim-test digitaljs bom clean help

## test:   run the whole suite (image, field-def check, both lints, tool + timed test-benches)
test: image check lint logisim-test sim
	@echo "=== ALL GREEN ==="

## image:  assemble the microcode into the single EEPROM image (microcode/build/)
image:
	$(PYTHON) tools/uasm/uasm.py

## browser: generate the HTML microcode browser (microcode/build/microcode.html)
browser:
	$(PYTHON) microcode/gen_browser.py

## check:  validate the 88-bit control-word field definition
check:
	$(PYTHON) microcode/check_fields.py

## lint:   structural-only gate (R-SIM-5) + timing-presence gate (D-47)
lint:
	$(PYTHON) tools/lint/structural_lint.py
	$(PYTHON) tools/lint/timing_lint.py

## sim:    the timed, self-checking test-benches
sim: cpu reg regfile alu right cc ccx mem lane lanex uloop irqx ldz prog fetch exec bench

## cpu:    boot copy (real loader + EEPROM -> WCS) then the microsequencer walk
##         (INC/JUMP/BRANCH/DISPATCH/WAIT) — the loader is proven on this standard path
cpu:
	bash sim/tb/cpu/run.sh

## reg:    the universal '163-counter register board (load/count/carry/hold/LEFT)
reg:
	bash sim/tb/reg/run.sh

## regfile: D/X/Y/USP/SSP + ACTIVE_SP banking through the datapath
regfile:
	bash sim/tb/regfile/run.sh

## alu:    the 16-bit ALU (arithmetic + logic + shift sections) + N/Z/V/C/H flags
alu:
	bash sim/tb/alu/run.sh

## right:  the ALU RIGHT source bus — SCR1/SCR2 + const-gen {-2,-1,0,+1,+2}
right:
	bash sim/tb/right/run.sh

## cc:     the condition-code board — flag writes, V/C_SRC, Z_ACCUM, conditions, M/I privilege
cc:
	bash sim/tb/cc/run.sh

## ccx:    privileged M/I through the datapath — SEI/CLI (I-only), WHOLE_Z restore, user-mode lock
ccx:
	bash sim/tb/ccx/run.sh

## mem:    the MDR + external-bus port — stage/WRITE/READ round trip vs a memory model
mem:
	bash sim/tb/mem/run.sh

## lane:   the byte-lane steer blocks — LEFT_LANE widen/move + Z_LANE byte-promote (unit)
lane:
	bash sim/tb/lane/run.sh

## lanex:  byte-lane steering through the whole datapath — Z_LANE byte-build + LEFT_LANE widen
lanex:
	bash sim/tb/lanex/run.sh

## ldz:    a memory read posts on Z — latch a register + N/Z in one microword
ldz:
	bash sim/tb/ldz/run.sh

## prog:   END-TO-END production blip.uc — fetch/dispatch/execute/refetch a real program
prog:
	bash sim/tb/prog/run.sh

## uloop:  the ULOOP micro-loop counter — load n, body runs n times (real cond[8] terminal)
uloop:
	bash sim/tb/uloop/run.sh

## irqx:   internal microconditions — IRQ/NMI/WAIT_READY gate the sequencer (real cond[9..11])
irqx:
	bash sim/tb/irqx/run.sh

## fetch:  REAL instruction fetch — PC -> MMU -> memory model -> MDR -> IR -> DISPATCH
fetch:
	bash sim/tb/fetch/run.sh

## exec:   REAL execute + branch — compute -> CC -> branch on the live condition (closes cond_drive)
exec:
	bash sim/tb/exec/run.sh

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

## bom:    package count — flatten each board-level top (Yosys) and tally real chips
bom:
	$(PYTHON) tools/bom/chipcount.py

## clean:  remove generated artifacts (keeps the hand-edited logisim/build/*.circ)
clean:
	rm -rf microcode/build tools/viz/build
	rm -f logisim/build/*.netlist.json

## help:   list these targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed -E 's/^## //'
