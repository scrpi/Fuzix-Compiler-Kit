# BLIP microcode — first routines (register-transfer notation).
# Grammar: docs/microcode-source.md. Assembled by uasm.py against control_word.toml.
# Each line is one microword = one cycle (strict 1:1).

# ---------------------------------------------------------------------------
# FETCH — the fixed fetch entry (microaddress 0). Reset and RETURN_FETCH land
# here; `dispatch` jumps via the opcode map on the byte just latched into IR.
# ---------------------------------------------------------------------------
.fetch FETCH
routine FETCH:
  IR <- [PC]; PC++; dispatch          # read opcode @PC -> IR, PC+1, dispatch

# ---------------------------------------------------------------------------
# LD A,(X+n8) — 8-bit signed offset. The opcode names register+mode, so FETCH's
# dispatch lands here directly (no postbyte, D-41). Byte value not yet assigned
# (D-41); the .opcode binding gets a placeholder index for now.
# ---------------------------------------------------------------------------
.opcode page0 LD A,(X+n8)
routine LD A,(X+n8):
  MDR  <- [PC]; PC++                   # offset @PC -> MDR
  SCR1 <- sext(MDR)                    # SCR1 <- sign-extend(offset)
  MAR  <- X + SCR1                     # MAR <- X + offset (EA)
  A    <- [MAR] : nz, v=0              # A <- (EA); set N/Z, V=0
