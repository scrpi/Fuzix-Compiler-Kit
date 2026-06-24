#!/usr/bin/env python3
"""tools/viz/logisim.py — keep a Logisim Evolution 4.1.0 .circ in step with the
structural HDL, via the Yosys JSON netlist (toolchain.md §6; P3 generated-not-authored).

Two modes, like KiCad's schematic->PCB flow:

  generate   first creation: emit a fresh .circ (overwrites). Each BLIP cell becomes a
             real chip (a Logisim TTL-library part), wired by NAMED TUNNELS — one 1-bit
             tunnel per net, so the circuit simulates the moment it loads.

  reconcile  thereafter: the .circ is YOURS to edit (move/rotate chips, rip tunnels out
             for direct wires, add splitters). reconcile never overwrites it — it does
             an LVS diff against the HDL and reports DRIFT:
               * electrically identical (any rewiring that preserves the net partition)
                 -> silent. Tunnel<->wire swaps, rearrangements: accepted.
               * HDL net split / pin floating  -> OPEN  (a wire is missing)
               * drawn net merges two HDL nets  -> SHORT
               * HDL chip with no matching chip -> MISSING (offer --insert)
               * drawn chip absent from the HDL -> STALE  (warn only)

Stable identity: every chip carries a `label` = its sanitized HDL instance name. That
label is the reference designator — it survives moves/rotations/rewiring (Logisim drops
unknown attributes on save, but preserves `label`), so reconcile matches chips by label,
never by position. Tunnels and wires are fungible and carry no identity.

Geometry: chips are placed FACING SOUTH so their DIP pins land on two vertical columns
(west = DIP pins 1..N/2, east = N/2+1..N), readable top-to-bottom. The verified EAST
pin formula (loc-relative) rotates to the four facings by Logisim's Location.rotate:
    EAST  pin i<N/2 : (i*20+10, +30)       i>=N/2 : (W-(i-N/2)*20-10, -30)   [W=N*10]
    SOUTH = rotate(EAST) (x,y)->(-y,x);  WEST = (-x,-y);  NORTH = (y,-x)
GND (pin N/2) and VCC (pin N) are not connectable by default, so we skip them. Each pin
S-doglegs out to a vertically-aligned tunnel column; tunnel rows sit on the even grid
while pins sit on the odd grid, so no dogleg endpoint lands on a sibling's wire.

Usage:
  logisim.py generate  <netlist.json> <TOP> <out.circ> [--flat]
  logisim.py reconcile <netlist.json> <TOP> <circ> [--insert]
  logisim.py <netlist.json> <TOP> <out.circ>            # legacy: == generate

generate draws every multi-bit net as a bus tunnel + per-chip break-out splitter by default;
--flat draws 1-bit-tunnel-per-net instead (reconcile handles either drawing). v2 handles
all-TTL blocks; the memory components come next.
"""
import json
import re
import sys
from collections import defaultdict

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
PART2CELL = {spec["name"]: (ct, spec) for ct, spec in CELLS.items()}  # Logisim part -> cell

# --- custom-chip cells: the 3 parts with no Logisim TTL part. Each becomes a SUBCIRCUIT that
# draws as its real DIP (1:1 datasheet pinout) and wraps a lib-5 primitive (+ inverters for the
# active-low controls). Treated like a TTL chip for placement/wiring/reconcile, but with the
# DIP `custom_pin_xy` geometry and a subcircuit instance instead of a lib-7 part. `map` = the
# datasheet port->DIP-pin map (LSB-first); `power` = the GND/VCC/NC pins (drawn, not connectable).
CUSTOM_CHIPS = {
    "sn74ahct574": {"name": "74574", "pins": 20, "internal": "register",  # octal DFF, 3-state out
        "map": {"OE_n": [1], "D": [2, 3, 4, 5, 6, 7, 8, 9], "CLK": [11],
                "Q": [19, 18, 17, 16, 15, 14, 13, 12]},
        "power": {10: "GND", 20: "VCC"}},
    "is61c64": {"name": "is61c64", "pins": 28, "internal": "ram",          # 8Kx8 async SRAM
        "map": {"a": [10, 9, 8, 7, 6, 5, 4, 3, 25, 24, 21, 23, 2],
                "io": [11, 12, 13, 15, 16, 17, 18, 19],
                "ce_n": [20], "oe_n": [22], "we_n": [27]},
        "power": {14: "GND", 28: "VCC", 1: "NC", 26: "NC"}},
    "sst39sf010a": {"name": "sst39sf010a", "pins": 32, "internal": "rom",  # 128Kx8 flash (read)
        "map": {"a": [12, 11, 10, 9, 8, 7, 6, 5, 27, 26, 23, 25, 4, 28, 29, 3, 2],
                "dq": [13, 14, 15, 17, 18, 19, 20, 21],
                "ce_n": [22], "oe_n": [24], "we_n": [31]},
        "power": {16: "VSS", 32: "VDD", 1: "NC", 30: "NC"}},
}
PART2CUSTOM = {spec["name"]: (ct, spec) for ct, spec in CUSTOM_CHIPS.items()}

STUB = 20      # horizontal run from a pin before its vertical jog
CH_STEP = 10   # per-pin vertical-channel spacing (each pin's jog gets its own column)
TUN_DY = 40    # tunnel-column spacing: 4 grid (>=3, readable) AND even, so the column sits
               # on loc.y+even*10 while pins sit on loc.y+odd*10 -> their rows never coincide
               # -> no dogleg endpoint ever lands on a sibling's wire (no false T-junctions)

# loc-relative pin rotation: EAST is the verified base; the others are Location.rotate of it.
_ROT = {"east": lambda x, y: (x, y), "south": lambda x, y: (-y, x),
        "west": lambda x, y: (-x, -y), "north": lambda x, y: (y, -x)}


def sanitize(name):
    return re.sub(r"[^A-Za-z0-9_]", "_", name)


