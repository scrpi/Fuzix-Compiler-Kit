# ===========================================================================
# BLIP microcode source — the complete instruction set (all 462 opcodes).
#
# Register-transfer notation of docs/microcode-source.md; assembled by
# tools/uasm/uasm.py against microcode/control_word.toml.  EACH STATEMENT IS
# ONE MICROWORD = ONE CYCLE (strict 1:1, P2) — so counting the lines of a
# routine counts its cycles.
#
# This file is GENERATED from isa/opcodes.toml (the single source of truth for
# the instruction set) by microcode/gen_microcode.py, the same way isa.md's
# opcode table is generated.  The per-mode and per-operation cycle sequences are
# hand-designed in that generator; the expansion over every opcode and the
# opcode->routine bindings are mechanical, so coverage is complete and uniform.
#
# Notation used here (docs/microcode-source.md §14 left some glyphs open; these
# are the choices this source commits to):
#   <-            register transfer            : nz, v=0   flag write clause
#   [PC] / [MAR]  memory read at PC / MAR       [MAR] <-   memory write (LEFT drives data)
#   R++           off-bus +1 counter tick       R - 1      ALU add of a -2..+2 const-gen value
#   low(r)/high(r)/sext(r)   lane steer         a +c b / a -c b   ADC / SBC (carry-in = CC.C)
#   _ <- expr     compute for flags only (Z_DEST = none — CMP/BIT/TST)
#   R <- 0        load a const-gen value via PASS_R (CLR / clears)
#   goto L / if <cond> goto L / call R / return / return to fetch / dispatch [page1]
#   count -> uloop ; uloop-- ; if not uloop.zero goto L      the dedicated loop counter
#   cc(whole|and|or) / mi(enter|set_i|clr_i) / map(kernel|user|imm8) / pt(read|write)
#   lock / unlock   hold the bus across an RMW (TAS_LOCK)
#   vector(NAME)    the hardwired trap-vector slot address (materialized by the trap logic)
#   reg[src]/reg[dst]   the register-move selector nibbles drive the register-file ports
#
# Conditions (§9): z c n v, c|z, n^v, z|(n^v), true, and the microconditions
# uloop irq nmi …; prefix `not` inverts.  Every routine ends by RETURN-to-FETCH
# (trap-intercepted instruction boundary), DISPATCH, or a JUMP — never by
# falling into the next routine.
#
# A handful of genuinely under-specified routines carry a `REVIEW:` note (MUL
# flags, DAA correction, LDMMU/STMMU entry format, CWAI framing, the selector-
# driven register moves): the datapath capability they assume is called out so
# simulation can settle it.
# ===========================================================================


# ---------------------------------------------------------------------------
# FETCH — the fixed fetch entry (microaddress 0).  RESET and every routine's
# `return to fetch` land here (a pending trap is vectored away by hardware).
# ---------------------------------------------------------------------------
.fetch FETCH
routine FETCH:
  IR <- [PC]; PC++; dispatch          # read opcode @PC -> IR, PC+1, dispatch via the LUT

# 0x80 — the page-1 prefix: a one-step routine that re-fetches the real
# opcode and re-dispatches on page 1 (isa.md §5.1).  page0[0x80] in the
# opcode LUT points here (0x80 is reserved as the prefix, not an opcode).
.opcode page0 0x80 PREFIX_P1
routine PREFIX_P1:
  IR <- [PC]; PC++; dispatch page1    # second opcode byte -> IR, dispatch on page 1

# Shared tail for taken Bcc/LBcc: apply the sign-extended displacement.
routine BR_TAKEN:
  PC <- PC + SCR1 ; return to fetch

# ===========================================================================
# PAGE 0 · Byte load/store (A, B)
# ===========================================================================
# 0x00 LD A,$nn   (1 cyc)
.opcode page0 0x00 LD A,$nn
routine LD A,$nn:
  A <- [PC]; PC++ : nz, v=0 ; return to fetch

# 0x01 LD A,(SP+n8)   (4 cyc)
.opcode page0 0x01 LD A,(SP+n8)
routine LD A,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  A  <- [MAR] : nz, v=0 ; return to fetch

# 0x02 LD A,(SP)   (2 cyc)
.opcode page0 0x02 LD A,(SP)
routine LD A,(SP):
  MAR  <- SP
  A  <- [MAR] : nz, v=0 ; return to fetch

# 0x03 LD A,(X)   (2 cyc)
.opcode page0 0x03 LD A,(X)
routine LD A,(X):
  MAR  <- X
  A  <- [MAR] : nz, v=0 ; return to fetch

# 0x04 LD A,(X+n8)   (4 cyc)
.opcode page0 0x04 LD A,(X+n8)
routine LD A,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  A  <- [MAR] : nz, v=0 ; return to fetch

# 0x05 LD A,(X+)   (2 cyc)
.opcode page0 0x05 LD A,(X+)
routine LD A,(X+):
  MAR  <- X
  A  <- [MAR] ; X++ : nz, v=0 ; return to fetch

# 0x06 LD A,(X+D)   (3 cyc)
.opcode page0 0x06 LD A,(X+D)
routine LD A,(X+D):
  SCR1 <- D
  MAR  <- X + SCR1
  A  <- [MAR] : nz, v=0 ; return to fetch

# 0x07 LD A,($nnnn)   (4 cyc)
.opcode page0 0x07 LD A,($nnnn)
routine LD A,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  A  <- [MAR] : nz, v=0 ; return to fetch

# 0x08 LD A,(Y)   (2 cyc)
.opcode page0 0x08 LD A,(Y)
routine LD A,(Y):
  MAR  <- Y
  A  <- [MAR] : nz, v=0 ; return to fetch

# 0x09 LD A,(Y+)   (2 cyc)
.opcode page0 0x09 LD A,(Y+)
routine LD A,(Y+):
  MAR  <- Y
  A  <- [MAR] ; Y++ : nz, v=0 ; return to fetch

