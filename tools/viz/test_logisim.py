#!/usr/bin/env python3
"""tools/viz/test_logisim.py — self-test for the Logisim generator + reconciler.

Hermetic: builds a tiny synthetic netlist in-process (no Yosys), so it runs anywhere
`python3` does. Covers the two things that are subtle and easy to regress:

  1. the electrical model (electrical_nets) — a wire is an equipotential, so any node on
     it (endpoint OR interior) joins the net, while a pure crossing does not. This is what
     makes tunnel<->wire rewiring electrically equivalent and what catches mid-span taps.
  2. the LVS reconcile verdicts — IN SYNC on equivalent edits; OPEN / SHORT / MISSING /
     STALE on real drift; no crash on hand-edited (rotated / malformed) files.

Run:  python3 tools/viz/test_logisim.py   (exit 0 = all pass)
"""
import importlib.util
import os
import sys
import tempfile
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("logisim", os.path.join(HERE, "logisim.py"))
L = importlib.util.module_from_spec(spec)
spec.loader.exec_module(L)

_n = {"pass": 0, "fail": 0}


def chk(name, cond):
    print(("PASS" if cond else "FAIL"), name)
    _n["pass" if cond else "fail"] += 1


# --- a tiny module: an inverter feeding one input of an AND gate ---------------------
# net 2 = in0 (fans to inv.a and and0.b), net 3 = inv.y->and0.a, net 5 = and0.y = out0,
# and0 also has a spare input tied to the constant-1 rail (net "1").
TOP = "selftest"
MODULE = {
    "ports": {"in0": {"direction": "input", "bits": [2]},
              "out0": {"direction": "output", "bits": [5]}},
    "cells": {
        "inv":  {"type": "sn74ahct04", "connections": {"a": [2], "y": [3]}},
        "and0": {"type": "sn74ahct08", "connections": {"a": [3], "b": [2], "y": [5]}},
        "and1": {"type": "sn74ahct08", "connections": {"a": [5], "b": ["1"], "y": [6]}},
    },
    "netnames": {"in0": {"bits": [2]}, "n3": {"bits": [3]},
                 "out0": {"bits": [5]}, "n6": {"bits": [6]}},
}


def write_base(path):
    text, _ = L.generate(MODULE, TOP)
    open(path, "w").write(text)


def load(path):
    t = ET.parse(path)
    circ = [c for c in t.getroot().findall("circuit") if c.get("name") == TOP][0]
    return t, circ


def add_wire(circ, a, b):
    w = ET.SubElement(circ, "wire")
    w.set("from", f"({a[0]},{a[1]})"); w.set("to", f"({b[0]},{b[1]})")


def tunnels(circ):
    out = []
    for c in circ.findall("comp"):
        if c.get("name") == "Tunnel":
            lb = [a.get("val") for a in c.findall("a") if a.get("name") == "label"]
            out.append((c, lb[0] if lb else None, L._pt(c.get("loc"))))
    return out


def clean(f):
    return not (f.opens or f.shorts or f.missing or f.stale or f.undriven or f.dup)