def pin_xy(loc, pin, npins, facing="south"):
    """Absolute (x, y) of DIP pin `pin` (1-based) for a chip at loc with `facing`."""
    lx, ly = loc
    i = pin - 1
    w = npins * 10
    if i < npins // 2:
        ex, ey = (i * 20 + 10, 30)                     # EAST base, west half
    else:
        ex, ey = (w - (i - npins // 2) * 20 - 10, -30)  # EAST base, east half
    dx, dy = _ROT.get((facing or "south").lower(), _ROT["south"])(ex, ey)
    return (lx + dx, ly + dy)


def custom_pin_xy(loc, pin, npins):
    """Instance-pin coord of DIP pin `pin` for a custom-chip subcircuit at `loc`: pins 1..N/2
    down the LEFT edge (top->bottom), N/2+1..N up the RIGHT (so pin N is top-right), 20px pitch,
    anchor at the body's top-centre. Verified against the custom-DIP <appear> coordinate formula."""
    lx, ly = loc
    if pin <= npins // 2:
        return (lx - 50, ly + 20 + (pin - 1) * 20)        # left column, top -> bottom
    return (lx + 50, ly + 20 + (npins - pin) * 20)        # right column, bottom -> top


def dip_appearance(name, npins, pins):
    """Custom <appear> block drawing an `npins` DIP. `pins` = {dip_pin: (label, interface_pin_loc)}
    for the CONNECTABLE pins. The anchor sits at the body's top-centre, so a placed instance's pins
    land at custom_pin_xy(loc, dip, npins) — i.e. instance_pin = loc + (port_centre - anchor_centre),
    where here (port_centre - anchor_centre) == custom_pin_xy((0,0), dip, npins) by construction."""
    ax, ay = 200, 60                                       # appearance-space anchor centre
    rows = npins // 2
    body_y, body_h = ay + 10, rows * 20 + 20
    out = [f'      <rect fill="#ffffff" height="{body_h}" stroke="#000000" stroke-width="2" '
           f'width="80" x="{ax - 40}" y="{body_y}"/>',
           f'      <text font-family="SansSerif" font-size="11" font-weight="bold" '
           f'text-anchor="middle" x="{ax}" y="{body_y + body_h // 2 + 4}">{name}</text>']
    for dip in sorted(pins):
        _label, ploc, is_out = pins[dip]
        ox, oy = custom_pin_xy((0, 0), dip, npins)         # offset of this pin from instance loc
        # `dir` makes the circ-port's input/output reference EXPLICIT. Logisim's appearance reader
        # binds a circ-port to a Pin only when the Pin's direction matches the reference, and with
        # no `dir` it infers "input" from the width-8 glyph — so output pins would never bind.
        out.append(f'      <circ-port dir="{"out" if is_out else "in"}" height="8" '
                   f'pin="{ploc[0]},{ploc[1]}" width="8" x="{ax + ox - 4}" y="{ay + oy - 4}"/>')
    out.append(f'      <circ-anchor facing="east" height="6" width="6" x="{ax - 3}" y="{ay - 3}"/>')
    return "    <appear>\n" + "\n".join(out) + "\n    </appear>\n"


def emit_custom_subcircuit(spec):
    """The <circuit> DEFINITION for a custom chip: one 1-bit interface Pin per connectable DIP pin
    plus the custom DIP appearance, so it draws + instantiates as the real chip with a 1:1 pinout.
    (The internal primitive + bundling splitters land in a later pass; the reconciler treats the
    chip as a black box, so it already reconciles pin-faithfully.)"""
    name, npins, pmap = spec["name"], spec["pins"], spec["map"]
    pin_label, pin_out = {}, {}
    for port, dips in pmap.items():
        # A Logisim subcircuit pin can only be input or output (no inout), so a bidirectional data
        # line is modelled as a single TRI-STATE OUTPUT: the chip drives the shared bus, which is a
        # multi-driver tri-state net at the block level (the read path). This stays pin-faithful —
        # the reconciler is a black-box LVS that ignores pin direction. (`io` = SRAM data bus.)
        is_out = port in ("Q", "dq", "y", "io")
        for i, dip in enumerate(dips):
            pin_label[dip] = f"{port}{i}" if len(dips) > 1 else port
            pin_out[dip] = is_out
    comps, pins, iy = [], {}, 100
    for dip in sorted(pin_label):
        ploc = (100, iy); iy += 30
        pins[dip] = (pin_label[dip], ploc, pin_out[dip])
        comps.append(comp("0", "Pin", ploc,
                          [("label", pin_label[dip])] + ([("type", "output")] if pin_out[dip] else [])))
    return (f'  <circuit name="{name}">\n    <a name="circuit" val="{name}"/>\n'
            f'    <a name="appearance" val="logisim_evolution"/>\n'
            + dip_appearance(name, npins, pins) + "".join(comps) + "  </circuit>\n")


# --- XML emit helpers ---------------------------------------------------------------
def comp(lib, name, loc, attrs=()):
    libattr = f'lib="{lib}" ' if lib else ""   # falsy lib => a project-local subcircuit instance
    a = "".join(f'\n    <a name="{k}" val="{v}"/>' for k, v in attrs)
    return f'  <comp {libattr}loc="({loc[0]},{loc[1]})" name="{name}">{(a + chr(10) + "  ") if a else ""}</comp>\n'


def tunnel(loc, label, facing=None, width=1):
    attrs = ([("label", label)] + ([("width", str(width))] if width > 1 else [])
             + ([("facing", facing)] if facing else []))
    return comp("0", "Tunnel", loc, attrs)


def wire(a, b):
    return f'  <wire from="({a[0]},{a[1]})" to="({b[0]},{b[1]})"/>\n'


def build_net_of(module):
    """Return net_of(bit) -> stable net label (or None for x/z), per this module."""
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

    return net_of, bitname


# --- buses: a multi-bit net becomes one bus tunnel + a per-chip break-out splitter ----
BUS_MAX = 32                     # Logisim hard limit: a wire/bus/splitter/Pin is <= 32 bits wide
BUS_SPACING = 2                  # splitter `spacing` attr -> fanout pitch = 20px
BUS_GAP = BUS_SPACING * 10       # vertical pitch of a bus group's dogleg rows (= fanout pitch)
BUS_INTER = TUN_DY               # vertical gap between items (bus group / 1-bit) in a column


def build_bus_map(module, chunk_wide=True):
    """bit -> (busname, position, width): each net bit's WIDEST containing multi-bit signal,
    so an overlapping field (a slice of a wider port) resolves to the encompassing bus and
    every endpoint of that bit agrees on one bus label + width. A signal wider than the 32-bit
    Logisim bus limit is, when `chunk_wide`, split into BUS_MAX-bit, position-relative chunks
    `san__0`, `san__1`, … (widest-first, so those chunks claim their bits before any narrower net
    does — a consistent grid across endpoints and blocks). With `chunk_wide=False` a >32-bit net is
    left UNBUSSED, so each of its bits routes as its own 1-bit net (used at the cpu top, where wide
    inter-block signals connect bit-by-bit by net name and chunk buses would only add colliding
    slice splitters). Empty when no buses exist."""
    bus_of = {}
    sources = list(module.get("netnames", {}).items()) + list(module.get("ports", {}).items())
    for nm, info in sorted(sources, key=lambda kv: -len(kv[1]["bits"])):   # widest first
        bits = info["bits"]
        if len(bits) < 2:
            continue
        san = sanitize(nm)
        if len(bits) <= BUS_MAX:
            for i, b in enumerate(bits):
                if isinstance(b, int):
                    bus_of.setdefault(b, (san, i, len(bits)))
        elif chunk_wide:
            for c0 in range(0, len(bits), BUS_MAX):          # 88-bit cw -> cw__0/__1/__2 (32+32+24)
                chunk = bits[c0:c0 + BUS_MAX]
                cname, cw = f"{san}__{c0 // BUS_MAX}", len(chunk)
                for j, b in enumerate(chunk):
                    if isinstance(b, int):
                        bus_of.setdefault(b, (cname, j, cw))
    return bus_of


def _channels(n):
    """outer-near interleave [0, n-1, 1, n-2, ...]: top & bottom pins turn NEAREST the chip,
    the centre FARTHEST, so the fan diverging from the centre never crosses itself."""
    rank, lo, hi, r = [0] * n, 0, n - 1, 0
    while lo <= hi:
        rank[lo] = r; r += 1
        if hi != lo:
            rank[hi] = r; r += 1
        lo += 1; hi -= 1
    return rank


def _dogleg(px, py, chx, ty, tx, wires):
    """pin -> horizontal -> vertical jog (its own channel) -> horizontal -> (tx, ty)."""
    wires.append(wire((px, py), (chx, py)))
    if ty != py:
        wires.append(wire((chx, py), (chx, ty)))
    wires.append(wire((chx, ty), (tx, ty)))


def _route_1bit(side, loc, sign, net_of, comps, wires, _bus):
    """Each pin S-doglegs to its own 1-bit tunnel in one aligned column."""
    lab = sorted((py, px, net_of(bit)) for py, px, bit in side if net_of(bit) is not None)
    if not lab:
        return
    m = len(lab)
    ty0 = int(round((lab[0][0] + lab[-1][0]) / 2 - TUN_DY * (m - 1) / 2, -1))
    if (ty0 - loc[1]) % 20 != 0:                  # keep the column on the even grid (see TUN_DY)
        ty0 -= 10
    colx = loc[0] + sign * (30 + STUB + m * CH_STEP + 20)
    face = "east" if sign < 0 else "west"         # face the chip
    rank = _channels(m)
    for j, (py, px, label) in enumerate(lab):
        chx = loc[0] + sign * (30 + STUB + rank[j] * CH_STEP)
        ty = ty0 + TUN_DY * j
        _dogleg(px, py, chx, ty, colx, wires)
        comps.append(tunnel((colx, ty), label, face))


def _route_bus(side, loc, sign, net_of, comps, wires, bus_of):
    """Pins on a multi-bit net are grouped and broken out of a bus tunnel through a splitter;
    a bus group's rows pack at BUS_GAP so the splitter's fanout ends land on the column."""
    groups, singles = {}, []
    for py, px, bit in side:
        nb = bus_of.get(bit) if isinstance(bit, int) else None
        if nb:
            groups.setdefault(nb[0], [nb[2], []])[1].append((nb[1], py, px))
        elif net_of(bit) is not None:
            singles.append((py, px, net_of(bit)))
    items = [(min(p[1] for p in pl), "bus", (bn, w, sorted(pl, key=lambda p: p[1])))
             for bn, (w, pl) in groups.items()]
    items += [(py, "one", (label, py, px)) for py, px, label in singles]
    if not items:
        return
    items.sort(key=lambda it: it[0])
    # relative row ys: bus rows packed at BUS_GAP, BUS_INTER between items (all multiples of
    # 20, so every row keeps the chip's even/odd parity -> a dogleg never shorts onto a pin)
    rel, meta, cy, first = [], [], 0, True
    for _key, kind, payload in items:
        if not first:
            cy += BUS_INTER
        first = False
        if kind == "bus":
            r0, F = len(rel), len(payload[2])
            for i in range(F):
                rel.append(cy)
                if i < F - 1:
                    cy += BUS_GAP
            meta.append((kind, r0, payload))
        else:
            rel.append(cy); meta.append((kind, len(rel) - 1, payload))
    nrows = len(rel)
    pys = [p[0] for p in side]
    ty0 = int(round((min(pys) + max(pys)) / 2 - rel[-1] / 2, -1))
    if (ty0 - loc[1]) % 20 != 0:
        ty0 -= 10
    colx = loc[0] + sign * (30 + STUB + nrows * CH_STEP + 20)
    face = "east" if sign < 0 else "west"
    rank = _channels(nrows)
    routes = []                                   # (py, px, target_x, target_y, row)
    for kind, r0, payload in meta:
        if kind == "one":
            label, py, px = payload
            ty = ty0 + rel[r0]
            comps.append(tunnel((colx, ty), label, face))
            routes.append((py, px, colx, ty, r0))
        else:
            bn, w, pins = payload
            F = len(pins)
            ys = [ty0 + rel[r0 + i] for i in range(F)]
            if sign < 0:
                sloc, sf = (colx - 20, ys[0] + 10 + BUS_GAP * (F - 1)), "east"
            else:
                sloc, sf = (colx + 20, ys[0] - 10), "west"
            comb, ends = splitter_ends(sloc, sf, F, BUS_SPACING)
            attrs = [("incoming", str(w)), ("fanout", str(F)), ("facing", sf),
                     ("appear", "left"), ("spacing", str(BUS_SPACING))]
            routed = {p[0] for p in pins}
            attrs += [(f"bit{pos}", str(i)) for i, (pos, _, _) in enumerate(pins)]
            attrs += [(f"bit{k}", "none") for k in range(w) if k not in routed]
            comps.append(comp("0", "Splitter", sloc, attrs))
            comps.append(tunnel(comb, bn, face, w))      # bus tunnel faces the chip
            for i, (_pos, py, px) in enumerate(pins):
                ex, ey = ends[i]
                routes.append((py, px, ex, ey, r0 + i))
    for py, px, tx, ty, rw in routes:
        chx = loc[0] + sign * (30 + STUB + rank[rw] * CH_STEP)
        _dogleg(px, py, chx, ty, tx, wires)


# --- one chip: SOUTH-facing part, pins routed out to an aligned column ---------------
def emit_chip(spec, inst, loc, conns, net_of, bus_of=None, custom=False):
    """Return (comp_lines, wire_lines) for one chip at `loc`. Shared by generate + insert.
    A TTL chip is a lib-7 DIP (pin_xy geometry); a custom chip is a subcircuit instance (no lib,
    custom_pin_xy DIP geometry). Either way each port-bit pins out, 1-bit or bus-routed."""
    if custom:
        comps = [comp("", spec["name"], loc, [("label", sanitize(inst))])]  # subcircuit instance
        geom = lambda dip: custom_pin_xy(loc, dip, spec["pins"])
    else:
        comps = [comp(spec["lib"], spec["name"], loc,
                      [("label", sanitize(inst)), ("facing", "south")])]
        geom = lambda dip: pin_xy(loc, dip, spec["pins"])
    wires = []
    west, east = [], []
    for port, pins in spec["map"].items():
        bits = conns.get(port, [])
        for idx, dip in enumerate(pins):
            if idx < len(bits):
                px, py = geom(dip)
                (west if px < loc[0] else east).append((py, px, bits[idx]))
    route = _route_bus if bus_of else _route_1bit
    for side, sign in ((west, -1), (east, +1)):
        if side:
            route(side, loc, sign, net_of, comps, wires, bus_of)
    return comps, wires


def chip_grid(idx, buses=False):
    if buses:
        return (460 + (idx % 4) * 680, 260 + (idx // 4) * 520)
    return (380 + (idx % 4) * 500, 240 + (idx // 4) * 460)


def _one_bus(bits, bus_of):
    """If all `bits` belong to ONE bus, return (busname, positions, width); else None."""
    if not bus_of:
        return None
    bi = [bus_of.get(b) if isinstance(b, int) else None for b in bits]
    if bi and bi[0] and all(x and x[0] == bi[0][0] for x in bi):
        return bi[0][0], [x[1] for x in bi], bi[0][2]
    return None


def _bus_pin(loc, ob, comps, wires, toward):
    """Wire a (multi-bit) pin at `loc` to its bus `ob`=(busname, positions, width): a direct bus
    tunnel if the pin IS the whole bus, else a fanout-1 splitter tapping the named bits. `toward`
    = +1 if the bus tunnel sits to the pin's right (input Pin on the left), -1 to its left (output
    Pin on the right). The splitter faces so its COMBINED (bus) terminal is on the tunnel side and
    its fanout END on the pin side: the pin->end wire then never crosses the combined point, which
    would otherwise T-junction the wide bus straight onto the narrow tap (a short + width clash)."""
    bn, pos, W = ob
    if len(pos) == W and pos == list(range(W)):
        comps.append(tunnel(loc, bn, width=W))
    else:
        sx = loc[0] + toward * 160
        facing = "west" if toward > 0 else "east"           # end lands on the pin (loc) side
        comb, ends = splitter_ends((sx, loc[1]), facing, 1, BUS_SPACING)
        comps.append(comp("0", "Splitter", (sx, loc[1]),
                          [("incoming", str(W)), ("fanout", "1"), ("facing", facing),
                           ("spacing", str(BUS_SPACING))]
                          + [(f"bit{p}", "0") for p in pos]
                          + [(f"bit{k}", "none") for k in range(W) if k not in pos]))
        comps.append(tunnel(comb, bn, width=W))
        ex, ey = ends[0]
        wires.append(wire(loc, (ex, loc[1])))
        if ey != loc[1]:
            wires.append(wire((ex, loc[1]), (ex, ey)))


def _port_lanes(bits, san):
    """Split a port's bits into interface lanes — one Pin each. A port up to BUS_MAX bits wide is a
    single bus lane labelled `san`; a wider port fans into BUS_MAX-bit chunk Pins `san__0`, `san__1`,
    … so no interface Pin exceeds the 32-bit limit and a block's box stays compact. Inside a block a
    chunk Pin taps its own (chunked) internal bus directly; at the cpu top a chunk Pin that maps to a
    non-32-aligned slice of the per-bit control word is gathered by a patch-panel fan-in (see
    _emit_fanins). Returns [(label, start_bit, bits_slice)]."""
    if len(bits) <= BUS_MAX:
        return [(san, 0, bits)]
    return [(f"{san}__{c // BUS_MAX}", c, bits[c:c + BUS_MAX])
            for c in range(0, len(bits), BUS_MAX)]


def _tap_lane(loc, lane_bits, net_of, bus_of, comps, wires, toward, buses, fanins=None, face=None):
    """Wire an interface Pin at `loc` carrying `lane_bits` (<= BUS_MAX wide) to the internal nets:
    a bus tap (direct tunnel or slice splitter) when the lane's bits share one internal bus, else a
    plain 1-bit tunnel for a single bit. A multi-bit lane whose bits do NOT share one bus (a chunk
    of the per-bit control word at the cpu top) records a deferred patch-panel fan-in when `fanins`
    is provided — its gathering splitter is placed later in open space (see _emit_fanins) instead
    of colliding with neighbouring pins. Inside a block every multi-bit lane is one bus, so the
    fan-in / stacked-tunnel paths never fire there."""
    if not lane_bits:                          # an unconnected port lane (e.g. a decoder output
        return                                 # that drives nothing yet) — leave the pin floating
    ob = _one_bus(lane_bits, bus_of) if buses else None
    if ob:
        _bus_pin(loc, ob, comps, wires, toward)
    elif len(lane_bits) == 1:
        lab = net_of(lane_bits[0])
        if lab is not None:
            comps.append(tunnel(loc, lab, face))
    elif fanins is not None:
        name = f"net_fanin_{len(fanins)}"
        comps.append(tunnel(loc, name, face, width=len(lane_bits)))
        fanins.append((name, list(lane_bits)))
    else:
        for i, b in enumerate(lane_bits):
            lab = net_of(b)
            if lab is not None:
                comps.append(tunnel((loc[0], loc[1] + i * 10), lab))


def _emit_ports_rails(module, comps, wires, net_of, bus_of, buses, fanins=None):
    """Module ports as interface Pins + the two constant rails. Shared by a block circuit and the
    cpu top. In bus mode each port is one Pin (a >32-bit port fans into BUS_MAX-bit chunk Pins)
    tapping its internal bus; in flat mode each bit is its own 1-bit Pin. `fanins` (cpu top only)
    defers the patch-panel gather for a chunk Pin that maps to per-bit control-word nets."""
    out_x, step = (3200, 40) if buses else (2400, 30)
    in_y = out_y = 120
    for pname, pinfo in module.get("ports", {}).items():
        is_out = pinfo["direction"] == "output"
        bits, san = pinfo["bits"], sanitize(pname)
        lanes = (_port_lanes(bits, san) if buses
                 else [(f"{san}_{i}" if len(bits) > 1 else san, i, [b]) for i, b in enumerate(bits)])
        for label, _start, lane_bits in lanes:
            if not buses and net_of(lane_bits[0]) is None:
                continue
            if is_out:
                loc = (out_x, out_y); out_y += step
            else:
                loc = (40, in_y); in_y += step
            w = len(lane_bits)
            # facing fixes the default-appearance edge (inputs west, outputs east) so a block's
            # subcircuit instance pins line up with instance_pins() in the cpu top.
            face = ("west", "output") if is_out else ("east", None)
            attrs = ([("label", label)] + ([("width", str(w))] if w > 1 else [])
                     + [("facing", face[0])] + ([("type", "output")] if is_out else []))
            comps.append(comp("0", "Pin", loc, attrs))
            _tap_lane(loc, lane_bits, net_of, bus_of, comps, wires,
                      -1 if is_out else 1, buses, fanins, face=("west" if is_out else "east"))
    comps.append(comp("0", "Constant", (40, 40), [("value", "0x0")]))
    comps.append(tunnel((40, 40), "ZERO"))
    comps.append(comp("0", "Constant", (40, 70), [("value", "0x1")]))
    comps.append(tunnel((40, 70), "ONE"))


# --- generate one circuit body: a block's cells + ports + constant rails ------------
def _block_circuit(module, top, buses=True):
    net_of, bitname = build_net_of(module)
    bus_of = build_bus_map(module) if buses else None
    comps, wires, unmapped = [], [], []

    placed = 0
    used_custom = {}                         # cell_type -> spec, for the subcircuit definitions
    for inst, cell in module.get("cells", {}).items():
        spec, custom = CELLS.get(cell["type"]), False
        if spec is None:
            spec = CUSTOM_CHIPS.get(cell["type"])
            if spec is None:
                unmapped.append((inst, cell["type"])); continue
            custom = True
            used_custom[cell["type"]] = spec
        cc, cw = emit_chip(spec, inst, chip_grid(placed, buses), cell["connections"],
                           net_of, bus_of, custom=custom)
        comps += cc; wires += cw
        placed += 1

    _emit_ports_rails(module, comps, wires, net_of, bus_of, buses)

    circuit = (
        f'  <circuit name="{top}">\n'
        f'    <a name="appearance" val="logisim_evolution"/>\n'
        f'    <a name="circuit" val="{top}"/>\n'
        f'    <a name="simulationFrequency" val="0.5"/>\n'
        + "".join(comps) + "".join(wires) + "  </circuit>\n"
    )
    nspl = sum(1 for c in comps if 'name="Splitter"' in c)
    return circuit, used_custom, {"cells": placed, "nets": len(bitname),
                                  "wires": len(wires), "splitters": nspl, "unmapped": unmapped}


def generate(module, top, buses=True):
    """A single block: PREAMBLE + custom-chip subcircuit defs + the block circuit."""
    circuit, used_custom, st = _block_circuit(module, top, buses)
    defs = "".join(emit_custom_subcircuit(s) for s in used_custom.values())
    text = PREAMBLE.format(main=top) + defs + circuit + "</project>\n"
    summary = (f"{st['cells']} cells, {st['nets']} nets, {st['wires']} stub wires"
               + (f", {st['splitters']} splitters" if st['splitters'] else "")
               + (f", {len(used_custom)} custom-chip subcircuits" if used_custom else ""),
               st['unmapped'])
    return text, summary


# --- hierarchy: the cpu top instantiates each block as a subcircuit -----------------
def _subcircuit_name(cell_type):
    """Clean Logisim circuit name for a sub-module instance type (strip yosys $paramod wrap)."""
    if cell_type.startswith("$paramod"):
        parts = cell_type.split("\\")
        return sanitize(parts[1]) if len(parts) > 1 else sanitize(cell_type)
    return sanitize(cell_type)


def instance_pins(loc, in_labels, out_labels, name):
    """Pin coords of a subcircuit instance (default logisim_evolution appearance). `in_labels`/
    `out_labels` are the ordered interface-Pin labels — one box pin each, in the SAME order the
    block emits them (ports order, expanded to _port_lanes, split by direction). Logisim sorts each
    edge's pins by position, which matches that emission order. Returns (in_pos, out_pos, width):
    inputs on the WEST edge (loc.x - width), outputs on the EAST (loc.x), both stepping 20px."""
    maxL = max((len(l) * 8 for l in in_labels), default=0)
    maxR = max((len(l) * 8 for l in out_labels), default=0)
    width = (max(maxL + maxR + 35, len(name) * 8 + 15) // 10) * 10 + 20
    in_pos = [(loc[0] - width, loc[1] + 20 * i) for i in range(len(in_labels))]
    out_pos = [(loc[0], loc[1] + 20 * i) for i in range(len(out_labels))]
    return in_pos, out_pos, width


def _emit_fanins(fanins, net_of, comps, wires, base_y):
    """Patch panel: for each deferred fan-in (a multi-bit chunk Pin whose bits live on per-bit nets)
    emit a fanout-W splitter combining those W per-bit nets (each end tunnelled by its net name)
    into the lane's named multi-bit tunnel. Laid out one column each in open space below the blocks,
    so the W-tall fans never collide with each other or with the (densely packed) instance pins."""
    per_row, col_dx, row_dy = 8, 320, 760                    # a grid so the W-tall fans never touch
    for k, (name, bits) in enumerate(fanins):
        w = len(bits)
        col, row = k % per_row, k // per_row
        sloc = (400 + col * col_dx, base_y + row * row_dy + 20 * w)   # ends fan UP from here
        comb, ends = splitter_ends(sloc, "east", w, BUS_SPACING)
        comps.append(comp("0", "Splitter", sloc,
                          [("incoming", str(w)), ("fanout", str(w)), ("facing", "east"),
                           ("spacing", str(BUS_SPACING))]))
        comps.append(tunnel(comb, name, "west", width=w))    # combined side -> the lane's tunnel
        for i, (ex, ey) in enumerate(ends):
            lab = net_of(bits[i])
            if lab is not None:
                comps.append(tunnel((ex, ey), lab, "west"))  # each bit -> its per-bit net


def _cpu_top_circuit(cpu_mod, design, top, buses=True):
    """The cpu top circuit: sub-module instances (subcircuit boxes) + leaf chips, ports wired to
    inter-block bus tunnels. Returns (circuit_xml, used_custom, submods, stats)."""
    net_of, _ = build_net_of(cpu_mod)
    # The top level carries NO buses: every inter-block signal routes per-bit by net name (leaf
    # chips via flat 1-bit routing, multi-bit block/port pins via spaced patch-panel fan-ins). Bus
    # splitters in this dense, mixed (chips + subcircuit boxes) layout collide — they shorted the IR
    # register's Q[4:8] and the control-word slices. Buses live INSIDE the blocks; the fan-in
    # splitters reconstitute each block's multi-bit pins from the per-bit nets.
    bus_of = None
    comps, wires, unmapped, used_custom, submods, fanins = [], [], [], {}, {}, []
    placed = bcol = brow = 0
    for inst, cell in cpu_mod.get("cells", {}).items():
        t = cell["type"]
        if t in CELLS or t in CUSTOM_CHIPS:                          # a leaf chip
            spec, custom = (CELLS[t], False) if t in CELLS else (CUSTOM_CHIPS[t], True)
            if custom:
                used_custom[t] = spec
            cc, cw = emit_chip(spec, inst, chip_grid(placed, buses), cell["connections"],
                               net_of, bus_of, custom=custom)
            comps += cc; wires += cw; placed += 1
        elif t in design:                                            # a sub-module instance
            name = _subcircuit_name(t)
            submods[name] = (t, design[t])
            ports = design[t]["ports"]
            # the block's interface = one lane (Pin) per port, wide ports chunked — enumerate it the
            # same way the block does, then tap each lane's slice of THIS instance's connection.
            in_lanes, out_lanes = [], []                  # (label, this-instance connection slice)
            for p, pi in ports.items():
                lane_list = out_lanes if pi["direction"] == "output" else in_lanes
                conn = cell["connections"].get(p, [])
                for label, start, lane_bits in _port_lanes(pi["bits"], sanitize(p)):
                    lane_list.append((label, conn[start:start + len(lane_bits)]))
            loc = (900 + bcol * 1200, 240 + brow * 900)
            bcol = (bcol + 1) % 3
            if bcol == 0:
                brow += 1
            comps.append(comp("", name, loc, [("label", sanitize(inst))]))
            in_pos, out_pos, _w = instance_pins(loc, [l[0] for l in in_lanes],
                                                [l[0] for l in out_lanes], name)
            for (_lab, lane_conn), pc in zip(in_lanes, in_pos):       # box inputs (west edge)
                _tap_lane(pc, lane_conn, net_of, bus_of, comps, wires, -1, buses, fanins, face="east")
            for (_lab, lane_conn), pc in zip(out_lanes, out_pos):     # box outputs (east edge)
                _tap_lane(pc, lane_conn, net_of, bus_of, comps, wires, 1, buses, fanins, face="west")
        else:
            unmapped.append((inst, t))
    _emit_ports_rails(cpu_mod, comps, wires, net_of, bus_of, buses, fanins)
    _emit_fanins(fanins, net_of, comps, wires, 240 + (brow + 1) * 900 + 200)
    circuit = (f'  <circuit name="{top}">\n    <a name="appearance" val="logisim_evolution"/>\n'
               f'    <a name="circuit" val="{top}"/>\n    <a name="simulationFrequency" val="0.5"/>\n'
               + "".join(comps) + "".join(wires) + "  </circuit>\n")
    return circuit, used_custom, submods, {"cells": placed + len(submods), "unmapped": unmapped}


def generate_cpu(design, top="cpu", buses=True):
    """Whole hierarchical CPU: custom-chip subcircuits + one subcircuit per block + the cpu top."""
    cpu_circuit, used_custom, submods, st = _cpu_top_circuit(design[top], design, top, buses)
    blocks = []
    for name, (t, mod) in submods.items():
        body, cust, _bst = _block_circuit(mod, name, buses)
        blocks.append(body)
        used_custom.update(cust)
    defs = "".join(emit_custom_subcircuit(s) for s in used_custom.values())
    text = PREAMBLE.format(main=top) + defs + "".join(blocks) + cpu_circuit + "</project>\n"
    summary = (f"{st['cells']} cells, {len(submods)} block subcircuits, "
               f"{len(used_custom)} custom chips", st['unmapped'])
    return text, summary


# --- circ parsing -------------------------------------------------------------------
_PT = re.compile(r"-?\d+")


def _pt(s):
    """Parse a Logisim '(x,y)' coordinate; None if malformed (hand-corrupted file)."""
    nums = _PT.findall(s or "")
    if len(nums) < 2:
        return None
    return (int(nums[0]), int(nums[1]))


class Comp:
    __slots__ = ("lib", "name", "loc", "attrs")

    def __init__(self, lib, name, loc, attrs):
        self.lib, self.name, self.loc, self.attrs = lib, name, loc, attrs


def parse_circ(path, top):
    """Read a .circ -> (comps, wires) for the circuit named `top`. Stdlib XML only."""
    import xml.etree.ElementTree as ET
    root = ET.parse(path).getroot()
    circ = None
    for c in root.findall("circuit"):
        if c.get("name") == top:
            circ = c; break
    if circ is None:
        raise SystemExit(f"reconcile: no <circuit name=\"{top}\"> in {path}")
    comps, wires, malformed = [], [], 0
    for e in circ:
        if e.tag == "comp":
            loc = _pt(e.get("loc"))
            if loc is None:
                malformed += 1; continue
            attrs = {a.get("name"): a.get("val") for a in e.findall("a")}
            comps.append(Comp(e.get("lib"), e.get("name"), loc, attrs))
        elif e.tag == "wire":
            a, b = _pt(e.get("from")), _pt(e.get("to"))
            if a is None or b is None:
                malformed += 1; continue
            wires.append((a, b))
    return comps, wires, malformed


# --- electrical model: union-find over wires + same-named tunnels -------------------
class DSU:
    def __init__(self):
        self.p = {}

    def find(self, x):
        self.p.setdefault(x, x)
        r = x
        while self.p[r] != r:
            r = self.p[r]
        while self.p[x] != r:
            self.p[x], x = r, self.p[x]
        return r

    def union(self, a, b):
        self.p[self.find(a)] = self.find(b)


def _int(v, default):
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def _point_dsu(comps, wires, seed_nodes):
    """Point-level (bundle) connectivity the way Logisim actually connects nodes: a wire is an
    equipotential, so EVERY node lying on it — endpoint OR strictly interior — joins that net.
    This models T-junctions (a wire endpoint or a tunnel landing mid-span of another wire) and
    collinear overlaps, which endpoint-only unioning silently misses (a false OPEN on a correct
    rewire and, worse, a missed SHORT). A pure crossing with no node at the cross point stays
    unconnected, exactly as in Logisim. Same-named tunnels join (bit-for-bit, handled by the
    bit layer above). Splitters are NOT a straight bundle join — they remap bits — so their end
    points are seeded as nodes here but the bit remapping happens in electrical_model().

    `seed_nodes` are extra connection points (chip DIP pins, splitter ends) so a wire passing
    over one connects to it. Nodes are bucketed by row/column so each wire scans only its line."""
    dsu = DSU()
    nodes = set(seed_nodes)
    for a, b in wires:
        nodes.add(a); nodes.add(b)
    for c in comps:
        if c.name in ("Tunnel", "Pin", "Constant", "Probe", "Clock"):
            nodes.add(c.loc)
    by_y, by_x = defaultdict(list), defaultdict(list)
    for n in nodes:
        by_y[n[1]].append(n); by_x[n[0]].append(n)
    for a, b in wires:
        (ax, ay), (bx, by_) = a, b
        if ay == by_:                              # horizontal: union nodes on this row span
            lo, hi = sorted((ax, bx))
            for n in by_y.get(ay, ()):
                if lo <= n[0] <= hi:
                    dsu.union(a, n)
        elif ax == bx:                             # vertical: union nodes on this column span
            lo, hi = sorted((ay, by_))
            for n in by_x.get(ax, ()):
                if lo <= n[1] <= hi:
                    dsu.union(a, n)
        else:                                      # diagonal (Logisim rarely emits) — endpoints
            dsu.union(a, b)
    for c in comps:
        if c.name == "Tunnel":
            lbl = c.attrs.get("label")
            if lbl:
                dsu.union(c.loc, ("TUN", lbl))
    return dsu


def electrical_nets(comps, wires, chip_pins):
    """Back-compat 1-bit view: the point-level (bundle) partition + a splitter count. The
    bit-aware model used by reconcile is electrical_model()."""
    return _point_dsu(comps, wires, chip_pins), sum(1 for c in comps if c.name == "Splitter")


def splitter_ends(loc, facing, fanout, spacing=1, appear="left"):
    """Absolute (combined_pt, [split_pt_0..split_pt_{fanout-1}]) for a Logisim Evolution 4.1.0
    Splitter. `end[i]` is the end the bitK attr names with val=i. A transcription of the engine's
    own SplitterParameters + Splitter.configureComponent, ground-truth-verified against Logisim's
    headless simulator for every facing, spacing 1/3, and appear left/right/center.

    The combined end (the wide bus, width = `incoming`) is always at `loc` exactly. The split-end
    fan steps away by `spacing*10` px; `appear` shifts the fan sideways relative to the spine."""
    x0, y0 = loc
    spacing = _int(spacing, 1)                        # tolerate a hand-edited / junk value
    justify = 0 if appear in ("center", "legacy") else (1 if appear == "right" else -1)  # left dflt
    width, gap = 20, spacing * 10
    if facing in ("north", "south"):
        m = 1 if facing == "north" else -1
        if justify == 0:
            dx0 = gap * ((fanout + 1) // 2 - 1)
        else:
            dx0 = -10 if (m * justify < 0) else (10 + gap * (fanout - 1))
        dy0, ddx, ddy = -m * width, -gap, 0
    else:                                            # east / west
        m = -1 if facing == "west" else 1
        dx0 = m * width
        if justify == 0:
            dy0 = -gap * (fanout // 2)
        else:
            dy0 = 10 if (m * justify > 0) else -(10 + gap * (fanout - 1))
        ddx, ddy = 0, gap
    ends = [(x0 + dx0 + i * ddx, y0 + dy0 + i * ddy) for i in range(fanout)]
    return (x0, y0), ends


def splitter_spec(comp):
    """Parse a Splitter -> (combined_pt, ends, incoming) where ends[g] = (split_pt_g, [combined
    bit indices routed to group g, ascending = local bit order]). None if it can't be modeled.

    bitK attr = which split-end group combined bit K goes to; 'none' = unrouted; absent = the
    default consecutive distribution (group floor(K*F/N))."""
    a = comp.attrs
    N = _int(a.get("incoming", a.get("width")), None)
    F = _int(a.get("fanout"), None)
    if N is None or F is None or F < 1:
        return None
    facing = (a.get("facing", "east") or "east").lower()
    combined_pt, end_pts = splitter_ends(comp.loc, facing, F,
                                         _int(a.get("spacing"), 1), a.get("appear", "left"))
    if combined_pt is None or not end_pts:
        return None
    groups = [[] for _ in range(F)]
    for k in range(N):
        v = a.get(f"bit{k}")
        if v is None:
            g = min(k, F - 1)        # Logisim's .circ-load default (SplitterFactory); real
        elif v == "none":            # files carry explicit bitK for any non-trivial split
            continue
        else:
            g = _int(v, -1)
        if 0 <= g < F:
            groups[g].append(k)
    return combined_pt, [(end_pts[g], groups[g]) for g in range(F)], N


def electrical_model(comps, wires, chip_pins):
    """Bit-level electrical model. A wire/tunnel carries a *bundle*; a splitter remaps individual
    bits between a combined bus and its fanout ends. Returns (root, splitters, unparsed,
    width_mismatch): root(point, bit=0) -> a hashable net id for that bit at that connection
    point; splitters = count seen; unparsed = splitters we couldn't model; width_mismatch =
    [(bundle, w1, w2)] where two declared widths collide on one bundle net (a real DRC error)."""
    splitters = [c for c in comps if c.name == "Splitter"]
    specs, unparsed, end_nodes = [], 0, []
    for c in splitters:
        sp = splitter_spec(c)
        if sp is None:
            unparsed += 1; continue
        specs.append(sp)
        end_nodes.append(sp[0])
        end_nodes.extend(ep for ep, _bits in sp[1])

    pdsu = _point_dsu(comps, wires, list(chip_pins) + end_nodes)

    bw, width_mismatch = {}, []                    # bundle root -> declared width
    def setw(pt, w):
        r = pdsu.find(pt)
        cur = bw.get(r)
        if cur is None:
            bw[r] = w
        elif cur != w:
            width_mismatch.append((r, cur, w))
    for p in chip_pins:
        setw(p, 1)
    for c in comps:
        if c.name == "Tunnel":
            lbl = c.attrs.get("label")
            if lbl:
                setw(("TUN", lbl), _int(c.attrs.get("width"), 1))
        elif c.name in ("Pin", "Constant", "Probe"):
            setw(c.loc, _int(c.attrs.get("width"), 1))
    for comb_pt, ends, n in specs:
        setw(comb_pt, n)
        for ep, bits in ends:
            setw(ep, len(bits))

    bdsu = DSU()                                    # over (bundle root, bit)
    for comb_pt, ends, _n in specs:
        cr = pdsu.find(comb_pt)
        for ep, bits in ends:
            er = pdsu.find(ep)
            for local, k in enumerate(bits):        # ascending k = local bit order
                bdsu.union((cr, k), (er, local))

    def root(pt, bit=0):
        return bdsu.find((pdsu.find(pt), bit))

    return root, len(splitters), unparsed, width_mismatch


# --- reconcile: LVS diff of the drawn .circ against the HDL golden netlist ----------
class Findings:
    def __init__(self):
        self.matched = []        # cid
        self.missing = []        # (cid, inst, type, part)
        self.stale = []          # label
        self.typedrift = []      # (label, drawn_part, want_part)
        self.dup = []            # label
        self.unmapped = []       # (inst, type) — no Logisim mapping at all
        self.opens = []          # (net, [groups of pin-names])
        self.shorts = []         # (elec descr, [nets], [pin-names])
        self.undriven = []       # (net, pin-name)
        self.ok_nets = 0
        self.splitters = 0
        self.splitter_unparsed = 0
        self.width_mismatch = []  # (bundle, w1, w2) — incompatible widths on one net
        self.malformed = 0


def _pinname(ep, golden_pinmeta):
    if ep[0] == "PORT":
        return f"port:{ep[1]}"
    if ep[0] == "CONST":
        return f"const@{ep[1]}"
    cid, dip = ep
    return golden_pinmeta.get(ep, f"{cid}.pin{dip}")


def reconcile(module, top, circ_path):
    net_of, _ = build_net_of(module)
    f = Findings()
    comps, wires, f.malformed = parse_circ(circ_path, top)
    chip_pins = []                       # every drawn chip's DIP pins, for wire-over-pin taps
    for c in comps:
        cell = PART2CELL.get(c.name)
        if cell:
            np = cell[1]["pins"]
            facing = c.attrs.get("facing", "south")
            for dip in range(1, np + 1):
                chip_pins.append(pin_xy(c.loc, dip, np, facing))
        elif c.name in PART2CUSTOM:                      # a custom-chip subcircuit instance
            np = PART2CUSTOM[c.name][1]["pins"]
            for dip in range(1, np + 1):
                chip_pins.append(custom_pin_xy(c.loc, dip, np))
    bitroot, f.splitters, f.splitter_unparsed, f.width_mismatch = \
        electrical_model(comps, wires, chip_pins)

    # golden side: cells + the (cid,dip)->net map, plus a human pin name per endpoint
    golden_pins = {}                 # cid -> list[(dip, net)]
    golden_part = {}                 # cid -> expected Logisim part name
    golden_custom = {}               # cid -> is it a custom-chip subcircuit?
    cid2inst = {}
    pinmeta = {}                     # (cid,dip) -> "cid.port[idx]"
    for inst, cell in module.get("cells", {}).items():
        spec, custom = CELLS.get(cell["type"]), False
        if spec is None:
            spec = CUSTOM_CHIPS.get(cell["type"])
            if spec is None:
                f.unmapped.append((inst, cell["type"])); continue
            custom = True
        cid = sanitize(inst)
        cid2inst[cid] = inst
        golden_part[cid] = spec["name"]
        golden_custom[cid] = custom
        conns = cell["connections"]
        plist = []
        for port, dips in spec["map"].items():
            bits = conns.get(port, [])
            for idx, dip in enumerate(dips):
                if idx < len(bits):
                    net = net_of(bits[idx])
                    if net is not None:
                        plist.append((dip, net, spec["pins"]))
                        pinmeta[(cid, dip)] = f"{cid}.{port}[{idx}]"
        golden_pins[cid] = plist

    # drawn side: chips identified by label
    label_to_comp = {}
    seen = set()
    for c in comps:
        if c.name in PART2CELL or c.name in PART2CUSTOM:   # a TTL DIP or custom-chip subcircuit
            lbl = c.attrs.get("label")
            if not lbl:
                continue
            if lbl in label_to_comp and lbl not in f.dup:
                f.dup.append(lbl)
            label_to_comp.setdefault(lbl, c)
            seen.add(lbl)

    golden_ids = set(golden_pins)
    for cid in sorted(golden_ids):
        if cid not in label_to_comp:
            f.missing.append((cid, cid2inst[cid], None, golden_part[cid]))
    for lbl in sorted(seen):
        if lbl not in golden_ids:
            f.stale.append(lbl)
    for cid in sorted(golden_ids & seen):
        drawn = label_to_comp[cid].name
        if drawn != golden_part[cid]:
            f.typedrift.append((cid, drawn, golden_part[cid]))

    # endpoints: (golden_net, elec_root, is_const) for everything we can compare
    endpoints = {}
    for cid in sorted(golden_ids & seen):
        if cid in f.dup or label_to_comp[cid].name != golden_part[cid]:
            continue
        c = label_to_comp[cid]
        facing = c.attrs.get("facing", "south")
        for dip, net, npins in golden_pins[cid]:
            pt = (custom_pin_xy(c.loc, dip, npins) if golden_custom[cid]
                  else pin_xy(c.loc, dip, npins, facing))
            endpoints[(cid, dip)] = (net, bitroot(pt), False)

    # module-port Pins. The generator labels each interface Pin by its port: `san` (a 1-bit or
    # whole-bus port), `san__c` (chunk c of a >32-bit port, bits c*BUS_MAX..), or `san_i` (a flat
    # per-bit Pin). Resolve the label to (port, base bit) and check EVERY bit the Pin carries.
    port_bits = {sanitize(p): [net_of(b) for b in pinfo["bits"]]
                 for p, pinfo in module.get("ports", {}).items()}

    def _resolve_pin(lbl):
        if lbl in port_bits:                                 # whole-port Pin: bits 0..w-1
            return lbl, 0
        head, sep, tail = lbl.rpartition("__")               # chunk Pin san__c
        if sep and head in port_bits and tail.isdigit():
            return head, int(tail) * BUS_MAX
        head, sep, tail = lbl.rpartition("_")                # flat per-bit Pin san_i
        if sep and head in port_bits and tail.isdigit():
            return head, int(tail)
        return None

    for c in comps:
        if c.name == "Pin":
            lbl, w = c.attrs.get("label"), _int(c.attrs.get("width"), 1)
            r = _resolve_pin(lbl) if lbl else None
            if r:
                san, base = r
                nets = port_bits[san]
                for k in range(w):
                    if base + k < len(nets) and nets[base + k] is not None:
                        endpoints[("PORT", lbl, k)] = (nets[base + k], bitroot(c.loc, k), False)
        elif c.name == "Constant":
            val = c.attrs.get("value", "0x1")
            try:
                gnet = "ZERO" if int(val, 0) == 0 else "ONE"
            except ValueError:
                gnet = "ONE"
            endpoints[("CONST", c.loc)] = (gnet, bitroot(c.loc), True)

    # --- LVS: compare the golden partition (by net) to the drawn one (by elec root) ---
    by_net = defaultdict(list)       # golden net -> [ep]
    by_root = defaultdict(list)      # elec root  -> [ep]
    for ep, (net, root, isc) in endpoints.items():
        by_net[net].append(ep)
        by_root[root].append(ep)

    RAILS = ("ZERO", "ONE")
    # SHORT: a drawn net carrying endpoints from >=2 distinct golden nets
    for root, eps in by_root.items():
        nets = sorted({endpoints[e][0] for e in eps})
        if len(nets) > 1:
            f.shorts.append((nets, [_pinname(e, pinmeta) for e in eps]))
    # OPEN: a (non-rail) golden net whose endpoints land in >=2 drawn nets
    for net, eps in by_net.items():
        if net in RAILS or len(eps) < 2:
            continue
        roots = defaultdict(list)
        for e in eps:
            roots[endpoints[e][2] and "x" or endpoints[e][1]].append(e)
        groups = defaultdict(list)
        for e in eps:
            groups[endpoints[e][1]].append(_pinname(e, pinmeta))
        if len(groups) > 1:
            f.opens.append((net, list(groups.values())))
        else:
            f.ok_nets += 1
    # rails: every consumer must share a drawn net with a constant of that value
    for rail in RAILS:
        consumers = [e for e in by_net.get(rail, []) if not endpoints[e][2]]
        for e in consumers:
            root = endpoints[e][1]
            if not any(endpoints[o][2] and endpoints[o][0] == rail for o in by_root[root]):
                f.undriven.append((rail, _pinname(e, pinmeta)))
    f.ok_nets += sum(1 for net, eps in by_net.items()
                     if net not in RAILS and len(eps) >= 2
                     and len({endpoints[e][1] for e in eps}) == 1)
    f.matched = sorted(golden_ids & seen)
    return f


def report(top, circ_path, f):
    err = bool(f.missing or f.opens or f.shorts or f.undriven or f.dup or f.width_mismatch)
    print(f"RECONCILE {top}   ({circ_path} vs HDL)")
    print(f"  chips:  {len(f.matched)} matched, {len(f.missing)} missing, "
          f"{len(f.stale)} stale, {len(f.typedrift)} type-changed")
    print(f"  nets:   {f.ok_nets} ok, {len(f.shorts)} short, "
          f"{len(f.opens)} open, {len(f.undriven)} undriven"
          + (f", {len(f.width_mismatch)} width-mismatch" if f.width_mismatch else "")
          + (f"; {f.splitters} splitter(s)" if f.splitters else ""))
    if f.dup:
        print("  AMBIGUOUS — duplicate chip labels (copy-paste?):")
        for l in f.dup:
            print(f"    {l}")
    if f.missing:
        print("  MISSING (in HDL, not drawn) — `--insert` to add:")
        for cid, inst, _t, part in f.missing:
            print(f"    {cid}  -> {part}")
    if f.typedrift:
        print("  TYPE-CHANGED (label kept, part differs):")
        for cid, drawn, want in f.typedrift:
            print(f"    {cid}: drawn {drawn}, HDL wants {want}")
    if f.shorts:
        print("  SHORT (one drawn net merges distinct HDL nets):")
        for nets, pins in f.shorts:
            print(f"    {' + '.join(nets)}  <-  {', '.join(pins)}")
    if f.opens:
        print("  OPEN (HDL net split across drawn nets / floating pin):")
        for net, groups in f.opens:
            print(f"    {net}: " + "  ||  ".join(", ".join(g) for g in groups))
    if f.undriven:
        print("  UNDRIVEN (constant consumer not tied to its rail):")
        for rail, pin in f.undriven:
            print(f"    {pin} expects {rail}")
    if f.stale:
        print("  STALE (drawn, absent from HDL) — warning only:")
        for l in f.stale:
            print(f"    {l}")
    if f.unmapped:
        print("  UNMAPPED HDL cells (no Logisim part yet — not checked):")
        for inst, t in f.unmapped:
            print(f"    {inst}: {t}")
    if f.width_mismatch:
        print("  WIDTH MISMATCH (incompatible bus widths on one drawn net):")
        for _bundle, w1, w2 in f.width_mismatch:
            print(f"    a net carries both {w1}-bit and {w2}-bit endpoints")
    if f.splitter_unparsed:
        print(f"  note: {f.splitter_unparsed} splitter(s) not modeled (geometry pending) — "
              f"nets through them are unverified.")
    if f.malformed:
        print(f"  note: skipped {f.malformed} malformed element(s) (bad loc/coord).")
    print("  RESULT:", "DRIFT" if (err or f.stale) else "IN SYNC")
    return 1 if err else 0


# --- insert: additively splice missing chips in, without disturbing the file --------
def insert_missing(module, top, circ_path, f):
    net_of, _ = build_net_of(module)
    cells = module.get("cells", {})
    text = open(circ_path).read()
    # match the drawing's style: bus break-outs if it already has splitters, else 1-bit
    bus_of = build_bus_map(module) if 'name="Splitter"' in text else None
    dx, dy = (680, 520) if bus_of else (500, 460)
    # find a free row below everything currently drawn
    ys = [int(m) for m in re.findall(r'loc="\(\d+,(\d+)\)"', text)] or [0]
    base = ((max(ys) // dy) + 1) * dy + 240
    blocks = []
    for i, (cid, inst, _t, _part) in enumerate(f.missing):
        spec = CELLS[cells[inst]["type"]]
        loc = (380 + (i % 4) * dx, base + (i // 4) * dy)
        cc, cw = emit_chip(spec, inst, loc, cells[inst]["connections"], net_of, bus_of)
        blocks.append("".join(cc) + "".join(cw))
    addition = "".join(blocks)
    # splice before the circuit's closing tag, tolerating whatever indentation Logisim
    # wrote on its last save (text edit only — never reserialize the user's file).
    idx = text.rfind("</circuit>")
    if idx < 0:
        raise SystemExit(f"insert: no </circuit> in {circ_path}")
    line_start = text.rfind("\n", 0, idx) + 1
    out = text[:line_start] + addition + text[line_start:]
    open(circ_path, "w").write(out)
    return [cid for cid, *_ in f.missing]


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
      <a name="type" val="output"/>
    </tool>
  </toolbar>
'''


def main():
    args = sys.argv[1:]
    if args and args[0] in ("generate", "reconcile"):
        sub, rest = args[0], args[1:]
    else:
        sub, rest = "generate", args            # legacy positional == generate
    flags = {a for a in rest if a.startswith("--")}
    pos = [a for a in rest if not a.startswith("--")]
    if len(pos) < 3:
        raise SystemExit(__doc__)
    netlist_path, top, circ_path = pos[0], pos[1], pos[2]
    design = json.load(open(netlist_path))["modules"]
    module = design[top]
    # hierarchy if any cell instantiates another NON-LEAF module in the design — a real sub-module,
    # not a leaf cell. (read_verilog -lib makes every 74-series / memory cell a blackbox module that
    # also shows up in `design`, so we must exclude the CELLS / CUSTOM_CHIPS leaf parts explicitly.)
    hier = any(c["type"] in design and c["type"] != top
               and c["type"] not in CELLS and c["type"] not in CUSTOM_CHIPS
               for c in module.get("cells", {}).values())

    if sub == "generate":
        if hier:
            text, (summary, unmapped) = generate_cpu(design, top, buses="--flat" not in flags)
        else:
            text, (summary, unmapped) = generate(module, top, buses="--flat" not in flags)
        open(circ_path, "w").write(text)
        print(f"logisim: wrote {circ_path}  ({summary})")
        if unmapped:
            print("  UNMAPPED cells (no Logisim mapping yet):")
            for inst, t in unmapped:
                print(f"    {inst}: {t}")
        return

    f = reconcile(module, top, circ_path)
    rc = report(top, circ_path, f)
    if "--insert" in flags and f.missing:
        added = insert_missing(module, top, circ_path, f)
        print(f"  inserted {len(added)} chip(s): {', '.join(added)}")
        rc = 0
    sys.exit(rc)


if __name__ == "__main__":
    main()
