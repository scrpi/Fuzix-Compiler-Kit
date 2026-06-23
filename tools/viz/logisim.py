#!/usr/bin/env python3
"""tools/viz/logisim.py — generate a runnable Logisim Evolution 4.1.0 .circ from the
structural HDL, via the Yosys JSON netlist (toolchain.md §6; P3 generated-not-authored).

Each BLIP cell becomes a real chip: a Logisim TTL-library part where one exists (the
74-series number we use), else a general Logisim component, else a custom subcircuit.
Connectivity is by NAMED TUNNELS — every net bit gets a 1-bit tunnel, so no routing is
needed and the circuit simulates as soon as it loads.

Geometry: chips are placed FACING SOUTH so their DIP pins land on two vertical columns
(west = DIP pins 1..N/2, east = N/2+1..N), readable top-to-bottom. The verified EAST
pin formula (loc-relative) is rotated to SOUTH by Logisim's Location.rotate 270deg,
(x,y) -> (-y, x):
    EAST  pin i<N/2 : (i*20+10, +30)       i>=N/2 : (W-(i-N/2)*20-10, -30)   [W=N*10]
    SOUTH pin i<N/2 : (-30, i*20+10)        i>=N/2 : (+30, W-(i-N/2)*20-10)
GND (pin N/2) and VCC (pin N) are not connectable by default, so we skip them. Each pin
is stubbed out horizontally to a tunnel; tunnels alternate between two lanes so their
labels never overlap (pins are 20px apart, labels need ~3 grid of vertical clearance).

Usage:  logisim.py <netlist.json> <TOP> <out.circ>
v1 handles all-TTL blocks (control_word_decoder, microsequencer). Memory/Register/
hierarchy come next.
"""
import json
import re
import sys

# --- cell library: BLIP cell -> Logisim part + Verilog-port -> DIP-pin map ----------
# `pins` = DIP pin count. `map` = {verilog_port: [DIP pin per bit, LSB first]}.
# Pinouts are the datasheet pinouts; Logisim numbers TTL ports in DIP-pin order.
CELLS = {
    "sn74ahct04": {"lib": "7", "name": "7404", "pins": 14,   # hex inverter
        "map": {"a": [1, 3, 5, 9, 11, 13], "y": [2, 4, 6, 8, 10, 12]}},
    "sn74ahct08": {"lib": "7", "name": "7408", "pins": 14,   # quad 2-in AND
        "map": {"a": [1, 4, 9, 12], "b": [2, 5, 10, 13], "y": [3, 6, 8, 11]}},
    "sn74ahct32": {"lib": "7", "name": "7432", "pins": 14,   # quad 2-in OR
        "map": {"a": [1, 4, 9, 12], "b": [2, 5, 10, 13], "y": [3, 6, 8, 11]}},
    "sn74ahct86": {"lib": "7", "name": "7486", "pins": 14,   # quad 2-in XOR
        "map": {"a": [1, 4, 9, 12], "b": [2, 5, 10, 13], "y": [3, 6, 8, 11]}},
    "sn74ahct138": {"lib": "7", "name": "74138", "pins": 16,  # 3->8 decoder
        "map": {"a": [1], "b": [2], "c": [3], "g2a_n": [4], "g2b_n": [5], "g1": [6],
                "y": [15, 14, 13, 12, 11, 10, 9, 7]}},
    "sn74ahct139": {"lib": "7", "name": "74139", "pins": 16,  # dual 2->4 decoder
        "map": {"g1_n": [1], "a1": [2], "b1": [3], "y1": [4, 5, 6, 7],
                "g2_n": [15], "a2": [14], "b2": [13], "y2": [12, 11, 10, 9]}},
    "sn74ahct157": {"lib": "7", "name": "74157", "pins": 16,  # quad 2:1 mux
        "map": {"sel": [1], "g_n": [15],
                "a": [2, 5, 11, 14], "b": [3, 6, 10, 13], "y": [4, 7, 9, 12]}},
    "cd74act151": {"lib": "7", "name": "74151", "pins": 16,   # 8:1 mux
        "map": {"a": [11], "b": [10], "c": [9], "g_n": [7], "y": [5], "w": [6],
                "d": [4, 3, 2, 1, 15, 14, 13, 12]}},
    "sn74act153": {"lib": "7", "name": "74153", "pins": 16,   # dual 4:1 mux
        "map": {"a": [15], "b": [2], "g1_n": [1], "c1": [6, 5, 4, 3], "y1": [7],
                "g2_n": [14], "c2": [10, 11, 12, 13], "y2": [9]}},
    "cd74act161": {"lib": "7", "name": "74161", "pins": 16,   # 4-bit counter
        "map": {"clr_n": [1], "clk": [2], "p": [3, 4, 5, 6], "enp": [7], "load_n": [9],
                "ent": [10], "q": [14, 13, 12, 11], "rco": [15]}},
    "sn74ahct541": {"lib": "7", "name": "74541", "pins": 20,  # octal buffer (3-state)
        "map": {"oe1_n": [1], "a": [2, 3, 4, 5, 6, 7, 8, 9],
                "y": [18, 17, 16, 15, 14, 13, 12, 11], "oe2_n": [19]}},
    "sn74f283": {"lib": "7", "name": "74283", "pins": 16,     # 4-bit adder
        "map": {"A": [5, 3, 14, 12], "B": [6, 2, 15, 11], "C0": [7],
                "S": [4, 1, 13, 10], "C4": [9]}},
}

