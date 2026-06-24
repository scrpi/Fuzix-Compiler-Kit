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


# --- XML emit helpers ---------------------------------------------------------------
def comp(lib, name, loc, attrs=()):
    a = "".join(f'\n    <a name="{k}" val="{v}"/>' for k, v in attrs)
    return f'  <comp lib="{lib}" loc="({loc[0]},{loc[1]})" name="{name}">{(a + chr(10) + "  ") if a else ""}</comp>\n'


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
BUS_SPACING = 2                  # splitter `spacing` attr -> fanout pitch = 20px
BUS_GAP = BUS_SPACING * 10       # vertical pitch of a bus group's dogleg rows (= fanout pitch)
BUS_INTER = TUN_DY               # vertical gap between items (bus group / 1-bit) in a column


def build_bus_map(module):
    """bit -> (busname, position, width): each net bit's WIDEST containing multi-bit signal,
    so an overlapping field (a slice of a wider port) resolves to the encompassing bus and
    every endpoint of that bit agrees on one bus label + width. Empty when no buses exist."""
    bus_of = {}
    sources = list(module.get("netnames", {}).items()) + list(module.get("ports", {}).items())
    for nm, info in sorted(sources, key=lambda kv: -len(kv[1]["bits"])):   # widest first
        bits = info["bits"]
        if len(bits) < 2:
            continue
        san = sanitize(nm)
        for i, b in enumerate(bits):
            if isinstance(b, int):
                bus_of.setdefault(b, (san, i, len(bits)))
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
def emit_chip(spec, inst, loc, conns, net_of, bus_of=None):
    """Return (comp_lines, wire_lines) for one chip at `loc`. Shared by generate + insert.
    1-bit mode (bus_of falsy): each pin -> its own 1-bit tunnel. Bus mode: pins on a multi-bit
    net are grouped and broken out of a bus tunnel via a splitter."""
    comps = [comp(spec["lib"], spec["name"], loc,
                  [("label", sanitize(inst)), ("facing", "south")])]
    wires = []
    west, east = [], []
    for port, pins in spec["map"].items():
        bits = conns.get(port, [])
        for idx, dip in enumerate(pins):
            if idx < len(bits):
                px, py = pin_xy(loc, dip, spec["pins"])
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


# --- generate: a fresh .circ (overwrites) -------------------------------------------
def generate(module, top, buses=True):
    net_of, bitname = build_net_of(module)
    bus_of = build_bus_map(module) if buses else None
    comps, wires, unmapped = [], [], []

    placed = 0
    for inst, cell in module.get("cells", {}).items():
        spec = CELLS.get(cell["type"])
        if spec is None:
            unmapped.append((inst, cell["type"])); continue
        cc, cw = emit_chip(spec, inst, chip_grid(placed, buses), cell["connections"],
                           net_of, bus_of)
        comps += cc; wires += cw
        placed += 1

    # module ports: a 1-bit Pin per bit (1-bit mode), or one N-bit Pin per bus (bus mode),
    # each co-located with its net/bus tunnel
    out_x, step = (3200, 40) if buses else (2400, 30)
    in_y = out_y = 120
    for pname, pinfo in module.get("ports", {}).items():
        is_out = pinfo["direction"] == "output"
        bits, san = pinfo["bits"], sanitize(pname)
        bi = [bus_of.get(b) if isinstance(b, int) else None for b in bits] if buses else []
        if buses and len(bits) > 1 and bi[0] and all(x and x[0] == bi[0][0] for x in bi):
            bn, _, W = bi[0]                          # all the port's bits share one bus
            pos = [x[1] for x in bi]
            loc = (out_x, out_y) if is_out else (40, in_y)
            comps.append(comp("0", "Pin", loc, [("label", san), ("width", str(len(bits)))]
                              + ([("output", "true")] if is_out else [])))
            if len(bits) == W and pos == list(range(W)):
                comps.append(tunnel(loc, bn, width=W))           # the port IS the whole bus
            else:                                                # the port is a slice -> tap it
                sx = loc[0] + (-160 if is_out else 160)
                comb, ends = splitter_ends((sx, loc[1]), "east", 1, BUS_SPACING)
                comps.append(comp("0", "Splitter", (sx, loc[1]),
                                  [("incoming", str(W)), ("fanout", "1"), ("facing", "east"),
                                   ("spacing", str(BUS_SPACING))]
                                  + [(f"bit{p}", "0") for p in pos]
                                  + [(f"bit{k}", "none") for k in range(W) if k not in pos]))
                comps.append(tunnel(comb, bn, width=W))
                ex, ey = ends[0]
                wires.append(wire(loc, (ex, loc[1])))
                if ey != loc[1]:
                    wires.append(wire((ex, loc[1]), (ex, ey)))
            if is_out:
                out_y += step
            else:
                in_y += step
            continue
        for i, b in enumerate(bits):
            label = net_of(b)
            if label is None:
                continue
            lbl = f"{san}_{i}" if len(bits) > 1 else san
            if is_out:
                loc = (out_x, out_y); out_y += step
                comps.append(comp("0", "Pin", loc, [("label", lbl), ("output", "true")]))
            else:
                loc = (40, in_y); in_y += step
                comps.append(comp("0", "Pin", loc, [("label", lbl)]))
            comps.append(tunnel(loc, label))

    # the two constant rails
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
    text = PREAMBLE.format(main=top) + circuit + "</project>\n"
    nspl = sum(1 for c in comps if 'name="Splitter"' in c)
    summary = (f"{placed} cells, {len(bitname)} nets, {len(wires)} stub wires"
               + (f", {nspl} splitters" if nspl else ""), unmapped)
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
    bitroot, f.splitters, f.splitter_unparsed, f.width_mismatch = \
        electrical_model(comps, wires, chip_pins)

    # golden side: cells + the (cid,dip)->net map, plus a human pin name per endpoint
    golden_pins = {}                 # cid -> list[(dip, net)]
    golden_part = {}                 # cid -> expected Logisim part name
    cid2inst = {}
    pinmeta = {}                     # (cid,dip) -> "cid.port[idx]"
    for inst, cell in module.get("cells", {}).items():
        spec = CELLS.get(cell["type"])
        if spec is None:
            f.unmapped.append((inst, cell["type"])); continue
        cid = sanitize(inst)
        cid2inst[cid] = inst
        golden_part[cid] = spec["name"]
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
        if c.name in PART2CELL:                 # a TTL chip we emit
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
            pt = pin_xy(c.loc, dip, npins, facing)
            endpoints[(cid, dip)] = (net, bitroot(pt), False)

    # module-port Pins (the generator labels them port / port_i)
    port_nets = {}
    for pname, pinfo in module.get("ports", {}).items():
        bits, san = pinfo["bits"], sanitize(pname)
        for i, b in enumerate(bits):
            net = net_of(b)
            if net is None:
                continue
            port_nets[f"{san}_{i}" if len(bits) > 1 else san] = net
    for c in comps:
        if c.name == "Pin":
            lbl = c.attrs.get("label")
            if lbl in port_nets:
                endpoints[("PORT", lbl)] = (port_nets[lbl], bitroot(c.loc), False)
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
      <a name="output" val="true"/>
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
    module = json.load(open(netlist_path))["modules"][top]

    if sub == "generate":
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