# 0x0a LD A,(Y+n8)   (4 cyc)
.opcode page0 0x0a LD A,(Y+n8)
routine LD A,(Y+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- Y + SCR1
  A  <- [MAR] : nz, v=0 ; return to fetch

# 0x0b LD B,$nn   (1 cyc)
.opcode page0 0x0b LD B,$nn
routine LD B,$nn:
  B <- [PC]; PC++ : nz, v=0 ; return to fetch

# 0x0c LD B,(SP+n8)   (4 cyc)
.opcode page0 0x0c LD B,(SP+n8)
routine LD B,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  B  <- [MAR] : nz, v=0 ; return to fetch

# 0x0d LD B,(SP)   (2 cyc)
.opcode page0 0x0d LD B,(SP)
routine LD B,(SP):
  MAR  <- SP
  B  <- [MAR] : nz, v=0 ; return to fetch

# 0x0e LD B,(X)   (2 cyc)
.opcode page0 0x0e LD B,(X)
routine LD B,(X):
  MAR  <- X
  B  <- [MAR] : nz, v=0 ; return to fetch

# 0x0f LD B,(X+n8)   (4 cyc)
.opcode page0 0x0f LD B,(X+n8)
routine LD B,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  B  <- [MAR] : nz, v=0 ; return to fetch

# 0x10 LD B,(X+)   (2 cyc)
.opcode page0 0x10 LD B,(X+)
routine LD B,(X+):
  MAR  <- X
  B  <- [MAR] ; X++ : nz, v=0 ; return to fetch

# 0x11 LD B,(X+D)   (3 cyc)
.opcode page0 0x11 LD B,(X+D)
routine LD B,(X+D):
  SCR1 <- D
  MAR  <- X + SCR1
  B  <- [MAR] : nz, v=0 ; return to fetch

# 0x12 LD B,($nnnn)   (4 cyc)
.opcode page0 0x12 LD B,($nnnn)
routine LD B,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  B  <- [MAR] : nz, v=0 ; return to fetch

# 0x13 LD B,(Y)   (2 cyc)
.opcode page0 0x13 LD B,(Y)
routine LD B,(Y):
  MAR  <- Y
  B  <- [MAR] : nz, v=0 ; return to fetch

# 0x14 LD B,(Y+)   (2 cyc)
.opcode page0 0x14 LD B,(Y+)
routine LD B,(Y+):
  MAR  <- Y
  B  <- [MAR] ; Y++ : nz, v=0 ; return to fetch

# 0x15 LD B,(Y+n8)   (4 cyc)
.opcode page0 0x15 LD B,(Y+n8)
routine LD B,(Y+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- Y + SCR1
  B  <- [MAR] : nz, v=0 ; return to fetch

# 0x16 ST A,(SP+n8)   (4 cyc)
.opcode page0 0x16 ST A,(SP+n8)
routine ST A,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  [MAR] <- A : nz, v=0 ; return to fetch

# 0x17 ST A,(X)   (2 cyc)
.opcode page0 0x17 ST A,(X)
routine ST A,(X):
  MAR  <- X
  [MAR] <- A : nz, v=0 ; return to fetch

# 0x18 ST A,(X+n8)   (4 cyc)
.opcode page0 0x18 ST A,(X+n8)
routine ST A,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  [MAR] <- A : nz, v=0 ; return to fetch

# 0x19 ST A,(X+)   (2 cyc)
.opcode page0 0x19 ST A,(X+)
routine ST A,(X+):
  MAR  <- X
  [MAR] <- A ; X++ : nz, v=0 ; return to fetch

# 0x1a ST A,($nnnn)   (4 cyc)
.opcode page0 0x1a ST A,($nnnn)
routine ST A,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  [MAR] <- A : nz, v=0 ; return to fetch

# 0x1b ST A,(Y)   (2 cyc)
.opcode page0 0x1b ST A,(Y)
routine ST A,(Y):
  MAR  <- Y
  [MAR] <- A : nz, v=0 ; return to fetch

# 0x1c ST A,(Y+n8)   (4 cyc)
.opcode page0 0x1c ST A,(Y+n8)
routine ST A,(Y+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- Y + SCR1
  [MAR] <- A : nz, v=0 ; return to fetch

# 0x1d ST A,(Y+)   (2 cyc)
.opcode page0 0x1d ST A,(Y+)
routine ST A,(Y+):
  MAR  <- Y
  [MAR] <- A ; Y++ : nz, v=0 ; return to fetch

# 0x1e ST B,(SP+n8)   (4 cyc)
.opcode page0 0x1e ST B,(SP+n8)
routine ST B,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  [MAR] <- B : nz, v=0 ; return to fetch

# 0x1f ST B,(X)   (2 cyc)
.opcode page0 0x1f ST B,(X)
routine ST B,(X):
  MAR  <- X
  [MAR] <- B : nz, v=0 ; return to fetch

# 0x20 ST B,(X+n8)   (4 cyc)
.opcode page0 0x20 ST B,(X+n8)
routine ST B,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  [MAR] <- B : nz, v=0 ; return to fetch

# 0x21 ST B,(X+)   (2 cyc)
.opcode page0 0x21 ST B,(X+)
routine ST B,(X+):
  MAR  <- X
  [MAR] <- B ; X++ : nz, v=0 ; return to fetch

# 0x22 ST B,($nnnn)   (4 cyc)
.opcode page0 0x22 ST B,($nnnn)
routine ST B,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  [MAR] <- B : nz, v=0 ; return to fetch

# 0x23 ST B,(Y)   (2 cyc)
.opcode page0 0x23 ST B,(Y)
routine ST B,(Y):
  MAR  <- Y
  [MAR] <- B : nz, v=0 ; return to fetch

# 0x24 ST B,(Y+n8)   (4 cyc)
.opcode page0 0x24 ST B,(Y+n8)
routine ST B,(Y+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- Y + SCR1
  [MAR] <- B : nz, v=0 ; return to fetch

# 0x25 ST B,(Y+)   (2 cyc)
.opcode page0 0x25 ST B,(Y+)
routine ST B,(Y+):
  MAR  <- Y
  [MAR] <- B ; Y++ : nz, v=0 ; return to fetch

# ===========================================================================
# PAGE 0 · 16-bit load/store (D, X, Y, SP)
# ===========================================================================
# 0x26 LD D,$nnnn   (2 cyc)
.opcode page0 0x26 LD D,$nnnn
routine LD D,$nnnn:
  D.low  <- [PC]; PC++ : z
  D.high <- [PC]; PC++ : nz, v=0, z+ ; return to fetch

# 0x27 LD X,$nnnn   (3 cyc)
.opcode page0 0x27 LD X,$nnnn
routine LD X,$nnnn:
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  X <- SCR1 : nz, v=0 ; return to fetch

# 0x28 LD Y,$nnnn   (3 cyc)
.opcode page0 0x28 LD Y,$nnnn
routine LD Y,$nnnn:
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  Y <- SCR1 : nz, v=0 ; return to fetch

# 0x29 LD SP,$nnnn   (3 cyc)
.opcode page0 0x29 LD SP,$nnnn
routine LD SP,$nnnn:
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  SP <- SCR1 : nz, v=0 ; return to fetch

# 0x2a LD D,($nnnn)   (5 cyc)
.opcode page0 0x2a LD D,($nnnn)
routine LD D,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  D.low  <- [MAR]; MAR++ : z
  D.high <- [MAR]; MAR++ : nz, v=0, z+ ; return to fetch

# 0x2b LD X,($nnnn)   (6 cyc)
.opcode page0 0x2b LD X,($nnnn)
routine LD X,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  X <- SCR1 : nz, v=0 ; return to fetch

# 0x2c LD Y,($nnnn)   (6 cyc)
.opcode page0 0x2c LD Y,($nnnn)
routine LD Y,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  Y <- SCR1 : nz, v=0 ; return to fetch

# 0x2d ST D,($nnnn)   (5 cyc)
.opcode page0 0x2d ST D,($nnnn)
routine ST D,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  [MAR] <- low(D); MAR++ : z
  [MAR] <- high(D); MAR++ : nz, v=0, z+ ; return to fetch

# 0x2e ST X,($nnnn)   (5 cyc)
.opcode page0 0x2e ST X,($nnnn)
routine ST X,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  [MAR] <- low(X); MAR++ : z
  [MAR] <- high(X); MAR++ : nz, v=0, z+ ; return to fetch

# 0x2f ST Y,($nnnn)   (5 cyc)
.opcode page0 0x2f ST Y,($nnnn)
routine ST Y,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  [MAR] <- low(Y); MAR++ : z
  [MAR] <- high(Y); MAR++ : nz, v=0, z+ ; return to fetch

# 0x30 LD D,(X)   (3 cyc)
.opcode page0 0x30 LD D,(X)
routine LD D,(X):
  MAR  <- X
  D.low  <- [MAR]; MAR++ : z
  D.high <- [MAR]; MAR++ : nz, v=0, z+ ; return to fetch

# 0x31 ST D,(X)   (3 cyc)
.opcode page0 0x31 ST D,(X)
routine ST D,(X):
  MAR  <- X
  [MAR] <- low(D); MAR++ : z
  [MAR] <- high(D); MAR++ : nz, v=0, z+ ; return to fetch

# 0x32 LD D,(X+n8)   (5 cyc)
.opcode page0 0x32 LD D,(X+n8)
routine LD D,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  D.low  <- [MAR]; MAR++ : z
  D.high <- [MAR]; MAR++ : nz, v=0, z+ ; return to fetch

# 0x33 ST D,(X+n8)   (5 cyc)
.opcode page0 0x33 ST D,(X+n8)
routine ST D,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  [MAR] <- low(D); MAR++ : z
  [MAR] <- high(D); MAR++ : nz, v=0, z+ ; return to fetch

# 0x34 LD D,(X++)   (4 cyc)
.opcode page0 0x34 LD D,(X++)
routine LD D,(X++):
  MAR  <- X
  D.low  <- [MAR]; MAR++ : z
  D.high <- [MAR]; MAR++ : nz, v=0, z+
  X <- MAR ; return to fetch

# 0x35 ST D,(X++)   (4 cyc)
.opcode page0 0x35 ST D,(X++)
routine ST D,(X++):
  MAR  <- X
  [MAR] <- low(D); MAR++ : z
  [MAR] <- high(D); MAR++ : nz, v=0, z+
  X <- MAR ; return to fetch

# 0x36 LD D,(SP+n8)   (5 cyc)
.opcode page0 0x36 LD D,(SP+n8)
routine LD D,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  D.low  <- [MAR]; MAR++ : z
  D.high <- [MAR]; MAR++ : nz, v=0, z+ ; return to fetch

# 0x37 LD X,(SP+n8)   (6 cyc)
.opcode page0 0x37 LD X,(SP+n8)
routine LD X,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  X <- SCR1 : nz, v=0 ; return to fetch

# 0x38 LD Y,(SP+n8)   (6 cyc)
.opcode page0 0x38 LD Y,(SP+n8)
routine LD Y,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  Y <- SCR1 : nz, v=0 ; return to fetch

# 0x39 ST D,(SP+n8)   (5 cyc)
.opcode page0 0x39 ST D,(SP+n8)
routine ST D,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  [MAR] <- low(D); MAR++ : z
  [MAR] <- high(D); MAR++ : nz, v=0, z+ ; return to fetch

# 0x3a ST X,(SP+n8)   (5 cyc)
.opcode page0 0x3a ST X,(SP+n8)
routine ST X,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  [MAR] <- low(X); MAR++ : z
  [MAR] <- high(X); MAR++ : nz, v=0, z+ ; return to fetch

# 0x3b ST Y,(SP+n8)   (5 cyc)
.opcode page0 0x3b ST Y,(SP+n8)
routine ST Y,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  [MAR] <- low(Y); MAR++ : z
  [MAR] <- high(Y); MAR++ : nz, v=0, z+ ; return to fetch

# 0x3c LD D,(X+D)   (4 cyc)
.opcode page0 0x3c LD D,(X+D)
routine LD D,(X+D):
  SCR1 <- D
  MAR  <- X + SCR1
  D.low  <- [MAR]; MAR++ : z
  D.high <- [MAR]; MAR++ : nz, v=0, z+ ; return to fetch

# 0x3d ST D,(X+D)   (4 cyc)
.opcode page0 0x3d ST D,(X+D)
routine ST D,(X+D):
  SCR1 <- D
  MAR  <- X + SCR1
  [MAR] <- low(D); MAR++ : z
  [MAR] <- high(D); MAR++ : nz, v=0, z+ ; return to fetch

# 0x3e LD D,(Y)   (3 cyc)
.opcode page0 0x3e LD D,(Y)
routine LD D,(Y):
  MAR  <- Y
  D.low  <- [MAR]; MAR++ : z
  D.high <- [MAR]; MAR++ : nz, v=0, z+ ; return to fetch

# 0x3f ST D,(Y)   (3 cyc)
.opcode page0 0x3f ST D,(Y)
routine ST D,(Y):
  MAR  <- Y
  [MAR] <- low(D); MAR++ : z
  [MAR] <- high(D); MAR++ : nz, v=0, z+ ; return to fetch

# 0x40 LD D,(Y+n8)   (5 cyc)
.opcode page0 0x40 LD D,(Y+n8)
routine LD D,(Y+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- Y + SCR1
  D.low  <- [MAR]; MAR++ : z
  D.high <- [MAR]; MAR++ : nz, v=0, z+ ; return to fetch

# 0x41 ST D,(Y+n8)   (5 cyc)
.opcode page0 0x41 ST D,(Y+n8)
routine ST D,(Y+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- Y + SCR1
  [MAR] <- low(D); MAR++ : z
  [MAR] <- high(D); MAR++ : nz, v=0, z+ ; return to fetch

# ===========================================================================
# PAGE 0 · Byte ALU (ADD/SUB/CMP/AND/OR on A, B)
# ===========================================================================
# 0x42 ADD A,$nn   (2 cyc)
.opcode page0 0x42 ADD A,$nn
routine ADD A,$nn:
  SCR1 <- [PC]; PC++
  A <- A + SCR1 : nzvch ; return to fetch

# 0x43 ADD A,(X)   (3 cyc)
.opcode page0 0x43 ADD A,(X)
routine ADD A,(X):
  MAR  <- X
  SCR1 <- [MAR]
  A <- A + SCR1 : nzvch ; return to fetch

# 0x44 ADD A,(X+n8)   (5 cyc)
.opcode page0 0x44 ADD A,(X+n8)
routine ADD A,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  A <- A + SCR1 : nzvch ; return to fetch

# 0x45 ADD A,(X+D)   (4 cyc)
.opcode page0 0x45 ADD A,(X+D)
routine ADD A,(X+D):
  SCR1 <- D
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  A <- A + SCR1 : nzvch ; return to fetch

# 0x46 ADD A,(SP+n8)   (5 cyc)
.opcode page0 0x46 ADD A,(SP+n8)
routine ADD A,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1 <- [MAR]
  A <- A + SCR1 : nzvch ; return to fetch

# 0x47 ADD A,($nnnn)   (5 cyc)
.opcode page0 0x47 ADD A,($nnnn)
routine ADD A,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  A <- A + SCR1 : nzvch ; return to fetch

# 0x48 ADD A,(X+)   (3 cyc)
.opcode page0 0x48 ADD A,(X+)
routine ADD A,(X+):
  MAR  <- X
  SCR1 <- [MAR] ; X++
  A <- A + SCR1 : nzvch ; return to fetch

# 0x49 ADD A,(Y)   (3 cyc)
.opcode page0 0x49 ADD A,(Y)
routine ADD A,(Y):
  MAR  <- Y
  SCR1 <- [MAR]
  A <- A + SCR1 : nzvch ; return to fetch

# 0x4a ADD B,$nn   (2 cyc)
.opcode page0 0x4a ADD B,$nn
routine ADD B,$nn:
  SCR1 <- [PC]; PC++
  B <- B + SCR1 : nzvch ; return to fetch

# 0x4b ADD B,(X)   (3 cyc)
.opcode page0 0x4b ADD B,(X)
routine ADD B,(X):
  MAR  <- X
  SCR1 <- [MAR]
  B <- B + SCR1 : nzvch ; return to fetch

# 0x4c ADD B,(X+n8)   (5 cyc)
.opcode page0 0x4c ADD B,(X+n8)
routine ADD B,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  B <- B + SCR1 : nzvch ; return to fetch

# 0x4d ADD B,(X+D)   (4 cyc)
.opcode page0 0x4d ADD B,(X+D)
routine ADD B,(X+D):
  SCR1 <- D
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  B <- B + SCR1 : nzvch ; return to fetch

# 0x4e ADD B,(SP+n8)   (5 cyc)
.opcode page0 0x4e ADD B,(SP+n8)
routine ADD B,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1 <- [MAR]
  B <- B + SCR1 : nzvch ; return to fetch

# 0x4f ADD B,($nnnn)   (5 cyc)
.opcode page0 0x4f ADD B,($nnnn)
routine ADD B,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  B <- B + SCR1 : nzvch ; return to fetch

# 0x50 ADD B,(X+)   (3 cyc)
.opcode page0 0x50 ADD B,(X+)
routine ADD B,(X+):
  MAR  <- X
  SCR1 <- [MAR] ; X++
  B <- B + SCR1 : nzvch ; return to fetch

# 0x51 ADD B,(Y)   (3 cyc)
.opcode page0 0x51 ADD B,(Y)
routine ADD B,(Y):
  MAR  <- Y
  SCR1 <- [MAR]
  B <- B + SCR1 : nzvch ; return to fetch

# 0x52 SUB A,$nn   (2 cyc)
.opcode page0 0x52 SUB A,$nn
routine SUB A,$nn:
  SCR1 <- [PC]; PC++
  A <- A - SCR1 : nzvc ; return to fetch

# 0x53 SUB A,(X)   (3 cyc)
.opcode page0 0x53 SUB A,(X)
routine SUB A,(X):
  MAR  <- X
  SCR1 <- [MAR]
  A <- A - SCR1 : nzvc ; return to fetch

# 0x54 SUB A,(X+n8)   (5 cyc)
.opcode page0 0x54 SUB A,(X+n8)
routine SUB A,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  A <- A - SCR1 : nzvc ; return to fetch

# 0x55 SUB A,(X+D)   (4 cyc)
.opcode page0 0x55 SUB A,(X+D)
routine SUB A,(X+D):
  SCR1 <- D
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  A <- A - SCR1 : nzvc ; return to fetch

# 0x56 SUB A,(SP+n8)   (5 cyc)
.opcode page0 0x56 SUB A,(SP+n8)
routine SUB A,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1 <- [MAR]
  A <- A - SCR1 : nzvc ; return to fetch

# 0x57 SUB A,($nnnn)   (5 cyc)
.opcode page0 0x57 SUB A,($nnnn)
routine SUB A,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  A <- A - SCR1 : nzvc ; return to fetch

# 0x58 SUB A,(X+)   (3 cyc)
.opcode page0 0x58 SUB A,(X+)
routine SUB A,(X+):
  MAR  <- X
  SCR1 <- [MAR] ; X++
  A <- A - SCR1 : nzvc ; return to fetch

# 0x59 SUB A,(Y)   (3 cyc)
.opcode page0 0x59 SUB A,(Y)
routine SUB A,(Y):
  MAR  <- Y
  SCR1 <- [MAR]
  A <- A - SCR1 : nzvc ; return to fetch

# 0x5a SUB B,$nn   (2 cyc)
.opcode page0 0x5a SUB B,$nn
routine SUB B,$nn:
  SCR1 <- [PC]; PC++
  B <- B - SCR1 : nzvc ; return to fetch

# 0x5b SUB B,(X)   (3 cyc)
.opcode page0 0x5b SUB B,(X)
routine SUB B,(X):
  MAR  <- X
  SCR1 <- [MAR]
  B <- B - SCR1 : nzvc ; return to fetch

# 0x5c SUB B,(X+n8)   (5 cyc)
.opcode page0 0x5c SUB B,(X+n8)
routine SUB B,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  B <- B - SCR1 : nzvc ; return to fetch

# 0x5d SUB B,(X+D)   (4 cyc)
.opcode page0 0x5d SUB B,(X+D)
routine SUB B,(X+D):
  SCR1 <- D
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  B <- B - SCR1 : nzvc ; return to fetch

# 0x5e SUB B,(SP+n8)   (5 cyc)
.opcode page0 0x5e SUB B,(SP+n8)
routine SUB B,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1 <- [MAR]
  B <- B - SCR1 : nzvc ; return to fetch

# 0x5f SUB B,($nnnn)   (5 cyc)
.opcode page0 0x5f SUB B,($nnnn)
routine SUB B,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  B <- B - SCR1 : nzvc ; return to fetch

# 0x60 SUB B,(X+)   (3 cyc)
.opcode page0 0x60 SUB B,(X+)
routine SUB B,(X+):
  MAR  <- X
  SCR1 <- [MAR] ; X++
  B <- B - SCR1 : nzvc ; return to fetch

# 0x61 SUB B,(Y)   (3 cyc)
.opcode page0 0x61 SUB B,(Y)
routine SUB B,(Y):
  MAR  <- Y
  SCR1 <- [MAR]
  B <- B - SCR1 : nzvc ; return to fetch

# 0x62 CMP A,$nn   (2 cyc)
.opcode page0 0x62 CMP A,$nn
routine CMP A,$nn:
  SCR1 <- [PC]; PC++
  _ <- A - SCR1 : nzvc ; return to fetch

# 0x63 CMP A,(X)   (3 cyc)
.opcode page0 0x63 CMP A,(X)
routine CMP A,(X):
  MAR  <- X
  SCR1 <- [MAR]
  _ <- A - SCR1 : nzvc ; return to fetch

# 0x64 CMP A,(X+n8)   (5 cyc)
.opcode page0 0x64 CMP A,(X+n8)
routine CMP A,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  _ <- A - SCR1 : nzvc ; return to fetch

# 0x65 CMP A,(SP+n8)   (5 cyc)
.opcode page0 0x65 CMP A,(SP+n8)
routine CMP A,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1 <- [MAR]
  _ <- A - SCR1 : nzvc ; return to fetch

# 0x66 CMP A,($nnnn)   (5 cyc)
.opcode page0 0x66 CMP A,($nnnn)
routine CMP A,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  _ <- A - SCR1 : nzvc ; return to fetch

# 0x67 CMP A,(Y)   (3 cyc)
.opcode page0 0x67 CMP A,(Y)
routine CMP A,(Y):
  MAR  <- Y
  SCR1 <- [MAR]
  _ <- A - SCR1 : nzvc ; return to fetch

# 0x68 CMP B,$nn   (2 cyc)
.opcode page0 0x68 CMP B,$nn
routine CMP B,$nn:
  SCR1 <- [PC]; PC++
  _ <- B - SCR1 : nzvc ; return to fetch

# 0x69 CMP B,(X)   (3 cyc)
.opcode page0 0x69 CMP B,(X)
routine CMP B,(X):
  MAR  <- X
  SCR1 <- [MAR]
  _ <- B - SCR1 : nzvc ; return to fetch

# 0x6a CMP B,(X+n8)   (5 cyc)
.opcode page0 0x6a CMP B,(X+n8)
routine CMP B,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  _ <- B - SCR1 : nzvc ; return to fetch

# 0x6b CMP B,($nnnn)   (5 cyc)
.opcode page0 0x6b CMP B,($nnnn)
routine CMP B,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  _ <- B - SCR1 : nzvc ; return to fetch

# 0x6c CMP B,(Y)   (3 cyc)
.opcode page0 0x6c CMP B,(Y)
routine CMP B,(Y):
  MAR  <- Y
  SCR1 <- [MAR]
  _ <- B - SCR1 : nzvc ; return to fetch

# 0x6d AND A,$nn   (2 cyc)
.opcode page0 0x6d AND A,$nn
routine AND A,$nn:
  SCR1 <- [PC]; PC++
  A <- A & SCR1 : nz, v=0 ; return to fetch

# 0x6e AND A,(X)   (3 cyc)
.opcode page0 0x6e AND A,(X)
routine AND A,(X):
  MAR  <- X
  SCR1 <- [MAR]
  A <- A & SCR1 : nz, v=0 ; return to fetch

# 0x6f AND A,(X+n8)   (5 cyc)
.opcode page0 0x6f AND A,(X+n8)
routine AND A,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  A <- A & SCR1 : nz, v=0 ; return to fetch

# 0x70 AND A,($nnnn)   (5 cyc)
.opcode page0 0x70 AND A,($nnnn)
routine AND A,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  A <- A & SCR1 : nz, v=0 ; return to fetch

# 0x71 AND A,(X+)   (3 cyc)
.opcode page0 0x71 AND A,(X+)
routine AND A,(X+):
  MAR  <- X
  SCR1 <- [MAR] ; X++
  A <- A & SCR1 : nz, v=0 ; return to fetch

# 0x72 AND A,(Y)   (3 cyc)
.opcode page0 0x72 AND A,(Y)
routine AND A,(Y):
  MAR  <- Y
  SCR1 <- [MAR]
  A <- A & SCR1 : nz, v=0 ; return to fetch

# 0x73 AND B,$nn   (2 cyc)
.opcode page0 0x73 AND B,$nn
routine AND B,$nn:
  SCR1 <- [PC]; PC++
  B <- B & SCR1 : nz, v=0 ; return to fetch

# 0x74 AND B,(X)   (3 cyc)
.opcode page0 0x74 AND B,(X)
routine AND B,(X):
  MAR  <- X
  SCR1 <- [MAR]
  B <- B & SCR1 : nz, v=0 ; return to fetch

# 0x75 AND B,(X+n8)   (5 cyc)
.opcode page0 0x75 AND B,(X+n8)
routine AND B,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  B <- B & SCR1 : nz, v=0 ; return to fetch

# 0x76 AND B,($nnnn)   (5 cyc)
.opcode page0 0x76 AND B,($nnnn)
routine AND B,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  B <- B & SCR1 : nz, v=0 ; return to fetch

# 0x77 AND B,(X+)   (3 cyc)
.opcode page0 0x77 AND B,(X+)
routine AND B,(X+):
  MAR  <- X
  SCR1 <- [MAR] ; X++
  B <- B & SCR1 : nz, v=0 ; return to fetch

# 0x78 AND B,(Y)   (3 cyc)
.opcode page0 0x78 AND B,(Y)
routine AND B,(Y):
  MAR  <- Y
  SCR1 <- [MAR]
  B <- B & SCR1 : nz, v=0 ; return to fetch

# 0x79 OR A,$nn   (2 cyc)
.opcode page0 0x79 OR A,$nn
routine OR A,$nn:
  SCR1 <- [PC]; PC++
  A <- A | SCR1 : nz, v=0 ; return to fetch

# 0x7a OR A,(X)   (3 cyc)
.opcode page0 0x7a OR A,(X)
routine OR A,(X):
  MAR  <- X
  SCR1 <- [MAR]
  A <- A | SCR1 : nz, v=0 ; return to fetch

# 0x7b OR A,(X+n8)   (5 cyc)
.opcode page0 0x7b OR A,(X+n8)
routine OR A,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  A <- A | SCR1 : nz, v=0 ; return to fetch

# 0x7c OR A,($nnnn)   (5 cyc)
.opcode page0 0x7c OR A,($nnnn)
routine OR A,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  A <- A | SCR1 : nz, v=0 ; return to fetch

# 0x7d OR A,(X+)   (3 cyc)
.opcode page0 0x7d OR A,(X+)
routine OR A,(X+):
  MAR  <- X
  SCR1 <- [MAR] ; X++
  A <- A | SCR1 : nz, v=0 ; return to fetch

# 0x7e OR A,(Y)   (3 cyc)
.opcode page0 0x7e OR A,(Y)
routine OR A,(Y):
  MAR  <- Y
  SCR1 <- [MAR]
  A <- A | SCR1 : nz, v=0 ; return to fetch

# 0x7f OR B,$nn   (2 cyc)
.opcode page0 0x7f OR B,$nn
routine OR B,$nn:
  SCR1 <- [PC]; PC++
  B <- B | SCR1 : nz, v=0 ; return to fetch

# 0x81 OR B,(X)   (3 cyc)
.opcode page0 0x81 OR B,(X)
routine OR B,(X):
  MAR  <- X
  SCR1 <- [MAR]
  B <- B | SCR1 : nz, v=0 ; return to fetch

# 0x82 OR B,(X+n8)   (5 cyc)
.opcode page0 0x82 OR B,(X+n8)
routine OR B,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  B <- B | SCR1 : nz, v=0 ; return to fetch

# 0x83 OR B,($nnnn)   (5 cyc)
.opcode page0 0x83 OR B,($nnnn)
routine OR B,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  B <- B | SCR1 : nz, v=0 ; return to fetch

# 0x84 OR B,(X+)   (3 cyc)
.opcode page0 0x84 OR B,(X+)
routine OR B,(X+):
  MAR  <- X
  SCR1 <- [MAR] ; X++
  B <- B | SCR1 : nz, v=0 ; return to fetch

# 0x85 OR B,(Y)   (3 cyc)
.opcode page0 0x85 OR B,(Y)
routine OR B,(Y):
  MAR  <- Y
  SCR1 <- [MAR]
  B <- B | SCR1 : nz, v=0 ; return to fetch

# ===========================================================================
# PAGE 0 · 16-bit ALU, wide compare & D shifts
# ===========================================================================
# 0x86 ADD D,$nnnn   (3 cyc)
.opcode page0 0x86 ADD D,$nnnn
routine ADD D,$nnnn:
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  D <- D + SCR1 : nzvc ; return to fetch

# 0x87 ADD D,($nnnn)   (6 cyc)
.opcode page0 0x87 ADD D,($nnnn)
routine ADD D,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D + SCR1 : nzvc ; return to fetch

# 0x88 ADD D,(SP+n8)   (6 cyc)
.opcode page0 0x88 ADD D,(SP+n8)
routine ADD D,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D + SCR1 : nzvc ; return to fetch

# 0x89 ADD D,(X)   (4 cyc)
.opcode page0 0x89 ADD D,(X)
routine ADD D,(X):
  MAR  <- X
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D + SCR1 : nzvc ; return to fetch

# 0x8a ADD D,(X+n8)   (6 cyc)
.opcode page0 0x8a ADD D,(X+n8)
routine ADD D,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D + SCR1 : nzvc ; return to fetch

# 0x8b ADD D,(X+D)   (5 cyc)
.opcode page0 0x8b ADD D,(X+D)
routine ADD D,(X+D):
  SCR1 <- D
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D + SCR1 : nzvc ; return to fetch

# 0x8c SUB D,$nnnn   (3 cyc)
.opcode page0 0x8c SUB D,$nnnn
routine SUB D,$nnnn:
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  D <- D - SCR1 : nzvc ; return to fetch

# 0x8d SUB D,($nnnn)   (6 cyc)
.opcode page0 0x8d SUB D,($nnnn)
routine SUB D,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D - SCR1 : nzvc ; return to fetch

# 0x8e SUB D,(SP+n8)   (6 cyc)
.opcode page0 0x8e SUB D,(SP+n8)
routine SUB D,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D - SCR1 : nzvc ; return to fetch

# 0x8f CMP D,$nnnn   (3 cyc)
.opcode page0 0x8f CMP D,$nnnn
routine CMP D,$nnnn:
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  _ <- D - SCR1 : nzvc ; return to fetch

# 0x90 CMP D,($nnnn)   (6 cyc)
.opcode page0 0x90 CMP D,($nnnn)
routine CMP D,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  _ <- D - SCR1 : nzvc ; return to fetch

# 0x91 CMP D,(SP+n8)   (6 cyc)
.opcode page0 0x91 CMP D,(SP+n8)
routine CMP D,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  _ <- D - SCR1 : nzvc ; return to fetch

# 0x92 CMP X,$nnnn   (3 cyc)
.opcode page0 0x92 CMP X,$nnnn
routine CMP X,$nnnn:
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  _ <- X - SCR1 : nzvc ; return to fetch

# 0x93 CMP Y,$nnnn   (3 cyc)
.opcode page0 0x93 CMP Y,$nnnn
routine CMP Y,$nnnn:
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  _ <- Y - SCR1 : nzvc ; return to fetch

# 0x94 CMP SP,$nnnn   (3 cyc)
.opcode page0 0x94 CMP SP,$nnnn
routine CMP SP,$nnnn:
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  _ <- SP - SCR1 : nzvc ; return to fetch

# 0x95 ASL D,$n   (4 cyc)
.opcode page0 0x95 ASL D,$n
routine ASL D,$n:
  _ <- [PC]; PC++ : z ; count -> uloop   # shift count n (n==0 -> CC.Z); uloop <- ~n
  if z goto asld_done                        # n==0: zero-trip, leave D unchanged
asld_loop:
  D <- asl(D) : nzvc ; uloop-- ; if not uloop.zero goto asld_loop
asld_done:
  return to fetch

# 0x96 LSR D,$n   (4 cyc)
.opcode page0 0x96 LSR D,$n
routine LSR D,$n:
  _ <- [PC]; PC++ : z ; count -> uloop   # shift count n (n==0 -> CC.Z); uloop <- ~n
  if z goto lsrd_done                        # n==0: zero-trip, leave D unchanged
lsrd_loop:
  D <- lsr(D) : nzvc ; uloop-- ; if not uloop.zero goto lsrd_loop
lsrd_done:
  return to fetch

# 0x97 ASR D,$n   (4 cyc)
.opcode page0 0x97 ASR D,$n
routine ASR D,$n:
  _ <- [PC]; PC++ : z ; count -> uloop   # shift count n (n==0 -> CC.Z); uloop <- ~n
  if z goto asrd_done                        # n==0: zero-trip, leave D unchanged
asrd_loop:
  D <- asr(D) : nzvc ; uloop-- ; if not uloop.zero goto asrd_loop
asrd_done:
  return to fetch

# ===========================================================================
# PAGE 0 · RMW & register-direct unary
# ===========================================================================
# 0x98 INC A   (1 cyc)
.opcode page0 0x98 INC A
routine INC A:
  A <- A + 1 : nzv ; return to fetch

# 0x99 DEC A   (1 cyc)
.opcode page0 0x99 DEC A
routine DEC A:
  A <- A - 1 : nzv ; return to fetch

# 0x9a CLR A   (1 cyc)
.opcode page0 0x9a CLR A
routine CLR A:
  A <- 0 : nz, v=0, c=0 ; return to fetch

# 0x9b TST A   (1 cyc)
.opcode page0 0x9b TST A
routine TST A:
  _ <- A : nz, v=0 ; return to fetch

# 0x9c LSR A   (1 cyc)
.opcode page0 0x9c LSR A
routine LSR A:
  A <- lsr(A) : nzvc ; return to fetch

# 0x9d ASR A   (1 cyc)
.opcode page0 0x9d ASR A
routine ASR A:
  A <- asr(A) : nzvc ; return to fetch

# 0x9e ASL A   (1 cyc)
.opcode page0 0x9e ASL A
routine ASL A:
  A <- asl(A) : nzvc ; return to fetch

# 0x9f INC B   (1 cyc)
.opcode page0 0x9f INC B
routine INC B:
  B <- B + 1 : nzv ; return to fetch

# 0xa0 DEC B   (1 cyc)
.opcode page0 0xa0 DEC B
routine DEC B:
  B <- B - 1 : nzv ; return to fetch

# 0xa1 CLR B   (1 cyc)
.opcode page0 0xa1 CLR B
routine CLR B:
  B <- 0 : nz, v=0, c=0 ; return to fetch

# 0xa2 TST B   (1 cyc)
.opcode page0 0xa2 TST B
routine TST B:
  _ <- B : nz, v=0 ; return to fetch

# 0xa3 LSR B   (1 cyc)
.opcode page0 0xa3 LSR B
routine LSR B:
  B <- lsr(B) : nzvc ; return to fetch

# 0xa4 ASR B   (1 cyc)
.opcode page0 0xa4 ASR B
routine ASR B:
  B <- asr(B) : nzvc ; return to fetch

# 0xa5 ASL B   (1 cyc)
.opcode page0 0xa5 ASL B
routine ASL B:
  B <- asl(B) : nzvc ; return to fetch

# 0xa6 INC (X)   (4 cyc)
.opcode page0 0xa6 INC (X)
routine INC (X):
  MAR  <- X
  SCR1 <- [MAR]
  SCR1 <- SCR1 + 1 : nzv
  [MAR] <- SCR1 ; return to fetch

# 0xa7 INC (X+n8)   (6 cyc)
.opcode page0 0xa7 INC (X+n8)
routine INC (X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  SCR1 <- SCR1 + 1 : nzv
  [MAR] <- SCR1 ; return to fetch

# 0xa8 INC (SP+n8)   (6 cyc)
.opcode page0 0xa8 INC (SP+n8)
routine INC (SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1 <- [MAR]
  SCR1 <- SCR1 + 1 : nzv
  [MAR] <- SCR1 ; return to fetch

# 0xa9 DEC (X)   (4 cyc)
.opcode page0 0xa9 DEC (X)
routine DEC (X):
  MAR  <- X
  SCR1 <- [MAR]
  SCR1 <- SCR1 - 1 : nzv
  [MAR] <- SCR1 ; return to fetch

# 0xaa DEC (X+n8)   (6 cyc)
.opcode page0 0xaa DEC (X+n8)
routine DEC (X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  SCR1 <- SCR1 - 1 : nzv
  [MAR] <- SCR1 ; return to fetch

# 0xab DEC (SP+n8)   (6 cyc)
.opcode page0 0xab DEC (SP+n8)
routine DEC (SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1 <- [MAR]
  SCR1 <- SCR1 - 1 : nzv
  [MAR] <- SCR1 ; return to fetch

# 0xac CLR (X)   (3 cyc)
.opcode page0 0xac CLR (X)
routine CLR (X):
  MAR  <- X
  SCR1 <- 0
  [MAR] <- SCR1 : nz, v=0, c=0 ; return to fetch

# 0xad CLR (X+n8)   (5 cyc)
.opcode page0 0xad CLR (X+n8)
routine CLR (X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- 0
  [MAR] <- SCR1 : nz, v=0, c=0 ; return to fetch

# 0xae TST (X)   (2 cyc)
.opcode page0 0xae TST (X)
routine TST (X):
  MAR  <- X
  _ <- [MAR] : nz, v=0 ; return to fetch

# 0xaf TST (X+n8)   (4 cyc)
.opcode page0 0xaf TST (X+n8)
routine TST (X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  _ <- [MAR] : nz, v=0 ; return to fetch

# 0xb0 INC ($nnnn)   (6 cyc)
.opcode page0 0xb0 INC ($nnnn)
routine INC ($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  SCR1 <- SCR1 + 1 : nzv
  [MAR] <- SCR1 ; return to fetch

# 0xb1 DEC ($nnnn)   (6 cyc)
.opcode page0 0xb1 DEC ($nnnn)
routine DEC ($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  SCR1 <- SCR1 - 1 : nzv
  [MAR] <- SCR1 ; return to fetch

# ===========================================================================
# PAGE 0 · Control flow
# ===========================================================================
# 0xb2 BRA rel8   (3 cyc)
.opcode page0 0xb2 BRA rel8
routine BRA rel8:
  MDR  <- [PC]; PC++                # rel8 displacement
  SCR1 <- sext(MDR)
  PC <- PC + SCR1 ; return to fetch

# 0xb3 BRN rel8   (2 cyc)
.opcode page0 0xb3 BRN rel8
routine BRN rel8:
  MDR  <- [PC]; PC++                # rel8 displacement
  return to fetch

# 0xb4 BHI rel8   (3 cyc)
.opcode page0 0xb4 BHI rel8
routine BHI rel8:
  MDR  <- [PC]; PC++                # rel8 displacement
  SCR1 <- sext(MDR) ; if not c|z goto BR_TAKEN
  return to fetch

# 0xb5 BLS rel8   (3 cyc)
.opcode page0 0xb5 BLS rel8
routine BLS rel8:
  MDR  <- [PC]; PC++                # rel8 displacement
  SCR1 <- sext(MDR) ; if c|z goto BR_TAKEN
  return to fetch

# 0xb6 BCC rel8   (3 cyc)
.opcode page0 0xb6 BCC rel8
routine BCC rel8:
  MDR  <- [PC]; PC++                # rel8 displacement
  SCR1 <- sext(MDR) ; if not c goto BR_TAKEN
  return to fetch

# 0xb7 BCS rel8   (3 cyc)
.opcode page0 0xb7 BCS rel8
routine BCS rel8:
  MDR  <- [PC]; PC++                # rel8 displacement
  SCR1 <- sext(MDR) ; if c goto BR_TAKEN
  return to fetch

# 0xb8 BNE rel8   (3 cyc)
.opcode page0 0xb8 BNE rel8
routine BNE rel8:
  MDR  <- [PC]; PC++                # rel8 displacement
  SCR1 <- sext(MDR) ; if not z goto BR_TAKEN
  return to fetch

# 0xb9 BEQ rel8   (3 cyc)
.opcode page0 0xb9 BEQ rel8
routine BEQ rel8:
  MDR  <- [PC]; PC++                # rel8 displacement
  SCR1 <- sext(MDR) ; if z goto BR_TAKEN
  return to fetch

# 0xba BVC rel8   (3 cyc)
.opcode page0 0xba BVC rel8
routine BVC rel8:
  MDR  <- [PC]; PC++                # rel8 displacement
  SCR1 <- sext(MDR) ; if not v goto BR_TAKEN
  return to fetch

# 0xbb BVS rel8   (3 cyc)
.opcode page0 0xbb BVS rel8
routine BVS rel8:
  MDR  <- [PC]; PC++                # rel8 displacement
  SCR1 <- sext(MDR) ; if v goto BR_TAKEN
  return to fetch

# 0xbc BPL rel8   (3 cyc)
.opcode page0 0xbc BPL rel8
routine BPL rel8:
  MDR  <- [PC]; PC++                # rel8 displacement
  SCR1 <- sext(MDR) ; if not n goto BR_TAKEN
  return to fetch

# 0xbd BMI rel8   (3 cyc)
.opcode page0 0xbd BMI rel8
routine BMI rel8:
  MDR  <- [PC]; PC++                # rel8 displacement
  SCR1 <- sext(MDR) ; if n goto BR_TAKEN
  return to fetch

# 0xbe BGE rel8   (3 cyc)
.opcode page0 0xbe BGE rel8
routine BGE rel8:
  MDR  <- [PC]; PC++                # rel8 displacement
  SCR1 <- sext(MDR) ; if not n^v goto BR_TAKEN
  return to fetch

# 0xbf BLT rel8   (3 cyc)
.opcode page0 0xbf BLT rel8
routine BLT rel8:
  MDR  <- [PC]; PC++                # rel8 displacement
  SCR1 <- sext(MDR) ; if n^v goto BR_TAKEN
  return to fetch

# 0xc0 BGT rel8   (3 cyc)
.opcode page0 0xc0 BGT rel8
routine BGT rel8:
  MDR  <- [PC]; PC++                # rel8 displacement
  SCR1 <- sext(MDR) ; if not z|(n^v) goto BR_TAKEN
  return to fetch

# 0xc1 BLE rel8   (3 cyc)
.opcode page0 0xc1 BLE rel8
routine BLE rel8:
  MDR  <- [PC]; PC++                # rel8 displacement
  SCR1 <- sext(MDR) ; if z|(n^v) goto BR_TAKEN
  return to fetch

# 0xc2 BSR rel8   (6 cyc)
.opcode page0 0xc2 BSR rel8
routine BSR rel8:
  MDR  <- [PC]; PC++                # rel8; PC -> return address
  SCR1 <- sext(MDR)
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- PC + SCR1 ; return to fetch # take the call

# 0xc3 RTS   (5 cyc)
.opcode page0 0xc3 RTS
routine RTS:
  MAR  <- SP                         # frame top = return-addr low byte
  SCR1.low  <- [MAR]; MAR++          # pull return addr low
  SCR1.high <- [MAR]; MAR++          # pull return addr high
  SP   <- MAR                        # SP += 2
  PC   <- SCR1 ; return to fetch     # resume at the caller

# 0xc4 JMP $nnnn   (3 cyc)
.opcode page0 0xc4 JMP $nnnn
routine JMP $nnnn:
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  PC <- SCR1 ; return to fetch

# 0xc5 JMP X   (1 cyc)
.opcode page0 0xc5 JMP X
routine JMP X:
  PC <- X ; return to fetch

# 0xc6 JMP Y   (1 cyc)
.opcode page0 0xc6 JMP Y
routine JMP Y:
  PC <- Y ; return to fetch

# 0xc7 JMP (X)   (4 cyc)
.opcode page0 0xc7 JMP (X)
routine JMP (X):
  MAR  <- X
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  PC <- SCR1 ; return to fetch

# 0xc8 JMP (X+n8)   (6 cyc)
.opcode page0 0xc8 JMP (X+n8)
routine JMP (X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  PC <- SCR1 ; return to fetch

# 0xc9 JMP (X+D)   (5 cyc)
.opcode page0 0xc9 JMP (X+D)
routine JMP (X+D):
  SCR1 <- D
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  PC <- SCR1 ; return to fetch

# 0xca JSR $nnnn   (6 cyc)
.opcode page0 0xca JSR $nnnn
routine JSR $nnnn:
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- SCR1 ; return to fetch

# 0xcb JSR (X)   (7 cyc)
.opcode page0 0xcb JSR (X)
routine JSR (X):
  MAR  <- X
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- SCR1 ; return to fetch

# 0xcc JSR Y   (4 cyc)
.opcode page0 0xcc JSR Y
routine JSR Y:
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- Y ; return to fetch

# 0xcd JSR X   (4 cyc)
.opcode page0 0xcd JSR X
routine JSR X:
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- X ; return to fetch

# 0xce JSR (X+n8)   (9 cyc)
.opcode page0 0xce JSR (X+n8)
routine JSR (X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- SCR1 ; return to fetch

# 0xcf JSR (X+D)   (8 cyc)
.opcode page0 0xcf JSR (X+D)
routine JSR (X+D):
  SCR1 <- D
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- SCR1 ; return to fetch

# ===========================================================================
# PAGE 0 · System / inherent / LEA / moves
# ===========================================================================
# 0xd0 NOP   (1 cyc)
.opcode page0 0xd0 NOP
routine NOP:
  return to fetch

# 0xd1 SEX   (1 cyc)
.opcode page0 0xd1 SEX
routine SEX:
  D <- sext(B) : nz, v=0 ; return to fetch    # sign-extend B into A:B

# 0xd2 MUL   (13 cyc · REVIEW)
.opcode page0 0xd2 MUL
routine MUL:
  # unsigned 8x8 -> 16: A*B -> D.  shift-add over the uloop counter.
  # Stage the loop count 8 on Z first (the const-gen tops out at +2), load uloop, then reuse
  # SCR2 for the multiplier — uloop must latch the count from Z in the LOAD word itself.
  SCR2 <- +2                         # 2
  SCR2 <- SCR2 + SCR2                # 4
  SCR2 <- SCR2 + SCR2 ; count -> uloop   # 8 on Z -> uloop <- ~8 (8 iterations)
  SCR1 <- high(D)                    # multiplicand A (zero-extended to 16)
  SCR2 <- low(D)                     # multiplier   B (reuse SCR2)
  D <- 0                             # clear the running product
mul_loop:
  SCR2 <- lsr(SCR2) : c              # next multiplier bit -> C
  if not c goto mul_noadd
  D <- D + SCR1                      # add the (shifted) multiplicand
mul_noadd:
  SCR1 <- asl(SCR1)                  # multiplicand <<= 1
  uloop-- ; if not uloop.zero goto mul_loop
  _ <- D : z                         # Z from the 16-bit product  (REVIEW: MUL also sets C)
  return to fetch

# 0xd3 ABX   (2 cyc)
.opcode page0 0xd3 ABX
routine ABX:
  SCR1 <- low(D)                     # zero-extend B (D low byte)
  X <- X + SCR1 ; return to fetch    # X += B  (unsigned)

# 0xd4 PSHS mask8   (35 cyc)
.opcode page0 0xd4 PSHS mask8
routine PSHS mask8:
  SCR2 <- [PC]; PC++                # push mask
  SCR2 <- asl(SCR2) : c             # shift next mask bit (msb-first) into C
  if not c goto pshs_skip0             # PC not in mask
  SP <- SP - 2 ; MAR <- SP - 2
  [MAR] <- low(PC); MAR++
  [MAR] <- high(PC)
pshs_skip0:
  SCR2 <- asl(SCR2) : c             # shift next mask bit (msb-first) into C
  if not c goto pshs_skip1             # SP not in mask
  SP <- SP - 2 ; MAR <- SP - 2
  [MAR] <- low(SP); MAR++
  [MAR] <- high(SP)
pshs_skip1:
  SCR2 <- asl(SCR2) : c             # shift next mask bit (msb-first) into C
  if not c goto pshs_skip2             # Y not in mask
  SP <- SP - 2 ; MAR <- SP - 2
  [MAR] <- low(Y); MAR++
  [MAR] <- high(Y)
pshs_skip2:
  SCR2 <- asl(SCR2) : c             # shift next mask bit (msb-first) into C
  if not c goto pshs_skip3             # X not in mask
  SP <- SP - 2 ; MAR <- SP - 2
  [MAR] <- low(X); MAR++
  [MAR] <- high(X)
pshs_skip3:
  SCR2 <- asl(SCR2) : c             # shift next mask bit (msb-first) into C
  SCR2 <- asl(SCR2) : c             # shift next mask bit (msb-first) into C
  if not c goto pshs_skip5             # B not in mask
  SP <- SP - 1 ; MAR <- SP - 1
  [MAR] <- B
pshs_skip5:
  SCR2 <- asl(SCR2) : c             # shift next mask bit (msb-first) into C
  if not c goto pshs_skip6             # A not in mask
  SP <- SP - 1 ; MAR <- SP - 1
  [MAR] <- A
pshs_skip6:
  SCR2 <- asl(SCR2) : c             # shift next mask bit (msb-first) into C
  if not c goto pshs_skip7             # CC not in mask
  SP <- SP - 1 ; MAR <- SP - 1
  [MAR] <- CC
pshs_skip7:
  return to fetch

# 0xd5 PULS mask8   (34 cyc)
.opcode page0 0xd5 PULS mask8
routine PULS mask8:
  SCR2 <- [PC]; PC++                # pull mask
  MAR <- SP                          # walk the frame upward from SP
  SCR2 <- lsr(SCR2) : c             # shift next mask bit (lsb-first) into C
  if not c goto puls_skip0             # CC not in mask
  CC <- [MAR]; MAR++ ; cc(whole)    # restore CC (M/I priv-gated)
puls_skip0:
  SCR2 <- lsr(SCR2) : c             # shift next mask bit (lsb-first) into C
  if not c goto puls_skip1             # A not in mask
  A <- [MAR]; MAR++
puls_skip1:
  SCR2 <- lsr(SCR2) : c             # shift next mask bit (lsb-first) into C
  if not c goto puls_skip2             # B not in mask
  B <- [MAR]; MAR++
puls_skip2:
  SCR2 <- lsr(SCR2) : c             # shift next mask bit (lsb-first) into C
  SCR2 <- lsr(SCR2) : c             # shift next mask bit (lsb-first) into C
  if not c goto puls_skip4             # X not in mask
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  X <- SCR1
puls_skip4:
  SCR2 <- lsr(SCR2) : c             # shift next mask bit (lsb-first) into C
  if not c goto puls_skip5             # Y not in mask
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  Y <- SCR1
puls_skip5:
  SCR2 <- lsr(SCR2) : c             # shift next mask bit (lsb-first) into C
  if not c goto puls_skip6             # SP not in mask
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  SP <- SCR1
puls_skip6:
  SCR2 <- lsr(SCR2) : c             # shift next mask bit (lsb-first) into C
  if not c goto puls_skip7             # PC not in mask
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  SP <- MAR                          # commit SP (LEFT = MAR)
  PC <- SCR1 ; return to fetch       # then set PC (LEFT = SCR1)
puls_skip7:
  SP <- MAR ; return to fetch        # commit the advanced SP

# 0xd6 ANDCC $nn   (2 cyc)
.opcode page0 0xd6 ANDCC $nn
routine ANDCC $nn:
  SCR1 <- [PC]; PC++                # AND-mask
  _ <- SCR1 ; cc(and) ; return to fetch    # CC <- CC & mask (M/I priv-gated)

# 0xd7 ORCC $nn   (2 cyc)
.opcode page0 0xd7 ORCC $nn
routine ORCC $nn:
  SCR1 <- [PC]; PC++                # OR-mask
  _ <- SCR1 ; cc(or) ; return to fetch     # CC <- CC | mask (M/I priv-gated)

# 0xd8 LD reg,reg   (2 cyc)
.opcode page0 0xd8 LD reg,reg
routine LD reg,reg:
  SCR2 <- [PC]; PC++                # src|dst register-select byte
  # the selector nibbles drive the register-file read/write ports
  # (a datapath mux fed by SCR2, not a control-word field):
  reg[dst] <- reg[src] ; return to fetch

# 0xd9 XCHG reg,reg   (4 cyc)
.opcode page0 0xd9 XCHG reg,reg
routine XCHG reg,reg:
  SCR2 <- [PC]; PC++                # the two register-select nibbles
  SCR1 <- reg[dst]                  # selector-driven (see LD reg,reg)
  reg[dst] <- reg[src]
  reg[src] <- SCR1 ; return to fetch

# 0xda TAS (X)   (5 cyc)
.opcode page0 0xda TAS (X)
routine TAS (X):
  MAR  <- X
  SCR1 <- [MAR] : nz, v=0 ; lock    # test: read the lock byte, hold the bus
  SCR2 <- 0
  SCR2 <- ~SCR2                     # the set value (all-ones)
  [MAR] <- SCR2 ; unlock ; return to fetch   # set: store, release the bus lock

# 0xdb TAS (X+n8)   (7 cyc)
.opcode page0 0xdb TAS (X+n8)
routine TAS (X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR] : nz, v=0 ; lock    # test: read the lock byte, hold the bus
  SCR2 <- 0
  SCR2 <- ~SCR2                     # the set value (all-ones)
  [MAR] <- SCR2 ; unlock ; return to fetch   # set: store, release the bus lock

# 0xdc LEA X,X+n8   (3 cyc)
.opcode page0 0xdc LEA X,X+n8
routine LEA X,X+n8:
  MDR  <- [PC]; PC++                # 8-bit displacement
  SCR1 <- sext(MDR)
  X <- X + SCR1 : z ; return to fetch

# 0xdd LEA X,X+A   (2 cyc)
.opcode page0 0xdd LEA X,X+A
routine LEA X,X+A:
  SCR1 <- sext(A)
  X <- X + SCR1 : z ; return to fetch

# 0xde LEA X,X+B   (2 cyc)
.opcode page0 0xde LEA X,X+B
routine LEA X,X+B:
  SCR1 <- sext(B)
  X <- X + SCR1 : z ; return to fetch

# 0xdf LEA X,X+D   (2 cyc)
.opcode page0 0xdf LEA X,X+D
routine LEA X,X+D:
  SCR1 <- D
  X <- X + SCR1 : z ; return to fetch

# 0xe0 LEA X,X+   (1 cyc)
.opcode page0 0xe0 LEA X,X+
routine LEA X,X+:
  X <- X + 1 : z ; return to fetch

# 0xe1 LEA X,X++   (1 cyc)
.opcode page0 0xe1 LEA X,X++
routine LEA X,X++:
  X <- X + 2 : z ; return to fetch

# 0xe2 LEA X,-X   (1 cyc)
.opcode page0 0xe2 LEA X,-X
routine LEA X,-X:
  X <- X - 1 : z ; return to fetch

# 0xe3 LEA X,Y+n8   (3 cyc)
.opcode page0 0xe3 LEA X,Y+n8
routine LEA X,Y+n8:
  MDR  <- [PC]; PC++                # 8-bit displacement
  SCR1 <- sext(MDR)
  X <- Y + SCR1 : z ; return to fetch

# 0xe4 LEA X,SP+n8   (3 cyc)
.opcode page0 0xe4 LEA X,SP+n8
routine LEA X,SP+n8:
  MDR  <- [PC]; PC++                # 8-bit displacement
  SCR1 <- sext(MDR)
  X <- SP + SCR1 : z ; return to fetch

# 0xe5 LEA Y,Y+n8   (3 cyc)
.opcode page0 0xe5 LEA Y,Y+n8
routine LEA Y,Y+n8:
  MDR  <- [PC]; PC++                # 8-bit displacement
  SCR1 <- sext(MDR)
  Y <- Y + SCR1 : z ; return to fetch

# 0xe6 LEA Y,SP+n8   (3 cyc)
.opcode page0 0xe6 LEA Y,SP+n8
routine LEA Y,SP+n8:
  MDR  <- [PC]; PC++                # 8-bit displacement
  SCR1 <- sext(MDR)
  Y <- SP + SCR1 : z ; return to fetch

# 0xe7 LEA SP,SP+n8   (3 cyc)
.opcode page0 0xe7 LEA SP,SP+n8
routine LEA SP,SP+n8:
  MDR  <- [PC]; PC++                # 8-bit displacement
  SCR1 <- sext(MDR)
  SP <- SP + SCR1 ; return to fetch

# 0xe8 LEA SP,X+n8   (3 cyc)
.opcode page0 0xe8 LEA SP,X+n8
routine LEA SP,X+n8:
  MDR  <- [PC]; PC++                # 8-bit displacement
  SCR1 <- sext(MDR)
  SP <- X + SCR1 ; return to fetch

# ===========================================================================
# PAGE 1 · System / privileged / cold TAS & LEA
# ===========================================================================
# 0x00 DAA   (2 cyc · REVIEW)
.opcode page1 0x00 DAA
routine DAA:
  # decimal-adjust A after a BCD add.  REVIEW: full conditional +$06/+$60
  # correction on the H flag and the two nibble ranges needs simulation.
  SCR1 <- A
  A <- A + SCR1 : nzvc ; return to fetch

# 0x01 SYNC   (2 cyc · privileged)
.opcode page1 0x01 SYNC
routine SYNC:
sync_wait:
  if not irq goto sync_wait          # privileged: spin until an interrupt is pending
  return to fetch

# 0x02 RTI   (6 cyc · privileged)
.opcode page1 0x02 RTI
routine RTI:
  MAR <- SP                                       # supervisor frame: CC on top
  CC  <- [MAR]; MAR++ ; cc(whole)                 # restore CC (incl. M, I — supervisor, so priv-gated load takes)
  SCR1.low  <- [MAR]; MAR++                       # pull PC low
  SCR1.high <- [MAR]; MAR++                       # pull PC high
  SP  <- MAR                                      # SP += 3
  PC  <- SCR1 ; return to fetch                   # resume interrupted context

# 0x03 SWI   (10 cyc)
.opcode page1 0x03 SWI
routine SWI:
  SSP <- SSP - 2 ; MAR <- SSP - 2 ; map(kernel)   # reserve 2 bytes for PC on the supervisor stack
  [MAR] <- low(PC); MAR++ ; map(kernel)           # push return PC low
  [MAR] <- high(PC) ; map(kernel)                 # push return PC high
  SSP <- SSP - 1 ; MAR <- SSP - 1 ; map(kernel)   # reserve 1 byte for CC (top of frame)
  [MAR] <- CC ; map(kernel)                       # push interrupted CC
  mi(enter)                                       # enter supervisor mode, set I
  MAR <- vector(SWI) ; map(kernel)             # hardwired SWI vector slot
  SCR1.low  <- [MAR]; MAR++ ; map(kernel)         # handler address low
  SCR1.high <- [MAR] ; map(kernel)                # handler address high
  PC <- SCR1 ; return to fetch                    # enter the handler

# 0x04 SWI2   (10 cyc)
.opcode page1 0x04 SWI2
routine SWI2:
  SSP <- SSP - 2 ; MAR <- SSP - 2 ; map(kernel)   # reserve 2 bytes for PC on the supervisor stack
  [MAR] <- low(PC); MAR++ ; map(kernel)           # push return PC low
  [MAR] <- high(PC) ; map(kernel)                 # push return PC high
  SSP <- SSP - 1 ; MAR <- SSP - 1 ; map(kernel)   # reserve 1 byte for CC (top of frame)
  [MAR] <- CC ; map(kernel)                       # push interrupted CC
  mi(enter)                                       # enter supervisor mode, set I
  MAR <- vector(SWI2) ; map(kernel)             # hardwired SWI2 vector slot
  SCR1.low  <- [MAR]; MAR++ ; map(kernel)         # handler address low
  SCR1.high <- [MAR] ; map(kernel)                # handler address high
  PC <- SCR1 ; return to fetch                    # enter the handler

# 0x05 SWI3   (10 cyc)
.opcode page1 0x05 SWI3
routine SWI3:
  SSP <- SSP - 2 ; MAR <- SSP - 2 ; map(kernel)   # reserve 2 bytes for PC on the supervisor stack
  [MAR] <- low(PC); MAR++ ; map(kernel)           # push return PC low
  [MAR] <- high(PC) ; map(kernel)                 # push return PC high
  SSP <- SSP - 1 ; MAR <- SSP - 1 ; map(kernel)   # reserve 1 byte for CC (top of frame)
  [MAR] <- CC ; map(kernel)                       # push interrupted CC
  mi(enter)                                       # enter supervisor mode, set I
  MAR <- vector(SWI3) ; map(kernel)             # hardwired SWI3 vector slot
  SCR1.low  <- [MAR]; MAR++ ; map(kernel)         # handler address low
  SCR1.high <- [MAR] ; map(kernel)                # handler address high
  PC <- SCR1 ; return to fetch                    # enter the handler

# 0x06 CWAI $nn   (4 cyc · REVIEW)
.opcode page1 0x06 CWAI $nn
routine CWAI $nn:
  SCR1 <- [PC]; PC++                # AND-mask
  _ <- SCR1 ; cc(and)              # CC <- CC & mask (M/I priv-gated)
cwai_wait:
  if not irq goto cwai_wait         # wait for an interrupt (REVIEW: CWAI should pre-stack the full register frame for a fast interruptible entry)
  return to fetch

# 0x07 SEI   (1 cyc · privileged)
.opcode page1 0x07 SEI
routine SEI:
  mi(set_i) ; return to fetch       # privileged: set the IRQ mask

# 0x08 CLI   (1 cyc · privileged)
.opcode page1 0x08 CLI
routine CLI:
  mi(clr_i) ; return to fetch       # privileged: clear the IRQ mask

# 0x09 HALT   (1 cyc · privileged)
.opcode page1 0x09 HALT
routine HALT:
halt_spin:
  goto halt_spin                     # privileged: stop until RESET

# 0x0a LDMMU $nn   (2 cyc · privileged · REVIEW)
.opcode page1 0x0a LDMMU $nn
routine LDMMU $nn:
  SCR1 <- [PC]; PC++                # page-table slot selector
  MMU_ENTRY <- D ; pt(write) ; map(imm8) ; return to fetch   # REVIEW: entry source/format

# 0x0b STMMU $nn   (2 cyc · privileged · REVIEW)
.opcode page1 0x0b STMMU $nn
routine STMMU $nn:
  SCR1 <- [PC]; PC++                # page-table slot selector
  D <- MMU_ENTRY ; pt(read) ; map(imm8) ; return to fetch    # REVIEW: entry dest/format

# 0x0c LD USP,X   (1 cyc · privileged)
.opcode page1 0x0c LD USP,X
routine LD USP,X:
  USP <- X ; return to fetch

# 0x0d LD USP,Y   (1 cyc · privileged)
.opcode page1 0x0d LD USP,Y
routine LD USP,Y:
  USP <- Y ; return to fetch

# 0x0e LD USP,D   (1 cyc · privileged)
.opcode page1 0x0e LD USP,D
routine LD USP,D:
  USP <- D ; return to fetch

# 0x0f LD X,USP   (1 cyc · privileged)
.opcode page1 0x0f LD X,USP
routine LD X,USP:
  X <- USP ; return to fetch

# 0x10 LD Y,USP   (1 cyc · privileged)
.opcode page1 0x10 LD Y,USP
routine LD Y,USP:
  Y <- USP ; return to fetch

# 0x11 LD D,USP   (1 cyc · privileged)
.opcode page1 0x11 LD D,USP
routine LD D,USP:
  D <- USP ; return to fetch

# 0x12 XCHG X,USP   (3 cyc · privileged)
.opcode page1 0x12 XCHG X,USP
routine XCHG X,USP:
  SCR1 <- X
  X <- USP
  USP <- SCR1 ; return to fetch

# 0x13 XCHG Y,USP   (3 cyc · privileged)
.opcode page1 0x13 XCHG Y,USP
routine XCHG Y,USP:
  SCR1 <- Y
  Y <- USP
  USP <- SCR1 ; return to fetch

# 0x14 XCHG D,USP   (3 cyc · privileged)
.opcode page1 0x14 XCHG D,USP
routine XCHG D,USP:
  SCR1 <- D
  D <- USP
  USP <- SCR1 ; return to fetch

# 0x15 TAS (Y)   (5 cyc)
.opcode page1 0x15 TAS (Y)
routine TAS (Y):
  MAR  <- Y
  SCR1 <- [MAR] : nz, v=0 ; lock    # test: read the lock byte, hold the bus
  SCR2 <- 0
  SCR2 <- ~SCR2                     # the set value (all-ones)
  [MAR] <- SCR2 ; unlock ; return to fetch   # set: store, release the bus lock

# 0x16 TAS (Y+n8)   (7 cyc)
.opcode page1 0x16 TAS (Y+n8)
routine TAS (Y+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- Y + SCR1
  SCR1 <- [MAR] : nz, v=0 ; lock    # test: read the lock byte, hold the bus
  SCR2 <- 0
  SCR2 <- ~SCR2                     # the set value (all-ones)
  [MAR] <- SCR2 ; unlock ; return to fetch   # set: store, release the bus lock

# 0x17 TAS (SP+n8)   (7 cyc)
.opcode page1 0x17 TAS (SP+n8)
routine TAS (SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1 <- [MAR] : nz, v=0 ; lock    # test: read the lock byte, hold the bus
  SCR2 <- 0
  SCR2 <- ~SCR2                     # the set value (all-ones)
  [MAR] <- SCR2 ; unlock ; return to fetch   # set: store, release the bus lock

# 0x18 TAS ($nnnn)   (7 cyc)
.opcode page1 0x18 TAS ($nnnn)
routine TAS ($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR] : nz, v=0 ; lock    # test: read the lock byte, hold the bus
  SCR2 <- 0
  SCR2 <- ~SCR2                     # the set value (all-ones)
  [MAR] <- SCR2 ; unlock ; return to fetch   # set: store, release the bus lock

# 0x19 LEA X,X+n16   (3 cyc)
.opcode page1 0x19 LEA X,X+n16
routine LEA X,X+n16:
  SCR1.low  <- [PC]; PC++            # 16-bit displacement
  SCR1.high <- [PC]; PC++
  X <- X + SCR1 : z ; return to fetch

# 0x1a LEA Y,Y+n16   (3 cyc)
.opcode page1 0x1a LEA Y,Y+n16
routine LEA Y,Y+n16:
  SCR1.low  <- [PC]; PC++            # 16-bit displacement
  SCR1.high <- [PC]; PC++
  Y <- Y + SCR1 : z ; return to fetch

# 0x1b LEA SP,SP+n16   (3 cyc)
.opcode page1 0x1b LEA SP,SP+n16
routine LEA SP,SP+n16:
  SCR1.low  <- [PC]; PC++            # 16-bit displacement
  SCR1.high <- [PC]; PC++
  SP <- SP + SCR1 ; return to fetch

# 0x1c LEA X,PC+n8   (3 cyc)
.opcode page1 0x1c LEA X,PC+n8
routine LEA X,PC+n8:
  MDR  <- [PC]; PC++                # 8-bit displacement
  SCR1 <- sext(MDR)
  X <- PC + SCR1 : z ; return to fetch

# 0x1d LEA Y,PC+n8   (3 cyc)
.opcode page1 0x1d LEA Y,PC+n8
routine LEA Y,PC+n8:
  MDR  <- [PC]; PC++                # 8-bit displacement
  SCR1 <- sext(MDR)
  Y <- PC + SCR1 : z ; return to fetch

# 0x1e LEA SP,Y+n8   (3 cyc)
.opcode page1 0x1e LEA SP,Y+n8
routine LEA SP,Y+n8:
  MDR  <- [PC]; PC++                # 8-bit displacement
  SCR1 <- sext(MDR)
  SP <- Y + SCR1 ; return to fetch

# ===========================================================================
# PAGE 1 · Control flow — long branches & cold JMP/JSR
# ===========================================================================
# 0x1f LBRA rel16   (3 cyc)
.opcode page1 0x1f LBRA rel16
routine LBRA rel16:
  SCR1.low  <- [PC]; PC++            # rel16 displacement low
  SCR1.high <- [PC]; PC++
  PC <- PC + SCR1 ; return to fetch

# 0x20 LBRN rel16   (2 cyc)
.opcode page1 0x20 LBRN rel16
routine LBRN rel16:
  SCR1.low  <- [PC]; PC++            # rel16 displacement low
  return to fetch

# 0x21 LBHI rel16   (3 cyc)
.opcode page1 0x21 LBHI rel16
routine LBHI rel16:
  SCR1.low  <- [PC]; PC++            # rel16 displacement low
  SCR1.high <- [PC]; PC++ ; if not c|z goto BR_TAKEN
  return to fetch

# 0x22 LBLS rel16   (3 cyc)
.opcode page1 0x22 LBLS rel16
routine LBLS rel16:
  SCR1.low  <- [PC]; PC++            # rel16 displacement low
  SCR1.high <- [PC]; PC++ ; if c|z goto BR_TAKEN
  return to fetch

# 0x23 LBCC rel16   (3 cyc)
.opcode page1 0x23 LBCC rel16
routine LBCC rel16:
  SCR1.low  <- [PC]; PC++            # rel16 displacement low
  SCR1.high <- [PC]; PC++ ; if not c goto BR_TAKEN
  return to fetch

# 0x24 LBCS rel16   (3 cyc)
.opcode page1 0x24 LBCS rel16
routine LBCS rel16:
  SCR1.low  <- [PC]; PC++            # rel16 displacement low
  SCR1.high <- [PC]; PC++ ; if c goto BR_TAKEN
  return to fetch

# 0x25 LBNE rel16   (3 cyc)
.opcode page1 0x25 LBNE rel16
routine LBNE rel16:
  SCR1.low  <- [PC]; PC++            # rel16 displacement low
  SCR1.high <- [PC]; PC++ ; if not z goto BR_TAKEN
  return to fetch

# 0x26 LBEQ rel16   (3 cyc)
.opcode page1 0x26 LBEQ rel16
routine LBEQ rel16:
  SCR1.low  <- [PC]; PC++            # rel16 displacement low
  SCR1.high <- [PC]; PC++ ; if z goto BR_TAKEN
  return to fetch

# 0x27 LBVC rel16   (3 cyc)
.opcode page1 0x27 LBVC rel16
routine LBVC rel16:
  SCR1.low  <- [PC]; PC++            # rel16 displacement low
  SCR1.high <- [PC]; PC++ ; if not v goto BR_TAKEN
  return to fetch

# 0x28 LBVS rel16   (3 cyc)
.opcode page1 0x28 LBVS rel16
routine LBVS rel16:
  SCR1.low  <- [PC]; PC++            # rel16 displacement low
  SCR1.high <- [PC]; PC++ ; if v goto BR_TAKEN
  return to fetch

# 0x29 LBPL rel16   (3 cyc)
.opcode page1 0x29 LBPL rel16
routine LBPL rel16:
  SCR1.low  <- [PC]; PC++            # rel16 displacement low
  SCR1.high <- [PC]; PC++ ; if not n goto BR_TAKEN
  return to fetch

# 0x2a LBMI rel16   (3 cyc)
.opcode page1 0x2a LBMI rel16
routine LBMI rel16:
  SCR1.low  <- [PC]; PC++            # rel16 displacement low
  SCR1.high <- [PC]; PC++ ; if n goto BR_TAKEN
  return to fetch

# 0x2b LBGE rel16   (3 cyc)
.opcode page1 0x2b LBGE rel16
routine LBGE rel16:
  SCR1.low  <- [PC]; PC++            # rel16 displacement low
  SCR1.high <- [PC]; PC++ ; if not n^v goto BR_TAKEN
  return to fetch

# 0x2c LBLT rel16   (3 cyc)
.opcode page1 0x2c LBLT rel16
routine LBLT rel16:
  SCR1.low  <- [PC]; PC++            # rel16 displacement low
  SCR1.high <- [PC]; PC++ ; if n^v goto BR_TAKEN
  return to fetch

# 0x2d LBGT rel16   (3 cyc)
.opcode page1 0x2d LBGT rel16
routine LBGT rel16:
  SCR1.low  <- [PC]; PC++            # rel16 displacement low
  SCR1.high <- [PC]; PC++ ; if not z|(n^v) goto BR_TAKEN
  return to fetch

# 0x2e LBLE rel16   (3 cyc)
.opcode page1 0x2e LBLE rel16
routine LBLE rel16:
  SCR1.low  <- [PC]; PC++            # rel16 displacement low
  SCR1.high <- [PC]; PC++ ; if z|(n^v) goto BR_TAKEN
  return to fetch

# 0x2f LBSR rel16   (6 cyc)
.opcode page1 0x2f LBSR rel16
routine LBSR rel16:
  SCR1.low  <- [PC]; PC++           # rel16; PC -> return address
  SCR1.high <- [PC]; PC++
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- PC + SCR1 ; return to fetch # take the call

# 0x30 JMP (X+n16)   (6 cyc)
.opcode page1 0x30 JMP (X+n16)
routine JMP (X+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  PC <- SCR1 ; return to fetch

# 0x31 JMP (X+A)   (5 cyc)
.opcode page1 0x31 JMP (X+A)
routine JMP (X+A):
  SCR1 <- sext(A)
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  PC <- SCR1 ; return to fetch

# 0x32 JMP (X+B)   (5 cyc)
.opcode page1 0x32 JMP (X+B)
routine JMP (X+B):
  SCR1 <- sext(B)
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  PC <- SCR1 ; return to fetch

# 0x33 JMP (Y)   (4 cyc)
.opcode page1 0x33 JMP (Y)
routine JMP (Y):
  MAR  <- Y
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  PC <- SCR1 ; return to fetch

# 0x34 JMP (Y+n8)   (6 cyc)
.opcode page1 0x34 JMP (Y+n8)
routine JMP (Y+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- Y + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  PC <- SCR1 ; return to fetch

# 0x35 JMP (Y+n16)   (6 cyc)
.opcode page1 0x35 JMP (Y+n16)
routine JMP (Y+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- Y + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  PC <- SCR1 ; return to fetch

# 0x36 JMP (Y+A)   (5 cyc)
.opcode page1 0x36 JMP (Y+A)
routine JMP (Y+A):
  SCR1 <- sext(A)
  MAR  <- Y + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  PC <- SCR1 ; return to fetch

# 0x37 JMP (Y+B)   (5 cyc)
.opcode page1 0x37 JMP (Y+B)
routine JMP (Y+B):
  SCR1 <- sext(B)
  MAR  <- Y + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  PC <- SCR1 ; return to fetch

# 0x38 JMP (Y+D)   (5 cyc)
.opcode page1 0x38 JMP (Y+D)
routine JMP (Y+D):
  SCR1 <- D
  MAR  <- Y + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  PC <- SCR1 ; return to fetch

# 0x39 JMP (PC+n8)   (6 cyc)
.opcode page1 0x39 JMP (PC+n8)
routine JMP (PC+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- PC + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  PC <- SCR1 ; return to fetch

# 0x3a JMP (PC+n16)   (6 cyc)
.opcode page1 0x3a JMP (PC+n16)
routine JMP (PC+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- PC + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  PC <- SCR1 ; return to fetch

# 0x3b JSR (X+n16)   (9 cyc)
.opcode page1 0x3b JSR (X+n16)
routine JSR (X+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- SCR1 ; return to fetch

# 0x3c JSR (X+A)   (8 cyc)
.opcode page1 0x3c JSR (X+A)
routine JSR (X+A):
  SCR1 <- sext(A)
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- SCR1 ; return to fetch

# 0x3d JSR (X+B)   (8 cyc)
.opcode page1 0x3d JSR (X+B)
routine JSR (X+B):
  SCR1 <- sext(B)
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- SCR1 ; return to fetch

# 0x3e JSR (Y)   (7 cyc)
.opcode page1 0x3e JSR (Y)
routine JSR (Y):
  MAR  <- Y
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- SCR1 ; return to fetch

# 0x3f JSR (Y+n8)   (9 cyc)
.opcode page1 0x3f JSR (Y+n8)
routine JSR (Y+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- Y + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- SCR1 ; return to fetch

# 0x40 JSR (Y+n16)   (9 cyc)
.opcode page1 0x40 JSR (Y+n16)
routine JSR (Y+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- Y + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- SCR1 ; return to fetch

# 0x41 JSR (Y+A)   (8 cyc)
.opcode page1 0x41 JSR (Y+A)
routine JSR (Y+A):
  SCR1 <- sext(A)
  MAR  <- Y + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- SCR1 ; return to fetch

# 0x42 JSR (Y+B)   (8 cyc)
.opcode page1 0x42 JSR (Y+B)
routine JSR (Y+B):
  SCR1 <- sext(B)
  MAR  <- Y + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- SCR1 ; return to fetch

# 0x43 JSR (Y+D)   (8 cyc)
.opcode page1 0x43 JSR (Y+D)
routine JSR (Y+D):
  SCR1 <- D
  MAR  <- Y + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- SCR1 ; return to fetch

# 0x44 JSR (PC+n8)   (9 cyc)
.opcode page1 0x44 JSR (PC+n8)
routine JSR (PC+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- PC + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- SCR1 ; return to fetch

# 0x45 JSR (PC+n16)   (9 cyc)
.opcode page1 0x45 JSR (PC+n16)
routine JSR (PC+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- PC + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  SP <- SP - 2 ; MAR <- SP - 2      # reserve the return slot
  [MAR] <- low(PC); MAR++           # push return PC low
  [MAR] <- high(PC)                 # push return PC high
  PC <- SCR1 ; return to fetch

# ===========================================================================
# PAGE 1 · Byte load/store (cold modes)
# ===========================================================================
# 0x46 ST A,(SP)   (2 cyc)
.opcode page1 0x46 ST A,(SP)
routine ST A,(SP):
  MAR  <- SP
  [MAR] <- A : nz, v=0 ; return to fetch

# 0x47 ST B,(SP)   (2 cyc)
.opcode page1 0x47 ST B,(SP)
routine ST B,(SP):
  MAR  <- SP
  [MAR] <- B : nz, v=0 ; return to fetch

# 0x48 LD A,(X++)   (3 cyc)
.opcode page1 0x48 LD A,(X++)
routine LD A,(X++):
  MAR  <- X
  A  <- [MAR] : nz, v=0
  X <- MAR ; return to fetch

# 0x49 LD B,(X++)   (3 cyc)
.opcode page1 0x49 LD B,(X++)
routine LD B,(X++):
  MAR  <- X
  B  <- [MAR] : nz, v=0
  X <- MAR ; return to fetch

# 0x4a LD A,(--X)   (2 cyc)
.opcode page1 0x4a LD A,(--X)
routine LD A,(--X):
  MAR  <- X - 2 ; X <- X - 2
  A  <- [MAR] : nz, v=0 ; return to fetch

# 0x4b LD B,(--X)   (2 cyc)
.opcode page1 0x4b LD B,(--X)
routine LD B,(--X):
  MAR  <- X - 2 ; X <- X - 2
  B  <- [MAR] : nz, v=0 ; return to fetch

# 0x4c LD A,(-X)   (2 cyc)
.opcode page1 0x4c LD A,(-X)
routine LD A,(-X):
  MAR  <- X - 1 ; X <- X - 1
  A  <- [MAR] : nz, v=0 ; return to fetch

# 0x4d LD B,(-X)   (2 cyc)
.opcode page1 0x4d LD B,(-X)
routine LD B,(-X):
  MAR  <- X - 1 ; X <- X - 1
  B  <- [MAR] : nz, v=0 ; return to fetch

# 0x4e ST A,(X++)   (3 cyc)
.opcode page1 0x4e ST A,(X++)
routine ST A,(X++):
  MAR  <- X
  [MAR] <- A : nz, v=0
  X <- MAR ; return to fetch

# 0x4f ST B,(X++)   (3 cyc)
.opcode page1 0x4f ST B,(X++)
routine ST B,(X++):
  MAR  <- X
  [MAR] <- B : nz, v=0
  X <- MAR ; return to fetch

# 0x50 ST A,(--X)   (2 cyc)
.opcode page1 0x50 ST A,(--X)
routine ST A,(--X):
  MAR  <- X - 2 ; X <- X - 2
  [MAR] <- A : nz, v=0 ; return to fetch

# 0x51 ST B,(--X)   (2 cyc)
.opcode page1 0x51 ST B,(--X)
routine ST B,(--X):
  MAR  <- X - 2 ; X <- X - 2
  [MAR] <- B : nz, v=0 ; return to fetch

# 0x52 ST A,(-X)   (2 cyc)
.opcode page1 0x52 ST A,(-X)
routine ST A,(-X):
  MAR  <- X - 1 ; X <- X - 1
  [MAR] <- A : nz, v=0 ; return to fetch

# 0x53 ST B,(-X)   (2 cyc)
.opcode page1 0x53 ST B,(-X)
routine ST B,(-X):
  MAR  <- X - 1 ; X <- X - 1
  [MAR] <- B : nz, v=0 ; return to fetch

# 0x54 LD A,(X+A)   (3 cyc)
.opcode page1 0x54 LD A,(X+A)
routine LD A,(X+A):
  SCR1 <- sext(A)
  MAR  <- X + SCR1
  A  <- [MAR] : nz, v=0 ; return to fetch

# 0x55 LD A,(X+B)   (3 cyc)
.opcode page1 0x55 LD A,(X+B)
routine LD A,(X+B):
  SCR1 <- sext(B)
  MAR  <- X + SCR1
  A  <- [MAR] : nz, v=0 ; return to fetch

# 0x56 LD B,(X+A)   (3 cyc)
.opcode page1 0x56 LD B,(X+A)
routine LD B,(X+A):
  SCR1 <- sext(A)
  MAR  <- X + SCR1
  B  <- [MAR] : nz, v=0 ; return to fetch

# 0x57 LD B,(X+B)   (3 cyc)
.opcode page1 0x57 LD B,(X+B)
routine LD B,(X+B):
  SCR1 <- sext(B)
  MAR  <- X + SCR1
  B  <- [MAR] : nz, v=0 ; return to fetch

# 0x58 ST A,(X+A)   (3 cyc)
.opcode page1 0x58 ST A,(X+A)
routine ST A,(X+A):
  SCR1 <- sext(A)
  MAR  <- X + SCR1
  [MAR] <- A : nz, v=0 ; return to fetch

# 0x59 ST A,(X+B)   (3 cyc)
.opcode page1 0x59 ST A,(X+B)
routine ST A,(X+B):
  SCR1 <- sext(B)
  MAR  <- X + SCR1
  [MAR] <- A : nz, v=0 ; return to fetch

# 0x5a ST A,(X+D)   (3 cyc)
.opcode page1 0x5a ST A,(X+D)
routine ST A,(X+D):
  SCR1 <- D
  MAR  <- X + SCR1
  [MAR] <- A : nz, v=0 ; return to fetch

# 0x5b ST B,(X+A)   (3 cyc)
.opcode page1 0x5b ST B,(X+A)
routine ST B,(X+A):
  SCR1 <- sext(A)
  MAR  <- X + SCR1
  [MAR] <- B : nz, v=0 ; return to fetch

# 0x5c ST B,(X+B)   (3 cyc)
.opcode page1 0x5c ST B,(X+B)
routine ST B,(X+B):
  SCR1 <- sext(B)
  MAR  <- X + SCR1
  [MAR] <- B : nz, v=0 ; return to fetch

# 0x5d ST B,(X+D)   (3 cyc)
.opcode page1 0x5d ST B,(X+D)
routine ST B,(X+D):
  SCR1 <- D
  MAR  <- X + SCR1
  [MAR] <- B : nz, v=0 ; return to fetch

# 0x5e LD A,(X+n16)   (4 cyc)
.opcode page1 0x5e LD A,(X+n16)
routine LD A,(X+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- X + SCR1
  A  <- [MAR] : nz, v=0 ; return to fetch

# 0x5f LD B,(X+n16)   (4 cyc)
.opcode page1 0x5f LD B,(X+n16)
routine LD B,(X+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- X + SCR1
  B  <- [MAR] : nz, v=0 ; return to fetch

# 0x60 ST A,(X+n16)   (4 cyc)
.opcode page1 0x60 ST A,(X+n16)
routine ST A,(X+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- X + SCR1
  [MAR] <- A : nz, v=0 ; return to fetch

# 0x61 ST B,(X+n16)   (4 cyc)
.opcode page1 0x61 ST B,(X+n16)
routine ST B,(X+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- X + SCR1
  [MAR] <- B : nz, v=0 ; return to fetch

# 0x62 LD A,(SP+n16)   (4 cyc)
.opcode page1 0x62 LD A,(SP+n16)
routine LD A,(SP+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SP + SCR1
  A  <- [MAR] : nz, v=0 ; return to fetch

# 0x63 LD B,(SP+n16)   (4 cyc)
.opcode page1 0x63 LD B,(SP+n16)
routine LD B,(SP+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SP + SCR1
  B  <- [MAR] : nz, v=0 ; return to fetch

# 0x64 ST A,(SP+n16)   (4 cyc)
.opcode page1 0x64 ST A,(SP+n16)
routine ST A,(SP+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SP + SCR1
  [MAR] <- A : nz, v=0 ; return to fetch

# 0x65 ST B,(SP+n16)   (4 cyc)
.opcode page1 0x65 ST B,(SP+n16)
routine ST B,(SP+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SP + SCR1
  [MAR] <- B : nz, v=0 ; return to fetch

# 0x66 LD A,(-Y)   (2 cyc)
.opcode page1 0x66 LD A,(-Y)
routine LD A,(-Y):
  MAR  <- Y - 1 ; Y <- Y - 1
  A  <- [MAR] : nz, v=0 ; return to fetch

# 0x67 LD B,(-Y)   (2 cyc)
.opcode page1 0x67 LD B,(-Y)
routine LD B,(-Y):
  MAR  <- Y - 1 ; Y <- Y - 1
  B  <- [MAR] : nz, v=0 ; return to fetch

# 0x68 ST A,(-Y)   (2 cyc)
.opcode page1 0x68 ST A,(-Y)
routine ST A,(-Y):
  MAR  <- Y - 1 ; Y <- Y - 1
  [MAR] <- A : nz, v=0 ; return to fetch

# 0x69 ST B,(-Y)   (2 cyc)
.opcode page1 0x69 ST B,(-Y)
routine ST B,(-Y):
  MAR  <- Y - 1 ; Y <- Y - 1
  [MAR] <- B : nz, v=0 ; return to fetch

# ===========================================================================
# PAGE 1 · 16-bit load/store (cold modes)
# ===========================================================================
# 0x6a LD X,(Y)   (4 cyc)
.opcode page1 0x6a LD X,(Y)
routine LD X,(Y):
  MAR  <- Y
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  X <- SCR1 : nz, v=0 ; return to fetch

# 0x6b ST X,(Y)   (3 cyc)
.opcode page1 0x6b ST X,(Y)
routine ST X,(Y):
  MAR  <- Y
  [MAR] <- low(X); MAR++ : z
  [MAR] <- high(X); MAR++ : nz, v=0, z+ ; return to fetch

# 0x6c LD Y,(X)   (4 cyc)
.opcode page1 0x6c LD Y,(X)
routine LD Y,(X):
  MAR  <- X
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  Y <- SCR1 : nz, v=0 ; return to fetch

# 0x6d ST Y,(X)   (3 cyc)
.opcode page1 0x6d ST Y,(X)
routine ST Y,(X):
  MAR  <- X
  [MAR] <- low(Y); MAR++ : z
  [MAR] <- high(Y); MAR++ : nz, v=0, z+ ; return to fetch

# 0x6e LD D,(SP)   (3 cyc)
.opcode page1 0x6e LD D,(SP)
routine LD D,(SP):
  MAR  <- SP
  D.low  <- [MAR]; MAR++ : z
  D.high <- [MAR]; MAR++ : nz, v=0, z+ ; return to fetch

# 0x6f LD X,(SP)   (4 cyc)
.opcode page1 0x6f LD X,(SP)
routine LD X,(SP):
  MAR  <- SP
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  X <- SCR1 : nz, v=0 ; return to fetch

# 0x70 LD Y,(SP)   (4 cyc)
.opcode page1 0x70 LD Y,(SP)
routine LD Y,(SP):
  MAR  <- SP
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  Y <- SCR1 : nz, v=0 ; return to fetch

# 0x71 ST D,(SP)   (3 cyc)
.opcode page1 0x71 ST D,(SP)
routine ST D,(SP):
  MAR  <- SP
  [MAR] <- low(D); MAR++ : z
  [MAR] <- high(D); MAR++ : nz, v=0, z+ ; return to fetch

# 0x72 ST X,(SP)   (3 cyc)
.opcode page1 0x72 ST X,(SP)
routine ST X,(SP):
  MAR  <- SP
  [MAR] <- low(X); MAR++ : z
  [MAR] <- high(X); MAR++ : nz, v=0, z+ ; return to fetch

# 0x73 ST Y,(SP)   (3 cyc)
.opcode page1 0x73 ST Y,(SP)
routine ST Y,(SP):
  MAR  <- SP
  [MAR] <- low(Y); MAR++ : z
  [MAR] <- high(Y); MAR++ : nz, v=0, z+ ; return to fetch

# 0x74 LD X,(X++)   (4 cyc)
.opcode page1 0x74 LD X,(X++)
routine LD X,(X++):
  MAR  <- X
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  X <- SCR1 : nz, v=0 ; return to fetch

# 0x75 LD Y,(X++)   (5 cyc)
.opcode page1 0x75 LD Y,(X++)
routine LD Y,(X++):
  MAR  <- X
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  Y <- SCR1 : nz, v=0
  X <- MAR ; return to fetch

# 0x76 ST Y,(X++)   (4 cyc)
.opcode page1 0x76 ST Y,(X++)
routine ST Y,(X++):
  MAR  <- X
  [MAR] <- low(Y); MAR++ : z
  [MAR] <- high(Y); MAR++ : nz, v=0, z+
  X <- MAR ; return to fetch

# 0x77 LD D,(Y++)   (4 cyc)
.opcode page1 0x77 LD D,(Y++)
routine LD D,(Y++):
  MAR  <- Y
  D.low  <- [MAR]; MAR++ : z
  D.high <- [MAR]; MAR++ : nz, v=0, z+
  Y <- MAR ; return to fetch

# 0x78 ST D,(Y++)   (4 cyc)
.opcode page1 0x78 ST D,(Y++)
routine ST D,(Y++):
  MAR  <- Y
  [MAR] <- low(D); MAR++ : z
  [MAR] <- high(D); MAR++ : nz, v=0, z+
  Y <- MAR ; return to fetch

# 0x79 LD X,(Y++)   (5 cyc)
.opcode page1 0x79 LD X,(Y++)
routine LD X,(Y++):
  MAR  <- Y
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  X <- SCR1 : nz, v=0
  Y <- MAR ; return to fetch

# 0x7a ST X,(Y++)   (4 cyc)
.opcode page1 0x7a ST X,(Y++)
routine ST X,(Y++):
  MAR  <- Y
  [MAR] <- low(X); MAR++ : z
  [MAR] <- high(X); MAR++ : nz, v=0, z+
  Y <- MAR ; return to fetch

# 0x7b LD D,(--X)   (3 cyc)
.opcode page1 0x7b LD D,(--X)
routine LD D,(--X):
  MAR  <- X - 2 ; X <- X - 2
  D.low  <- [MAR]; MAR++ : z
  D.high <- [MAR]; MAR++ : nz, v=0, z+ ; return to fetch

# 0x7c ST D,(--X)   (3 cyc)
.opcode page1 0x7c ST D,(--X)
routine ST D,(--X):
  MAR  <- X - 2 ; X <- X - 2
  [MAR] <- low(D); MAR++ : z
  [MAR] <- high(D); MAR++ : nz, v=0, z+ ; return to fetch

# 0x7d ST Y,(--X)   (3 cyc)
.opcode page1 0x7d ST Y,(--X)
routine ST Y,(--X):
  MAR  <- X - 2 ; X <- X - 2
  [MAR] <- low(Y); MAR++ : z
  [MAR] <- high(Y); MAR++ : nz, v=0, z+ ; return to fetch

# 0x7e LD D,(--Y)   (3 cyc)
.opcode page1 0x7e LD D,(--Y)
routine LD D,(--Y):
  MAR  <- Y - 2 ; Y <- Y - 2
  D.low  <- [MAR]; MAR++ : z
  D.high <- [MAR]; MAR++ : nz, v=0, z+ ; return to fetch

# 0x7f ST D,(--Y)   (3 cyc)
.opcode page1 0x7f ST D,(--Y)
routine ST D,(--Y):
  MAR  <- Y - 2 ; Y <- Y - 2
  [MAR] <- low(D); MAR++ : z
  [MAR] <- high(D); MAR++ : nz, v=0, z+ ; return to fetch

# 0x80 ST X,(--Y)   (3 cyc)
.opcode page1 0x80 ST X,(--Y)
routine ST X,(--Y):
  MAR  <- Y - 2 ; Y <- Y - 2
  [MAR] <- low(X); MAR++ : z
  [MAR] <- high(X); MAR++ : nz, v=0, z+ ; return to fetch

# 0x81 LD Y,(X+n8)   (6 cyc)
.opcode page1 0x81 LD Y,(X+n8)
routine LD Y,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  Y <- SCR1 : nz, v=0 ; return to fetch

# 0x82 ST Y,(X+n8)   (5 cyc)
.opcode page1 0x82 ST Y,(X+n8)
routine ST Y,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  [MAR] <- low(Y); MAR++ : z
  [MAR] <- high(Y); MAR++ : nz, v=0, z+ ; return to fetch

# 0x83 LD X,(Y+n8)   (6 cyc)
.opcode page1 0x83 LD X,(Y+n8)
routine LD X,(Y+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- Y + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  X <- SCR1 : nz, v=0 ; return to fetch

# 0x84 ST X,(Y+n8)   (5 cyc)
.opcode page1 0x84 ST X,(Y+n8)
routine ST X,(Y+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- Y + SCR1
  [MAR] <- low(X); MAR++ : z
  [MAR] <- high(X); MAR++ : nz, v=0, z+ ; return to fetch

# 0x85 LD D,(X+n16)   (5 cyc)
.opcode page1 0x85 LD D,(X+n16)
routine LD D,(X+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- X + SCR1
  D.low  <- [MAR]; MAR++ : z
  D.high <- [MAR]; MAR++ : nz, v=0, z+ ; return to fetch

# 0x86 LD X,(X+n16)   (6 cyc)
.opcode page1 0x86 LD X,(X+n16)
routine LD X,(X+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  X <- SCR1 : nz, v=0 ; return to fetch

# 0x87 ST D,(X+n16)   (5 cyc)
.opcode page1 0x87 ST D,(X+n16)
routine ST D,(X+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- X + SCR1
  [MAR] <- low(D); MAR++ : z
  [MAR] <- high(D); MAR++ : nz, v=0, z+ ; return to fetch

# 0x88 ST X,(X+n16)   (5 cyc)
.opcode page1 0x88 ST X,(X+n16)
routine ST X,(X+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- X + SCR1
  [MAR] <- low(X); MAR++ : z
  [MAR] <- high(X); MAR++ : nz, v=0, z+ ; return to fetch

# 0x89 LD D,(SP+n16)   (5 cyc)
.opcode page1 0x89 LD D,(SP+n16)
routine LD D,(SP+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SP + SCR1
  D.low  <- [MAR]; MAR++ : z
  D.high <- [MAR]; MAR++ : nz, v=0, z+ ; return to fetch

# 0x8a LD X,(SP+n16)   (6 cyc)
.opcode page1 0x8a LD X,(SP+n16)
routine LD X,(SP+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SP + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  X <- SCR1 : nz, v=0 ; return to fetch

# 0x8b LD Y,(SP+n16)   (6 cyc)
.opcode page1 0x8b LD Y,(SP+n16)
routine LD Y,(SP+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SP + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  Y <- SCR1 : nz, v=0 ; return to fetch

# 0x8c ST D,(SP+n16)   (5 cyc)
.opcode page1 0x8c ST D,(SP+n16)
routine ST D,(SP+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SP + SCR1
  [MAR] <- low(D); MAR++ : z
  [MAR] <- high(D); MAR++ : nz, v=0, z+ ; return to fetch

# 0x8d ST X,(SP+n16)   (5 cyc)
.opcode page1 0x8d ST X,(SP+n16)
routine ST X,(SP+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SP + SCR1
  [MAR] <- low(X); MAR++ : z
  [MAR] <- high(X); MAR++ : nz, v=0, z+ ; return to fetch

# 0x8e ST Y,(SP+n16)   (5 cyc)
.opcode page1 0x8e ST Y,(SP+n16)
routine ST Y,(SP+n16):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SP + SCR1
  [MAR] <- low(Y); MAR++ : z
  [MAR] <- high(Y); MAR++ : nz, v=0, z+ ; return to fetch

# 0x8f LD Y,(X+D)   (5 cyc)
.opcode page1 0x8f LD Y,(X+D)
routine LD Y,(X+D):
  SCR1 <- D
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  Y <- SCR1 : nz, v=0 ; return to fetch

# 0x90 ST Y,(X+D)   (4 cyc)
.opcode page1 0x90 ST Y,(X+D)
routine ST Y,(X+D):
  SCR1 <- D
  MAR  <- X + SCR1
  [MAR] <- low(Y); MAR++ : z
  [MAR] <- high(Y); MAR++ : nz, v=0, z+ ; return to fetch

# 0x91 LD D,(Y+D)   (4 cyc)
.opcode page1 0x91 LD D,(Y+D)
routine LD D,(Y+D):
  SCR1 <- D
  MAR  <- Y + SCR1
  D.low  <- [MAR]; MAR++ : z
  D.high <- [MAR]; MAR++ : nz, v=0, z+ ; return to fetch

# 0x92 LD SP,($nnnn)   (6 cyc)
.opcode page1 0x92 LD SP,($nnnn)
routine LD SP,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  SP <- SCR1 : nz, v=0 ; return to fetch

# 0x93 ST SP,($nnnn)   (5 cyc)
.opcode page1 0x93 ST SP,($nnnn)
routine ST SP,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  [MAR] <- low(SP); MAR++ : z
  [MAR] <- high(SP); MAR++ : nz, v=0, z+ ; return to fetch

# ===========================================================================
# PAGE 1 · Byte ALU (cold modes + ADC/SBC/EOR/BIT)
# ===========================================================================
# 0x94 ADD A,(SP)   (3 cyc)
.opcode page1 0x94 ADD A,(SP)
routine ADD A,(SP):
  MAR  <- SP
  SCR1 <- [MAR]
  A <- A + SCR1 : nzvch ; return to fetch

# 0x95 ADD B,(SP)   (3 cyc)
.opcode page1 0x95 ADD B,(SP)
routine ADD B,(SP):
  MAR  <- SP
  SCR1 <- [MAR]
  B <- B + SCR1 : nzvch ; return to fetch

# 0x96 SUB A,(SP)   (3 cyc)
.opcode page1 0x96 SUB A,(SP)
routine SUB A,(SP):
  MAR  <- SP
  SCR1 <- [MAR]
  A <- A - SCR1 : nzvc ; return to fetch

# 0x97 SUB B,(SP)   (3 cyc)
.opcode page1 0x97 SUB B,(SP)
routine SUB B,(SP):
  MAR  <- SP
  SCR1 <- [MAR]
  B <- B - SCR1 : nzvc ; return to fetch

# 0x98 CMP A,(SP)   (3 cyc)
.opcode page1 0x98 CMP A,(SP)
routine CMP A,(SP):
  MAR  <- SP
  SCR1 <- [MAR]
  _ <- A - SCR1 : nzvc ; return to fetch

# 0x99 CMP B,(SP)   (3 cyc)
.opcode page1 0x99 CMP B,(SP)
routine CMP B,(SP):
  MAR  <- SP
  SCR1 <- [MAR]
  _ <- B - SCR1 : nzvc ; return to fetch

# 0x9a AND A,(SP)   (3 cyc)
.opcode page1 0x9a AND A,(SP)
routine AND A,(SP):
  MAR  <- SP
  SCR1 <- [MAR]
  A <- A & SCR1 : nz, v=0 ; return to fetch

# 0x9b AND B,(SP)   (3 cyc)
.opcode page1 0x9b AND B,(SP)
routine AND B,(SP):
  MAR  <- SP
  SCR1 <- [MAR]
  B <- B & SCR1 : nz, v=0 ; return to fetch

# 0x9c OR A,(SP)   (3 cyc)
.opcode page1 0x9c OR A,(SP)
routine OR A,(SP):
  MAR  <- SP
  SCR1 <- [MAR]
  A <- A | SCR1 : nz, v=0 ; return to fetch

# 0x9d OR B,(SP)   (3 cyc)
.opcode page1 0x9d OR B,(SP)
routine OR B,(SP):
  MAR  <- SP
  SCR1 <- [MAR]
  B <- B | SCR1 : nz, v=0 ; return to fetch

# 0x9e ADC A,$nn   (2 cyc)
.opcode page1 0x9e ADC A,$nn
routine ADC A,$nn:
  SCR1 <- [PC]; PC++
  A <- A +c SCR1 : nzvch ; return to fetch

# 0x9f ADC B,$nn   (2 cyc)
.opcode page1 0x9f ADC B,$nn
routine ADC B,$nn:
  SCR1 <- [PC]; PC++
  B <- B +c SCR1 : nzvch ; return to fetch

# 0xa0 ADC A,($nnnn)   (5 cyc)
.opcode page1 0xa0 ADC A,($nnnn)
routine ADC A,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  A <- A +c SCR1 : nzvch ; return to fetch

# 0xa1 ADC B,($nnnn)   (5 cyc)
.opcode page1 0xa1 ADC B,($nnnn)
routine ADC B,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  B <- B +c SCR1 : nzvch ; return to fetch

# 0xa2 ADC A,(X)   (3 cyc)
.opcode page1 0xa2 ADC A,(X)
routine ADC A,(X):
  MAR  <- X
  SCR1 <- [MAR]
  A <- A +c SCR1 : nzvch ; return to fetch

# 0xa3 ADC B,(X)   (3 cyc)
.opcode page1 0xa3 ADC B,(X)
routine ADC B,(X):
  MAR  <- X
  SCR1 <- [MAR]
  B <- B +c SCR1 : nzvch ; return to fetch

# 0xa4 ADC A,(X+n8)   (5 cyc)
.opcode page1 0xa4 ADC A,(X+n8)
routine ADC A,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  A <- A +c SCR1 : nzvch ; return to fetch

# 0xa5 ADC B,(X+n8)   (5 cyc)
.opcode page1 0xa5 ADC B,(X+n8)
routine ADC B,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  B <- B +c SCR1 : nzvch ; return to fetch

# 0xa6 ADC A,(SP+n8)   (5 cyc)
.opcode page1 0xa6 ADC A,(SP+n8)
routine ADC A,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1 <- [MAR]
  A <- A +c SCR1 : nzvch ; return to fetch

# 0xa7 ADC B,(SP+n8)   (5 cyc)
.opcode page1 0xa7 ADC B,(SP+n8)
routine ADC B,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1 <- [MAR]
  B <- B +c SCR1 : nzvch ; return to fetch

# 0xa8 SBC A,$nn   (2 cyc)
.opcode page1 0xa8 SBC A,$nn
routine SBC A,$nn:
  SCR1 <- [PC]; PC++
  A <- A -c SCR1 : nzvc ; return to fetch

# 0xa9 SBC B,$nn   (2 cyc)
.opcode page1 0xa9 SBC B,$nn
routine SBC B,$nn:
  SCR1 <- [PC]; PC++
  B <- B -c SCR1 : nzvc ; return to fetch

# 0xaa SBC A,($nnnn)   (5 cyc)
.opcode page1 0xaa SBC A,($nnnn)
routine SBC A,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  A <- A -c SCR1 : nzvc ; return to fetch

# 0xab SBC B,($nnnn)   (5 cyc)
.opcode page1 0xab SBC B,($nnnn)
routine SBC B,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  B <- B -c SCR1 : nzvc ; return to fetch

# 0xac SBC A,(X)   (3 cyc)
.opcode page1 0xac SBC A,(X)
routine SBC A,(X):
  MAR  <- X
  SCR1 <- [MAR]
  A <- A -c SCR1 : nzvc ; return to fetch

# 0xad SBC B,(X)   (3 cyc)
.opcode page1 0xad SBC B,(X)
routine SBC B,(X):
  MAR  <- X
  SCR1 <- [MAR]
  B <- B -c SCR1 : nzvc ; return to fetch

# 0xae SBC A,(X+n8)   (5 cyc)
.opcode page1 0xae SBC A,(X+n8)
routine SBC A,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  A <- A -c SCR1 : nzvc ; return to fetch

# 0xaf SBC B,(X+n8)   (5 cyc)
.opcode page1 0xaf SBC B,(X+n8)
routine SBC B,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  B <- B -c SCR1 : nzvc ; return to fetch

# 0xb0 SBC A,(SP+n8)   (5 cyc)
.opcode page1 0xb0 SBC A,(SP+n8)
routine SBC A,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1 <- [MAR]
  A <- A -c SCR1 : nzvc ; return to fetch

# 0xb1 SBC B,(SP+n8)   (5 cyc)
.opcode page1 0xb1 SBC B,(SP+n8)
routine SBC B,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1 <- [MAR]
  B <- B -c SCR1 : nzvc ; return to fetch

# 0xb2 EOR A,$nn   (2 cyc)
.opcode page1 0xb2 EOR A,$nn
routine EOR A,$nn:
  SCR1 <- [PC]; PC++
  A <- A ^ SCR1 : nz, v=0 ; return to fetch

# 0xb3 EOR B,$nn   (2 cyc)
.opcode page1 0xb3 EOR B,$nn
routine EOR B,$nn:
  SCR1 <- [PC]; PC++
  B <- B ^ SCR1 : nz, v=0 ; return to fetch

# 0xb4 EOR A,($nnnn)   (5 cyc)
.opcode page1 0xb4 EOR A,($nnnn)
routine EOR A,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  A <- A ^ SCR1 : nz, v=0 ; return to fetch

# 0xb5 EOR B,($nnnn)   (5 cyc)
.opcode page1 0xb5 EOR B,($nnnn)
routine EOR B,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  B <- B ^ SCR1 : nz, v=0 ; return to fetch

# 0xb6 EOR A,(X)   (3 cyc)
.opcode page1 0xb6 EOR A,(X)
routine EOR A,(X):
  MAR  <- X
  SCR1 <- [MAR]
  A <- A ^ SCR1 : nz, v=0 ; return to fetch

# 0xb7 EOR B,(X)   (3 cyc)
.opcode page1 0xb7 EOR B,(X)
routine EOR B,(X):
  MAR  <- X
  SCR1 <- [MAR]
  B <- B ^ SCR1 : nz, v=0 ; return to fetch

# 0xb8 EOR A,(X+n8)   (5 cyc)
.opcode page1 0xb8 EOR A,(X+n8)
routine EOR A,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  A <- A ^ SCR1 : nz, v=0 ; return to fetch

# 0xb9 EOR B,(X+n8)   (5 cyc)
.opcode page1 0xb9 EOR B,(X+n8)
routine EOR B,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  B <- B ^ SCR1 : nz, v=0 ; return to fetch

# 0xba BIT A,$nn   (2 cyc)
.opcode page1 0xba BIT A,$nn
routine BIT A,$nn:
  SCR1 <- [PC]; PC++
  _ <- A & SCR1 : nz, v=0 ; return to fetch

# 0xbb BIT B,$nn   (2 cyc)
.opcode page1 0xbb BIT B,$nn
routine BIT B,$nn:
  SCR1 <- [PC]; PC++
  _ <- B & SCR1 : nz, v=0 ; return to fetch

# 0xbc BIT A,($nnnn)   (5 cyc)
.opcode page1 0xbc BIT A,($nnnn)
routine BIT A,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  _ <- A & SCR1 : nz, v=0 ; return to fetch

# 0xbd BIT B,($nnnn)   (5 cyc)
.opcode page1 0xbd BIT B,($nnnn)
routine BIT B,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1 <- [MAR]
  _ <- B & SCR1 : nz, v=0 ; return to fetch

# 0xbe BIT A,(X)   (3 cyc)
.opcode page1 0xbe BIT A,(X)
routine BIT A,(X):
  MAR  <- X
  SCR1 <- [MAR]
  _ <- A & SCR1 : nz, v=0 ; return to fetch

# 0xbf BIT B,(X)   (3 cyc)
.opcode page1 0xbf BIT B,(X)
routine BIT B,(X):
  MAR  <- X
  SCR1 <- [MAR]
  _ <- B & SCR1 : nz, v=0 ; return to fetch

# 0xc0 BIT A,(X+n8)   (5 cyc)
.opcode page1 0xc0 BIT A,(X+n8)
routine BIT A,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  _ <- A & SCR1 : nz, v=0 ; return to fetch

# 0xc1 BIT B,(X+n8)   (5 cyc)
.opcode page1 0xc1 BIT B,(X+n8)
routine BIT B,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1 <- [MAR]
  _ <- B & SCR1 : nz, v=0 ; return to fetch

# ===========================================================================
# PAGE 1 · 16-bit ALU & wide compare (cold)
# ===========================================================================
# 0xc2 ADC D,$nnnn   (3 cyc)
.opcode page1 0xc2 ADC D,$nnnn
routine ADC D,$nnnn:
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  D <- D +c SCR1 : nzvc ; return to fetch

# 0xc3 ADC D,($nnnn)   (6 cyc)
.opcode page1 0xc3 ADC D,($nnnn)
routine ADC D,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D +c SCR1 : nzvc ; return to fetch

# 0xc4 ADC D,(SP+n8)   (6 cyc)
.opcode page1 0xc4 ADC D,(SP+n8)
routine ADC D,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D +c SCR1 : nzvc ; return to fetch

# 0xc5 ADC D,(X)   (4 cyc)
.opcode page1 0xc5 ADC D,(X)
routine ADC D,(X):
  MAR  <- X
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D +c SCR1 : nzvc ; return to fetch

# 0xc6 ADC D,(X+n8)   (6 cyc)
.opcode page1 0xc6 ADC D,(X+n8)
routine ADC D,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D +c SCR1 : nzvc ; return to fetch

# 0xc7 SBC D,$nnnn   (3 cyc)
.opcode page1 0xc7 SBC D,$nnnn
routine SBC D,$nnnn:
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  D <- D -c SCR1 : nzvc ; return to fetch

# 0xc8 SBC D,($nnnn)   (6 cyc)
.opcode page1 0xc8 SBC D,($nnnn)
routine SBC D,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D -c SCR1 : nzvc ; return to fetch

# 0xc9 SBC D,(SP+n8)   (6 cyc)
.opcode page1 0xc9 SBC D,(SP+n8)
routine SBC D,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D -c SCR1 : nzvc ; return to fetch

# 0xca SBC D,(X)   (4 cyc)
.opcode page1 0xca SBC D,(X)
routine SBC D,(X):
  MAR  <- X
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D -c SCR1 : nzvc ; return to fetch

# 0xcb SBC D,(X+n8)   (6 cyc)
.opcode page1 0xcb SBC D,(X+n8)
routine SBC D,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D -c SCR1 : nzvc ; return to fetch

# 0xcc ADD D,(X++)   (5 cyc)
.opcode page1 0xcc ADD D,(X++)
routine ADD D,(X++):
  MAR  <- X
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D + SCR1 : nzvc
  X <- MAR ; return to fetch

# 0xcd ADD D,(--X)   (4 cyc)
.opcode page1 0xcd ADD D,(--X)
routine ADD D,(--X):
  MAR  <- X - 2 ; X <- X - 2
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D + SCR1 : nzvc ; return to fetch

# 0xce SUB D,(X)   (4 cyc)
.opcode page1 0xce SUB D,(X)
routine SUB D,(X):
  MAR  <- X
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D - SCR1 : nzvc ; return to fetch

# 0xcf SUB D,(X+n8)   (6 cyc)
.opcode page1 0xcf SUB D,(X+n8)
routine SUB D,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D - SCR1 : nzvc ; return to fetch

# 0xd0 SUB D,(X+D)   (5 cyc)
.opcode page1 0xd0 SUB D,(X+D)
routine SUB D,(X+D):
  SCR1 <- D
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  D <- D - SCR1 : nzvc ; return to fetch

# 0xd1 CMP D,(X)   (4 cyc)
.opcode page1 0xd1 CMP D,(X)
routine CMP D,(X):
  MAR  <- X
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  _ <- D - SCR1 : nzvc ; return to fetch

# 0xd2 CMP D,(X+n8)   (6 cyc)
.opcode page1 0xd2 CMP D,(X+n8)
routine CMP D,(X+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- X + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  _ <- D - SCR1 : nzvc ; return to fetch

# 0xd3 CMP X,($nnnn)   (6 cyc)
.opcode page1 0xd3 CMP X,($nnnn)
routine CMP X,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  _ <- X - SCR1 : nzvc ; return to fetch

# 0xd4 CMP Y,($nnnn)   (6 cyc)
.opcode page1 0xd4 CMP Y,($nnnn)
routine CMP Y,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  _ <- Y - SCR1 : nzvc ; return to fetch

# 0xd5 CMP SP,($nnnn)   (6 cyc)
.opcode page1 0xd5 CMP SP,($nnnn)
routine CMP SP,($nnnn):
  SCR1.low  <- [PC]; PC++
  SCR1.high <- [PC]; PC++
  MAR  <- SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  _ <- SP - SCR1 : nzvc ; return to fetch

# 0xd6 CMP X,(SP+n8)   (6 cyc)
.opcode page1 0xd6 CMP X,(SP+n8)
routine CMP X,(SP+n8):
  MDR  <- [PC]; PC++
  SCR1 <- sext(MDR)
  MAR  <- SP + SCR1
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  _ <- X - SCR1 : nzvc ; return to fetch

# 0xd7 CMP X,(X)   (4 cyc)
.opcode page1 0xd7 CMP X,(X)
routine CMP X,(X):
  MAR  <- X
  SCR1.low  <- [MAR]; MAR++
  SCR1.high <- [MAR]; MAR++
  _ <- X - SCR1 : nzvc ; return to fetch

# ===========================================================================
# PAGE 1 · RMW & register-direct unary (cold ops)
# ===========================================================================
# 0xd8 NEG A   (1 cyc)
.opcode page1 0xd8 NEG A
routine NEG A:
  A <- -A : nzvc ; return to fetch

# 0xd9 COM A   (1 cyc)
.opcode page1 0xd9 COM A
routine COM A:
  A <- ~A : nz, v=0, c=1 ; return to fetch

# 0xda ROL A   (1 cyc)
.opcode page1 0xda ROL A
routine ROL A:
  A <- rol(A) : nzvc ; return to fetch

# 0xdb ROR A   (1 cyc)
.opcode page1 0xdb ROR A
routine ROR A:
  A <- ror(A) : nzvc ; return to fetch

# 0xdc NEG B   (1 cyc)
.opcode page1 0xdc NEG B
routine NEG B:
  B <- -B : nzvc ; return to fetch

# 0xdd COM B   (1 cyc)
.opcode page1 0xdd COM B
routine COM B:
  B <- ~B : nz, v=0, c=1 ; return to fetch

# 0xde ROL B   (1 cyc)
.opcode page1 0xde ROL B
routine ROL B:
  B <- rol(B) : nzvc ; return to fetch

# 0xdf ROR B   (1 cyc)
.opcode page1 0xdf ROR B
routine ROR B:
  B <- ror(B) : nzvc ; return to fetch

# 0xe0 INC (X+)   (4 cyc)
.opcode page1 0xe0 INC (X+)
routine INC (X+):
  MAR  <- X
  SCR1 <- [MAR] ; X++
  SCR1 <- SCR1 + 1 : nzv
  [MAR] <- SCR1 ; return to fetch

# 0xe1 DEC (X+)   (4 cyc)
.opcode page1 0xe1 DEC (X+)
routine DEC (X+):
  MAR  <- X
  SCR1 <- [MAR] ; X++
  SCR1 <- SCR1 - 1 : nzv
  [MAR] <- SCR1 ; return to fetch

# 0xe2 INC (Y)   (4 cyc)
.opcode page1 0xe2 INC (Y)
routine INC (Y):
  MAR  <- Y
  SCR1 <- [MAR]
  SCR1 <- SCR1 + 1 : nzv
  [MAR] <- SCR1 ; return to fetch

# 0xe3 DEC (Y)   (4 cyc)
.opcode page1 0xe3 DEC (Y)
routine DEC (Y):
  MAR  <- Y
  SCR1 <- [MAR]
  SCR1 <- SCR1 - 1 : nzv
  [MAR] <- SCR1 ; return to fetch

# 0xe4 CLR (Y)   (3 cyc)
.opcode page1 0xe4 CLR (Y)
routine CLR (Y):
  MAR  <- Y
  SCR1 <- 0
  [MAR] <- SCR1 : nz, v=0, c=0 ; return to fetch

# 0xe5 TST (Y)   (2 cyc)
.opcode page1 0xe5 TST (Y)
routine TST (Y):
  MAR  <- Y
  _ <- [MAR] : nz, v=0 ; return to fetch