STUB = 20      # horizontal run from a pin before its vertical jog
CH_STEP = 10   # per-pin vertical-channel spacing (each pin's jog gets its own column)
TUN_DY = 40    # tunnel-column spacing: 4 grid (>=3, readable) AND even, so the column sits
               # on loc.y+even*10 while pins sit on loc.y+odd*10 -> their rows never coincide
               # -> no dogleg endpoint ever lands on a sibling's wire (no false T-junctions)


def sanitize(name):
    return re.sub(r"[^A-Za-z0-9_]", "_", name)


def pin_xy(loc, pin, npins):
    """Absolute (x, y) of DIP pin `pin` (1-based) for a SOUTH-facing chip at loc."""
    lx, ly = loc
    i = pin - 1
    w = npins * 10
    if i < npins // 2:                         # EAST (i*20+10, 30) -> SOUTH (-30, i*20+10)
        return (lx - 30, ly + i * 20 + 10)
    return (lx + 30, ly + w - (i - npins // 2) * 20 - 10)  # SOUTH (+30, ...)


def comp(lib, name, loc, attrs=()):
    a = "".join(f'\n    <a name="{k}" val="{v}"/>' for k, v in attrs)
    return f'  <comp lib="{lib}" loc="({loc[0]},{loc[1]})" name="{name}">{(a + chr(10) + "  ") if a else ""}</comp>\n'


def tunnel(loc, label, facing=None):
    attrs = [("label", label)] + ([("facing", facing)] if facing else [])
    return comp("0", "Tunnel", loc, attrs)


def wire(a, b):
    return f'  <wire from="({a[0]},{a[1]})" to="({b[0]},{b[1]})"/>\n'


def main():
    netlist_path, top, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    module = json.load(open(netlist_path))["modules"][top]

    bitname = {}
    for nm, info in module.get("netnames", {}).items():
        bits, san = info["bits"], sanitize(nm)
        for i, b in enumerate(bits):
            if isinstance(b, int) and b not in bitname:
                bitname[b] = f"{san}_{i}" if len(bits) > 1 else san

    def net_of(bit):
        if bit == "0": return "ZERO"
        if bit == "1": return "ONE"
        if isinstance(bit, int): return bitname.get(bit, f"n{bit}")
        return None  # x / z -> leave open

    comps, wires, unmapped = [], [], []

    # --- cells: one SOUTH-facing chip each; pins doglegged out to an aligned column ----
    # Each side's pins (20px apart) fan out to a single vertical tunnel column (30px apart)
    # via an S-dogleg: pin -> horizontal -> vertical jog (its own channel) -> horizontal ->
    # tunnel. Distinct channels keep the verticals from overlapping.
    col = row = 0
    for inst, cell in module.get("cells", {}).items():
        spec = CELLS.get(cell["type"])
        if spec is None:
            unmapped.append((inst, cell["type"])); continue
        loc = (380 + col * 500, 240 + row * 460)
        col += 1
        if col == 4:
            col, row = 0, row + 1
        comps.append(comp(spec["lib"], spec["name"], loc,
                          [("label", sanitize(inst)), ("facing", "south")]))
        conns = cell["connections"]
        west, east = [], []
        for port, pins in spec["map"].items():
            bits = conns.get(port, [])
            for idx, dip in enumerate(pins):
                if idx < len(bits):
                    label = net_of(bits[idx])
                    if label is not None:
                        px, py = pin_xy(loc, dip, spec["pins"])
                        (west if px < loc[0] else east).append((py, px, label))
        for side, sign in ((west, -1), (east, +1)):
            if not side:
                continue
            side.sort()                         # top -> bottom
            m = len(side)
            ty0 = int(round((side[0][0] + side[-1][0]) / 2 - TUN_DY * (m - 1) / 2, -1))
            if (ty0 - loc[1]) % 20 != 0:         # keep the column on the even grid (see TUN_DY)
                ty0 -= 10
            colx = loc[0] + sign * (30 + STUB + m * CH_STEP + 20)
            face = "east" if sign < 0 else "west"      # face the chip (flipped 180)
            # Jog-channel order: the fan diverges from the centre (upper pins route up to
            # higher tunnels, lower pins down to lower ones), so a single monotonic order
            # crosses. Nest from the extremes inward — top & bottom pins turn NEAREST the
            # chip, the centre pin FARTHEST: rank = [0, m-1, 1, m-2, ...]. Crossing-free.
            rank, lo, hi = [0] * m, 0, m - 1
            r = 0
            while lo <= hi:
                rank[lo] = r; r += 1
                if hi != lo:
                    rank[hi] = r; r += 1
                lo += 1; hi -= 1
            for j, (py, px, label) in enumerate(side):
                chx = loc[0] + sign * (30 + STUB + rank[j] * CH_STEP)
                ty = ty0 + TUN_DY * j
                wires.append(wire((px, py), (chx, py)))          # 1: out from the pin
                if ty != py:
                    wires.append(wire((chx, py), (chx, ty)))     # 2: vertical jog
                wires.append(wire((chx, ty), (colx, ty)))        # 3: in to the tunnel column
                comps.append(tunnel((colx, ty), label, face))

    # --- module ports: one 1-bit Pin per bit, co-located with its net tunnel ----------
    in_y = out_y = 120
    for pname, pinfo in module.get("ports", {}).items():
        is_out = pinfo["direction"] == "output"
        bits, san = pinfo["bits"], sanitize(pname)
        for i, b in enumerate(bits):
            label = net_of(b)
            if label is None:
                continue
            lbl = f"{san}_{i}" if len(bits) > 1 else san
            if is_out:
                loc = (2400, out_y); out_y += 30
                comps.append(comp("0", "Pin", loc, [("label", lbl), ("output", "true")]))
            else:
                loc = (40, in_y); in_y += 30
                comps.append(comp("0", "Pin", loc, [("label", lbl)]))
            comps.append(tunnel(loc, label))

    # --- the two constant rails -------------------------------------------------------
    comps.append(comp("0", "Constant", (40, 40), [("value", "0x0")]))
    comps.append(tunnel((40, 40), "ZERO"))
    comps.append(comp("0", "Constant", (40, 70), [("value", "0x1")]))
    comps.append(tunnel((40, 70), "ONE"))

    circuit = (
        f'  <circuit name="{top}">\n'
        f'    <a name="appearance" val="logisim_evolution"/>\n'
        f'    <a name="circuit" val="{top}"/>\n'
        f'    <a name="simulationFrequency" val="0.5"/>\n'
        + "".join(comps) + "".join(wires) + "  </circuit>\n"
    )
    open(out_path, "w").write(PREAMBLE.format(main=top) + circuit + "</project>\n")

    print(f"logisim: wrote {out_path}  ({len(module.get('cells', {}))} cells, "
          f"{len(bitname)} nets, {len(wires)} stub wires)")
    if unmapped:
        print("  UNMAPPED cells (no Logisim mapping yet):")
        for inst, t in unmapped:
            print(f"    {inst}: {t}")


PREAMBLE = '''<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<project source="4.1.0" version="1.0">
  This file is intended to be loaded by Logisim-evolution v4.1.0(https://github.com/logisim-evolution/).

  <lib desc="#Wiring" name="0">
    <tool name="Pin">
      <a name="appearance" val="classic"/>
    </tool>
  </lib>
  <lib desc="#Gates" name="1"/>
  <lib desc="#Plexers" name="2"/>
  <lib desc="#Arithmetic" name="3"/>
  <lib desc="#FPArithmetic" name="4"/>
  <lib desc="#Memory" name="5"/>
  <lib desc="#I/O" name="6"/>
  <lib desc="#TTL" name="7"/>
  <lib desc="#TCL" name="8"/>
  <lib desc="#Base" name="9"/>
  <lib desc="#BFH-Praktika" name="10"/>
  <lib desc="#Input/Output-Extra" name="11"/>
  <lib desc="#Soc" name="12"/>
  <main name="{main}"/>
  <options>
    <a name="gateUndefined" val="ignore"/>
    <a name="simlimit" val="1000"/>
    <a name="simrand" val="0"/>
  </options>
  <mappings>
    <tool lib="9" map="Button2" name="Poke Tool"/>
    <tool lib="9" map="Button3" name="Menu Tool"/>
    <tool lib="9" map="Ctrl Button1" name="Menu Tool"/>
  </mappings>
  <toolbar>
    <tool lib="9" name="Poke Tool"/>
    <tool lib="9" name="Edit Tool"/>
    <tool lib="9" name="Wiring Tool"/>
    <tool lib="9" name="Text Tool"/>
    <sep/>
    <tool lib="0" name="Pin"/>
    <tool lib="0" name="Pin">
      <a name="facing" val="west"/>
      <a name="output" val="true"/>
    </tool>
  </toolbar>
'''


if __name__ == "__main__":
    main()
