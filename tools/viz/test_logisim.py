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

    print("=" * 52)
    print(f"{_n['pass']} passed, {_n['fail']} failed")
    sys.exit(1 if _n["fail"] else 0)


if __name__ == "__main__":
    main()