def main():
    EN, C = L.electrical_nets, L.Comp

    # ---- unit: the electrical model -------------------------------------------------
    d, _ = EN([], [((0, 0), (40, 0)), ((20, 0), (20, 20))], [])
    chk("T-junction tap connects", d.find((0, 0)) == d.find((20, 20)))
    d, _ = EN([], [((0, 0), (40, 0)), ((20, -20), (20, 20))], [])
    chk("pure crossing stays separate", d.find((0, 0)) != d.find((20, 20)))
    d, _ = EN([], [((0, 0), (40, 0)), ((20, 0), (60, 0))], [])
    chk("collinear overlap merges", d.find((0, 0)) == d.find((60, 0)))
    d, _ = EN([C("0", "Tunnel", (20, 0), {"label": "X"})], [((0, 0), (40, 0))], [])
    chk("mid-wire tunnel tap connects", d.find((0, 0)) == d.find(("TUN", "X")))
    d, _ = EN([], [((0, 0), (40, 0))], [(20, 0)])
    chk("wire over chip pin connects", d.find((0, 0)) == d.find((20, 0)))

    # ---- unit: pin_xy geometry ------------------------------------------------------
    # distinct, non-colliding pin coords; rotation is rigid (same multiset of |offsets|).
    pins14 = [L.pin_xy((0, 0), p, 14, "south") for p in range(1, 15)]
    chk("south pins are distinct", len(set(pins14)) == 14)
    chk("bad facing falls back, no crash", L.pin_xy((0, 0), 1, 14, "SIDEWAYS") ==
        L.pin_xy((0, 0), 1, 14, "south"))
    chk("_pt tolerates malformed", L._pt("(500)") is None and L._pt("(7,8)") == (7, 8))

    # ---- unit: splitter / bus bit-level model (synthetic geometry) ------------------
    # The splitter pin geometry is injected here so these test the bit-remapping LOGIC
    # independently of the real coordinates (which are derived against Logisim itself).
    saved_ends = L.splitter_ends
    geo = {(100, 0): ((100, 0), [(90, 0), (90, 10), (90, 20), (90, 30)]),
           (200, 0): ((200, 0), [(210, 0), (210, 10), (210, 20), (210, 30)])}
    L.splitter_ends = lambda loc, fac, fo, spacing=1, appear="left": geo.get(tuple(loc), (None, None))
    try:
        def splitter(loc, **extra):
            a = {"incoming": "4", "fanout": "4", "facing": "east"}; a.update(extra)
            return C("0", "Splitter", loc, a)
        A = [(90, 0), (90, 10), (90, 20), (90, 30)]
        B = [(210, 0), (210, 10), (210, 20), (210, 30)]
        # two splitters fan a shared 4-bit BUS tunnel out to chip pins, identity mapping
        bus = [C("0", "Tunnel", (100, 0), {"label": "BUS", "width": "4"}),
               C("0", "Tunnel", (200, 0), {"label": "BUS", "width": "4"}),
               splitter((100, 0)), splitter((200, 0))]
        rt, ns, unp, wm = L.electrical_model(bus, [], A + B)
        chk("bus: same bit through splitters+bus tunnel connects",
            rt(A[0]) == rt(B[0]) and rt(A[2]) == rt(B[2]))
        chk("bus: distinct bits stay separate", rt(A[0]) != rt(A[1]) and rt(A[0]) != rt(B[1]))
        chk("bus: clean model (2 splitters, no mismatch)", ns == 2 and unp == 0 and not wm)
        # a reversed splitter map remaps which physical pin carries which bus bit
        rev = [C("0", "Tunnel", (100, 0), {"label": "R", "width": "4"}),
               C("0", "Tunnel", (200, 0), {"label": "R", "width": "4"}),
               splitter((100, 0)), splitter((200, 0), bit0="3", bit1="2", bit2="1", bit3="0")]
        rr, *_ = L.electrical_model(rev, [], A + B)
        chk("bus: reversed splitter map", rr(A[0]) == rr(B[3]) and rr(A[0]) != rr(B[0]))
        wmix = L.electrical_model(
            [C("0", "Tunnel", (100, 0), {"label": "W", "width": "4"})], [], [(100, 0)])[3]
        chk("bus: 1-bit pin on a 4-bit bus -> width mismatch", bool(wmix))
    finally:
        L.splitter_ends = saved_ends

    # ---- integration: reconcile verdicts -------------------------------------------
    tmp = tempfile.mkdtemp()
    base = os.path.join(tmp, "base.circ")
    write_base(base)
    chk("self-consistency IN SYNC", clean(L.reconcile(MODULE, TOP, base)))

    skip = {"ZERO", "ONE", "in0", "out0"}

    # tunnel -> direct wire on a 2-tunnel net stays IN SYNC
    t, circ = load(base)
    byl = {}
    for c, lb, loc in tunnels(circ):
        if lb and lb not in skip:
            byl.setdefault(lb, []).append((c, loc))
    pair = next(v for v in byl.values() if len(v) == 2)
    (c1, p1), (c2, p2) = pair
    circ.remove(c1); circ.remove(c2); add_wire(circ, p1, p2)
    p = os.path.join(tmp, "equiv.circ"); t.write(p)
    chk("tunnel->wire equivalence IN SYNC", clean(L.reconcile(MODULE, TOP, p)))

    # delete a chip -> MISSING (+ --insert restores IN SYNC)
    t, circ = load(base)
    ch = next(c for c in circ.findall("comp") if c.get("name") in L.PART2CELL)
    lbl = next(a.get("val") for a in ch.findall("a") if a.get("name") == "label")
    circ.remove(ch)
    p = os.path.join(tmp, "missing.circ"); t.write(p)
    f = L.reconcile(MODULE, TOP, p)
    chk("delete chip -> MISSING", any(cid == lbl for cid, *_ in f.missing))
    L.insert_missing(MODULE, TOP, p, f)
    chk("--insert restores IN SYNC", clean(L.reconcile(MODULE, TOP, p)))

    # relabel a tunnel -> OPEN on that net
    t, circ = load(base)
    target = next(lb for lb, v in byl.items() if len(v) == 2)
    for c in circ.findall("comp"):
        if c.get("name") == "Tunnel":
            la = [a for a in c.findall("a") if a.get("name") == "label" and a.get("val") == target]
            if la:
                la[0].set("val", "BOGUS"); break
    p = os.path.join(tmp, "open.circ"); t.write(p)
    chk("relabel tunnel -> OPEN", any(n == target for n, _ in L.reconcile(MODULE, TOP, p).opens))

    # stray chip -> STALE
    t, circ = load(base)
    g = ET.SubElement(circ, "comp"); g.set("lib", "7"); g.set("name", "7404"); g.set("loc", "(9000,9000)")
    a = ET.SubElement(g, "a"); a.set("name", "label"); a.set("val", "ghost")
    p = os.path.join(tmp, "stale.circ"); t.write(p)
    chk("stray chip -> STALE", "ghost" in L.reconcile(MODULE, TOP, p).stale)

    # wire two distinct nets -> SHORT
    t, circ = load(base)
    locs = {}
    for c, lb, loc in tunnels(circ):
        if lb and lb not in skip:
            locs.setdefault(lb, loc)
    ks = list(locs)[:2]
    add_wire(circ, locs[ks[0]], locs[ks[1]])
    p = os.path.join(tmp, "short.circ"); t.write(p)
    chk("wire two nets -> SHORT", any(set(ks) <= set(nn) for nn, _ in L.reconcile(MODULE, TOP, p).shorts))

    # interior T-junction (the high-sev fix): a tap mid-span of a wire is detected
    t, circ = load(base)
    hw = None
    for w in circ.findall("wire"):
        a, b = L._pt(w.get("from")), L._pt(w.get("to"))
        if a[1] == b[1] and abs(a[0] - b[0]) >= 40:
            hw = (a, b); break
    if hw:
        mid = ((hw[0][0] + hw[1][0]) // 20 * 10, hw[0][1])
        other = next(loc for c, lb, loc in tunnels(circ)
                     if lb and lb not in skip and loc[1] != mid[1])
        add_wire(circ, mid, other)
        p = os.path.join(tmp, "tap.circ"); t.write(p)
        f = L.reconcile(MODULE, TOP, p)
        chk("interior T-junction detected", bool(f.shorts or f.opens))

    # rail: delete the constant-1 source -> the consumer is UNDRIVEN
    t, circ = load(base)
    for c in circ.findall("comp"):
        if c.get("name") == "Constant":
            v = [a.get("val") for a in c.findall("a") if a.get("name") == "value"]
            if v and int(v[0], 0) == 1:
                circ.remove(c); break
    p = os.path.join(tmp, "undriven.circ"); t.write(p)
    chk("delete rail source -> UNDRIVEN", bool(L.reconcile(MODULE, TOP, p).undriven))

    # robustness: uppercase facing + malformed element must not crash
    t, circ = load(base)
    ch = next(c for c in circ.findall("comp") if c.get("name") in L.PART2CELL)
    for a in ch.findall("a"):
        if a.get("name") == "facing":
            a.set("val", "SOUTH")
    g = ET.SubElement(circ, "comp"); g.set("lib", "0"); g.set("name", "Pin"); g.set("loc", "(500)")
    p = os.path.join(tmp, "rough.circ"); t.write(p)
    try:
        f = L.reconcile(MODULE, TOP, p)
        chk("uppercase facing + malformed: no crash, counted", f.malformed >= 1)
    except Exception as e:  # noqa: BLE001
        chk(f"uppercase facing + malformed: no crash ({e!r})", False)

    # ---- integration: bus replacement with REAL splitter geometry ------------------
    # the user's scenario: replace a bus's individual 1-bit tunnels with one bus tunnel
    # + two real splitters wired to the actual chip pins. Must stay IN SYNC; a wrong
    # bit-map must trip SHORT/OPEN. decoder y[0..3] drive buffer a[0..3] over 4 nets.
    chk("splitter_ends matches Logisim ground-truth example",
        L.splitter_ends((810, 630), "south", 5, 1, "right")
        == ((810, 630), [(800, 650), (790, 650), (780, 650), (770, 650), (760, 650)]))
    BTOP = "bustop"
    BMOD = {
        "ports": {"sel": {"direction": "input", "bits": [10, 11, 12]},
                  "q": {"direction": "output", "bits": [20, 21, 22, 23]}},
        "cells": {
            "dec": {"type": "sn74ahct138", "connections": {
                "a": [10], "b": [11], "c": [12], "g1": ["1"], "g2a_n": ["0"], "g2b_n": ["0"],
                "y": [30, 31, 32, 33, 40, 41, 42, 43]}},
            "buf": {"type": "sn74ahct541", "connections": {
                "oe1_n": ["0"], "oe2_n": ["0"],
                "a": [30, 31, 32, 33, 50, 51, 52, 53], "y": [20, 21, 22, 23, 60, 61, 62, 63]}}},
        "netnames": {}}
    bnet_of, _ = L.build_net_of(BMOD)
    busnets = {bnet_of(b) for b in (30, 31, 32, 33)}
    bbase = os.path.join(tmp, "bus_base.circ")
    open(bbase, "w").write(L.generate(BMOD, BTOP, buses=False)[0])   # busify converts it itself

    def busify(dst, consumer_map):
        bt = ET.parse(bbase)
        bc = [c for c in bt.getroot().findall("circuit") if c.get("name") == BTOP][0]
        cloc = {}
        for c in bc.findall("comp"):
            if c.get("name") in L.PART2CELL:
                lb = next(x.get("val") for x in c.findall("a") if x.get("name") == "label")
                cloc[lb] = L._pt(c.get("loc"))
        for c in list(bc.findall("comp")):                 # drop the bus nets' 1-bit tunnels
            if c.get("name") == "Tunnel":
                lb = [x.get("val") for x in c.findall("a") if x.get("name") == "label"]
                if lb and lb[0] in busnets:
                    bc.remove(c)

        def splitter(sloc, pins, endmap):
            sp = ET.SubElement(bc, "comp"); sp.set("lib", "0"); sp.set("name", "Splitter")
            sp.set("loc", f"({sloc[0]},{sloc[1]})")
            for k, v in (("incoming", "4"), ("fanout", "4"), ("facing", "east")):
                e = ET.SubElement(sp, "a"); e.set("name", k); e.set("val", v)
            comb, ends = L.splitter_ends(sloc, "east", 4)   # combined end -> shared bus tunnel
            tn = ET.SubElement(bc, "comp"); tn.set("lib", "0"); tn.set("name", "Tunnel")
            tn.set("loc", f"({comb[0]},{comb[1]})")
            for k, v in (("label", "DBUS"), ("width", "4")):
                e = ET.SubElement(tn, "a"); e.set("name", k); e.set("val", v)
            for i, pin in enumerate(pins):                  # each fanout end -> a real chip pin
                ep = ends[endmap[i]]
                w = ET.SubElement(bc, "wire")
                w.set("from", f"({ep[0]},{ep[1]})"); w.set("to", f"({pin[0]},{pin[1]})")
        drv = [L.pin_xy(cloc["dec"], d, 16, "south") for d in (15, 14, 13, 12)]  # dec.y[0..3]
        con = [L.pin_xy(cloc["buf"], d, 20, "south") for d in (2, 3, 4, 5)]      # buf.a[0..3]
        splitter((4000, 3000), drv, [0, 1, 2, 3])           # driver: y[i] -> bus bit i
        splitter((4000, 3300), con, consumer_map)           # consumer: a[i] -> bus bit map[i]
        bt.write(dst)

    good = os.path.join(tmp, "bus_good.circ"); busify(good, [0, 1, 2, 3])
    fg = L.reconcile(BMOD, BTOP, good)
    chk("bus replacement (real splitters) IN SYNC",
        not (fg.opens or fg.shorts or fg.missing or fg.width_mismatch)
        and fg.splitters == 2 and fg.splitter_unparsed == 0)
    bad = os.path.join(tmp, "bus_bad.circ"); busify(bad, [3, 2, 1, 0])
    fb = L.reconcile(BMOD, BTOP, bad)
    chk("wrong bus bit-map -> SHORT/OPEN", bool(fb.shorts or fb.opens))

    # ---- bus GENERATION (generate --bus): widest-first, internal bus, slice ports -----
    # cw (6-bit input bus) feeds a decoder; pt is a 2-bit pass-through output SLICE of cw; pti is a
    # 2-bit INPUT slice of cw (its fanout-1 tap faces so the pin->end wire never crosses the bus
    # combined point — regression for the input slice-tap short); q is the decoder's 4-bit output
    # bus; cw_lo overlaps cw narrowly to exercise widest-first.
    GMOD = {
        "ports": {"cw": {"direction": "input", "bits": [50, 51, 52, 53, 54, 55]},
                  "pt": {"direction": "output", "bits": [52, 53]},
                  "pti": {"direction": "input", "bits": [53, 54]},
                  "q": {"direction": "output", "bits": [20, 21, 22, 23]}},
        "cells": {"dec": {"type": "sn74ahct138", "connections": {
            "a": [50], "b": [51], "c": [52], "g1": ["1"], "g2a_n": ["0"], "g2b_n": ["0"],
            "y": [20, 21, 22, 23, 40, 41, 42, 43]}}},
        "netnames": {"q": {"bits": [20, 21, 22, 23]},
                     "cw": {"bits": [50, 51, 52, 53, 54, 55]},
                     "cw_lo": {"bits": [50, 51]}}}
    chk("widest-first bus resolution", L.build_bus_map(GMOD).get(50) == ("cw", 0, 6))
    gb = os.path.join(tmp, "gen_bus.circ")
    open(gb, "w").write(L.generate(GMOD, "gmod", buses=True)[0])
    fg = L.reconcile(GMOD, "gmod", gb)
    chk("generate --bus reconciles IN SYNC (incl. input+output slice ports)",
        not (fg.opens or fg.shorts or fg.missing or fg.width_mismatch) and fg.splitters > 0)
    g1 = os.path.join(tmp, "gen_1bit.circ")
    open(g1, "w").write(L.generate(GMOD, "gmod", buses=False)[0])
    f1 = L.reconcile(GMOD, "gmod", g1)
    chk("1-bit generate of same module IN SYNC",
        not (f1.opens or f1.shorts or f1.missing or f1.width_mismatch) and f1.splitters == 0)

    # bus-aware --insert: drop the chip from the bus circuit, splice it back via break-outs
    gt = ET.parse(gb)
    gc = [c for c in gt.getroot().findall("circuit") if c.get("name") == "gmod"][0]
    gc.remove(next(c for c in gc.findall("comp") if c.get("name") in L.PART2CELL))
    gd = os.path.join(tmp, "gen_bus_drop.circ"); gt.write(gd)
    fd = L.reconcile(GMOD, "gmod", gd)
    chk("bus circuit: chip delete -> MISSING", bool(fd.missing))
    L.insert_missing(GMOD, "gmod", gd, fd)
    fi = L.reconcile(GMOD, "gmod", gd)
    chk("bus-aware --insert restores IN SYNC",
        not (fi.opens or fi.shorts or fi.missing or fi.width_mismatch))

    print("=" * 52)
    print(f"{_n['pass']} passed, {_n['fail']} failed")
    sys.exit(1 if _n["fail"] else 0)


if __name__ == "__main__":
    main()
