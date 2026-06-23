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
  logisim.py generate  <netlist.json> <TOP> <out.circ>
  logisim.py reconcile <netlist.json> <TOP> <circ> [--insert]
  logisim.py <netlist.json> <TOP> <out.circ>            # legacy: == generate

v2 handles all-TTL blocks (control_word_decoder, microsequencer). Splitters / multi-bit
buses / the memory components / rotated facings come next.
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


def tunnel(loc, label, facing=None):
    attrs = [("label", label)] + ([("facing", facing)] if facing else [])
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


# --- one chip: SOUTH-facing part, pins doglegged to an aligned tunnel column ---------
def emit_chip(spec, inst, loc, conns, net_of):
    """Return (comp_lines, wire_lines) for one chip at `loc`. Shared by generate + insert.
    Each side's pins (20px apart) fan to a single vertical tunnel column via an S-dogleg:
    pin -> horizontal -> vertical jog (its own channel) -> horizontal -> tunnel."""
    comps = [comp(spec["lib"], spec["name"], loc,
                  [("label", sanitize(inst)), ("facing", "south")])]
    wires = []
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
        side.sort()                          # top -> bottom
        m = len(side)
        ty0 = int(round((side[0][0] + side[-1][0]) / 2 - TUN_DY * (m - 1) / 2, -1))
        if (ty0 - loc[1]) % 20 != 0:          # keep the column on the even grid (see TUN_DY)
            ty0 -= 10
        colx = loc[0] + sign * (30 + STUB + m * CH_STEP + 20)
        face = "east" if sign < 0 else "west"       # face the chip (flipped 180)
        # Jog-channel order: the fan diverges from the centre, so a single monotonic order
        # crosses. Nest from the extremes inward — top & bottom pins turn NEAREST the chip,
        # the centre pin FARTHEST: rank = [0, m-1, 1, m-2, ...]. Crossing-free.
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
    return comps, wires


def chip_grid(idx):
    return (380 + (idx % 4) * 500, 240 + (idx // 4) * 460)


# --- generate: a fresh .circ (overwrites) -------------------------------------------
def generate(module, top):
    net_of, bitname = build_net_of(module)
    comps, wires, unmapped = [], [], []

    placed = 0
    for inst, cell in module.get("cells", {}).items():
        spec = CELLS.get(cell["type"])
        if spec is None:
            unmapped.append((inst, cell["type"])); continue
        cc, cw = emit_chip(spec, inst, chip_grid(placed), cell["connections"], net_of)
        comps += cc; wires += cw
        placed += 1

    # module ports: one 1-bit Pin per bit, co-located with its net tunnel
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
    summary = (f"{placed} cells, {len(bitname)} nets, {len(wires)} stub wires", unmapped)
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


def electrical_nets(comps, wires, chip_pins):
    """Build the electrical partition the way Logisim actually connects nodes: a wire is an
    equipotential, so EVERY node lying on it — endpoint OR strictly interior — joins that net.
    This models T-junctions (a wire endpoint or a tunnel landing mid-span of another wire) and
    collinear overlaps, which endpoint-only unioning silently misses (both a false OPEN on a
    correct rewire and, worse, a missed SHORT). A pure crossing with no node at the cross point
    stays unconnected, exactly as in Logisim. Returns (dsu, splitters_present).

    `chip_pins` is every drawn chip's DIP-pin coordinate, so a wire passing over a pin connects
    to it. Nodes are bucketed by row/column, so each wire only scans its own line."""
    dsu = DSU()
    nodes = set()
    for a, b in wires:
        nodes.add(a); nodes.add(b)
    for c in comps:
        if c.name in ("Tunnel", "Pin", "Constant", "Probe", "Clock"):
            nodes.add(c.loc)
    nodes.update(chip_pins)
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
    splitters = 0
    for c in comps:
        if c.name == "Tunnel":
            lbl = c.attrs.get("label")
            if lbl:
                dsu.union(c.loc, ("TUN", lbl))     # same-named tunnels join (bit-level: v3)
        elif c.name == "Splitter":
            splitters += 1
    return dsu, splitters


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
    dsu, f.splitters = electrical_nets(comps, wires, chip_pins)

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
            endpoints[(cid, dip)] = (net, dsu.find(pt), False)

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
                endpoints[("PORT", lbl)] = (port_nets[lbl], dsu.find(c.loc), False)
        elif c.name == "Constant":
            val = c.attrs.get("value", "0x1")
            try:
                gnet = "ZERO" if int(val, 0) == 0 else "ONE"
            except ValueError:
                gnet = "ONE"
            endpoints[("CONST", c.loc)] = (gnet, dsu.find(c.loc), True)

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
    err = bool(f.missing or f.opens or f.shorts or f.undriven or f.dup)
    print(f"RECONCILE {top}   ({circ_path} vs HDL)")
    print(f"  chips:  {len(f.matched)} matched, {len(f.missing)} missing, "
          f"{len(f.stale)} stale, {len(f.typedrift)} type-changed")
    print(f"  nets:   {f.ok_nets} ok, {len(f.shorts)} short, "
          f"{len(f.opens)} open, {len(f.undriven)} undriven")
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
    if f.splitters:
        print(f"  note: {f.splitters} splitter(s) present — bus-level LVS is v3; "
              f"nets through them are not yet verified.")
    if f.malformed:
        print(f"  note: skipped {f.malformed} malformed element(s) (bad loc/coord).")
    print("  RESULT:", "DRIFT" if (err or f.stale) else "IN SYNC")
    return 1 if err else 0


# --- insert: additively splice missing chips in, without disturbing the file --------
def insert_missing(module, top, circ_path, f):
    net_of, _ = build_net_of(module)
    cells = module.get("cells", {})
    text = open(circ_path).read()
    # find a free row below everything currently drawn
    ys = [int(m) for m in re.findall(r'loc="\(\d+,(\d+)\)"', text)] or [0]
    base = ((max(ys) // 460) + 1) * 460 + 240
    blocks = []
    for i, (cid, inst, _t, _part) in enumerate(f.missing):
        spec = CELLS[cells[inst]["type"]]
        loc = (380 + (i % 4) * 500, base + (i // 4) * 460)
        cc, cw = emit_chip(spec, inst, loc, cells[inst]["connections"], net_of)
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
        text, (summary, unmapped) = generate(module, top)
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
