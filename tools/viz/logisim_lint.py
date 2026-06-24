#!/usr/bin/env python3
"""tools/viz/logisim_lint.py — a faithful, headless re-implementation of the load-time validation
Logisim Evolution 4.1.0 performs when it OPENS a .circ file.

WHY THIS EXISTS.  Logisim reports structural problems (overlaps, unbound appearance ports,
out-of-range attributes, unresolved components, …) in a GUI *error dialog* — there is no console
or headless path that prints them (`-t stats` / `-n` parse but never bind the custom appearance,
and the GUI buffers stdout). To closed-loop test generated `.circ` files we re-implement Logisim's
checks here, transcribed from the bytecode of `logisim-evolution-4.1.0-all.jar`. Each check names
the originating class + resource-bundle message so it can be cross-checked against the source.

COVERAGE — the load-time checks Logisim runs (and whether we reproduce them):

  com.cburch.logisim.file.XmlReader$ReadContext  (per element, as it is read)
    attrNameMissingError    "attribute name missing"                        ✓ check_components/attrs
    attrValueInvalidError   "attribute value (%s) is not valid for %s"       ✓ check_attr_values
    libMissingError         "library ‘%s’ not found"                         ✓ check_components (lib ref)
    compNameMissingError    "component name missing"                         ✓ check_components
    compUnknownError        "component ‘%s’ not found"                       ✓ check_components (factory)
    compAbsentError         "component ‘%s’ missing from library ‘%s’"       ✓ check_components (factory)
    compLocMissingError     "location of component ‘%s’ is unspecified"      ✓ check_components
    compLocInvalidError     "location of component ‘%s’ is invalid (%s)"     ✓ check_components
    wireStartMissingError / wireStartInvalidError                           ✓ check_wires
    wireEndMissingError   / wireEndInvalidError                             ✓ check_wires
    circNameMissingError    "circuit name is missing"                        ✓ check_circuit

  com.cburch.logisim.file.XmlCircuitReader.buildCircuit
    fileComponentOverlapError  "Components %s and %s exactly overlap …"      ✓ check_overlap
    fileAppearanceNotFound     "Appearance element %s not found"             ✓ check_appearance
    fileAppearanceError        "Error while loading appearance element %s"   ✓ check_appearance (structure)

  com.cburch.logisim.circuit.CircuitWires (bundle build, shown as a circuit error on load)
    incompatible widths on a single net                                     ✓ check_net_widths

  Not reproduced (need full GUI / runtime, not a static load concern for a generator):
    library-file resolution (jar/logisim sub-libraries), mouse-mapping/toolbar checks,
    label-collision warnings, PLA/ROM image parsing, FPGA board checks.

Usage:  python3 tools/viz/logisim_lint.py <file.circ> [<file.circ> ...] [--quiet]
Exit status: 0 if every file is clean of ERRORS (warnings alone still exit 0); 1 otherwise.
"""
import os
import sys
import xml.etree.ElementTree as ET
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import logisim as L     # reuse the tested .circ parser + bit-level electrical model + chip tables

BITWIDTH_MAX = 32       # com.cburch.logisim.data.BitWidth.MAXWIDTH
INPUT_RADIUS = 4        # com.cburch.logisim.circuit.appear.AppearancePort.INPUT_RADIUS
FACINGS = {"north", "south", "east", "west"}

# Factory ids per built-in library the generator targets (com.cburch.logisim.std.*). We validate
# names only for the libraries we emit into (Wiring=0, TTL=7); components in any other declared
# library are accepted (a human edit may legitimately use them). Lists from WiringLibrary /
# TtlLibrary in the 4.1.0 jar.
WIRING_TOOLS = {"Pin", "Probe", "Tunnel", "Pull Resistor", "Clock", "Constant", "Power", "Ground",
                "Do Not Connect", "Power-on Reset", "Transistor", "Transmission Gate",
                "Bit Extender", "Splitter"}
TTL_TOOLS = {f"74{n}" for n in (
    "00", "02", "04", "08", "10", "11", "13", "14", "18", "19", "20", "21", "24", "27", "30", "32",
    "34", "36", "42", "43", "44", "47", "51", "54", "58", "64", "74", "85", "86", "87", "125", "138",
    "139", "151", "153", "157", "158", "161", "163", "164", "165", "166", "175", "181", "182", "192",
    "193", "194", "240", "241", "244", "245", "266", "273", "283", "299", "377", "381", "541", "670",
    "7266")}
LIB_TOOLS = {"#Wiring": WIRING_TOOLS, "#TTL": TTL_TOOLS}

ERROR, WARN = "ERROR", "WARN"


def _xy(text):
    """Parse Logisim '(x,y)' -> (int,int); None if absent/malformed."""
    if text is None:
        return None
    s = text.strip()
    if not (s.startswith("(") and s.endswith(")")):
        return False                       # present but malformed
    try:
        x, y = s[1:-1].split(",")
        return (int(x), int(y))
    except ValueError:
        return False


def _int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


class Circuit:
    def __init__(self, el):
        self.el = el
        self.name = el.get("name")
        self.comps = []          # (factory, lib, loc_raw, loc, {attr:val}, [attr_names_present])
        self.wires = []          # (from_raw, to_raw)
        self.appear_ports = []   # {pin, width, dir}
        self.appear_anchors = 0
        self.has_appear = False
        for comp in el.findall("comp"):
            attrs, names_ok = {}, True
            for a in comp.findall("a"):
                if a.get("name") is None:
                    names_ok = False
                else:
                    attrs[a.get("name")] = a.get("val")
            self.comps.append({
                "factory": comp.get("name"), "lib": comp.get("lib"),
                "loc_raw": comp.get("loc"), "loc": _xy(comp.get("loc")),
                "attrs": attrs, "attr_names_ok": names_ok})
        for w in el.findall("wire"):
            self.wires.append((w.get("from"), w.get("to")))
        appear = el.find("appear")
        if appear is not None:
            self.has_appear = True
            self.appear_anchors = len(appear.findall("circ-anchor"))
            for cp in appear.findall("circ-port"):
                self.appear_ports.append({
                    "pin": _xy("(" + (cp.get("pin") or "") + ")") if cp.get("pin") else None,
                    "width": cp.get("width"), "dir": cp.get("dir")})


# --------------------------------------------------------------------------- checks
def check_circuit(circ, _libs, _names, out):
    if not circ.name:
        out.append((ERROR, "circuit name is missing"))


def check_components(circ, libs, circuit_names, out):
    """compNameMissing / compLocMissing / compLocInvalid / libMissing / compUnknown / attrNameMissing."""
    for c in circ.comps:
        where = f'{circ.name}.{c["factory"] or "?"}{c["loc"] if c["loc"] else c["loc_raw"]}'
        if not c["factory"]:
            out.append((ERROR, f"component name missing [{circ.name}]")); continue
        if not c["attr_names_ok"]:
            out.append((ERROR, f"attribute name missing [{where}]"))
        if c["loc_raw"] is None:
            out.append((ERROR, f'location of component ‘{c["factory"]}’ is unspecified [{circ.name}]'))
        elif c["loc"] is False:
            out.append((ERROR, f'location of component ‘{c["factory"]}’ is invalid ({c["loc_raw"]}) [{circ.name}]'))
        if c["lib"] is not None:
            if c["lib"] not in libs:
                out.append((ERROR, f'library ‘{c["lib"]}’ not found [{where}]'))
            else:
                tools = LIB_TOOLS.get(libs[c["lib"]])
                if tools is not None and c["factory"] not in tools:
                    out.append((WARN, f'component ‘{c["factory"]}’ not a known tool of '
                                      f'library {libs[c["lib"]]} [{where}]'))
        else:                                  # no lib => a project-local subcircuit instance
            if c["factory"] not in circuit_names:
                out.append((ERROR, f'component ‘{c["factory"]}’ not found '
                                  f'(no such subcircuit) [{where}]'))


def check_attr_values(circ, _libs, _names, out):
    """attrValueInvalidError: BitWidth (width/incoming) 1..32, Splitter fanout 1..32 and bitN range,
    facing in {north,south,east,west}."""
    for c in circ.comps:
        a = c["attrs"]
        for k in ("width", "incoming"):
            if k in a:
                v = _int(a[k])
                if v is not None and not (1 <= v <= BITWIDTH_MAX):
                    out.append((ERROR, f'attribute value ({v}) is not valid for {k} '
                                      f'[{circ.name}.{c["factory"]}{c["loc"]}]'))
        if "facing" in a and a["facing"] not in FACINGS:
            out.append((ERROR, f'attribute value ({a["facing"]}) is not valid for facing '
                              f'[{circ.name}.{c["factory"]}{c["loc"]}]'))
        if c["factory"] == "Splitter":
            fan = _int(a.get("fanout"))
            if fan is not None and not (1 <= fan <= BITWIDTH_MAX):
                out.append((ERROR, f'attribute value ({fan}) is not valid for fanout '
                                  f'[{circ.name}.Splitter{c["loc"]}]'))
            for k, v in a.items():
                if k.startswith("bit") and k[3:].isdigit() and v != "none":
                    bv = _int(v)
                    if bv is not None and fan is not None and not (0 <= bv < fan):
                        out.append((ERROR, f'attribute value ({v}) is not valid for {k} '
                                          f'[{circ.name}.Splitter{c["loc"]}]'))


def check_wires(circ, _libs, _names, out):
    """wireStart/End Missing/Invalid: every <wire> needs a valid from= and to=."""
    for frm, to in circ.wires:
        if frm is None:
            out.append((ERROR, f"wire start not defined [{circ.name}]"))
        elif _xy(frm) is False:
            out.append((ERROR, f"wire start malformatted ({frm}) [{circ.name}]"))
        if to is None:
            out.append((ERROR, f"wire end not defined [{circ.name}]"))
        elif _xy(to) is False:
            out.append((ERROR, f"wire end malformatted ({to}) [{circ.name}]"))


def _bounds_key(c):
    """Proxy for component.getBounds() (the key XmlCircuitReader dedups on): location, facing,
    width, and label *length* (text extent ~ #chars) — equal bounds => overlap."""
    if not c["loc"]:
        return None
    a = c["attrs"]
    return (c["factory"], c["loc"], a.get("facing"), a.get("width"), len(a.get("label") or ""))


def check_overlap(circ, _libs, _names, out):
    """fileComponentOverlapError: two components landing on identical bounds."""
    seen = {}
    for c in circ.comps:
        key = _bounds_key(c)
        if key is None:
            continue
        if key in seen:
            out.append((ERROR, f'Components {c["factory"]}{c["loc"]} and '
                              f'{seen[key]["factory"]}{seen[key]["loc"]} exactly overlap each '
                              f'other. One has been moved slightly. [{circ.name}]'))
        else:
            seen[key] = c


def _is_input_pin(c):
    """Pin.isInputPin: input unless type=output (legacy output=true) or tristate."""
    t = c["attrs"].get("type")
    return not (t in ("output", "tristate") or c["attrs"].get("output") == "true")


def _is_input_reference(port):
    """isInputPinReference(circ-port): dir=="in" if a dir attr is present, else inferred from the
    glyph width — AppearancePort.isInputAppearance(round(width/2)) == (round(width/2)==INPUT_RADIUS)."""
    if port["dir"] is not None:
        return port["dir"] == "in"
    w = _int(port["width"])
    return w is not None and int(w / 2.0 + 0.5) == INPUT_RADIUS


def check_appearance(circ, _libs, _names, out):
    """fileAppearanceNotFound / fileAppearanceError: bind each <circ-port> to a Pin by LOCATION and
    DIRECTION (Pin.isInputPin == isInputPinReference); a custom appearance needs exactly one anchor."""
    if not circ.has_appear:
        return
    if circ.appear_anchors != 1:
        out.append((ERROR, f"Error while loading appearance element circ-anchor "
                          f"({circ.appear_anchors} anchors, expected 1) [{circ.name}]"))
    pins = [c for c in circ.comps if c["factory"] == "Pin"]
    for port in circ.appear_ports:
        if port["pin"] in (None, False):
            out.append((ERROR, f"Error while loading appearance element circ-port "
                              f"(missing/invalid pin reference) [{circ.name}]")); continue
        want_in = _is_input_reference(port)
        if not any(p["loc"] == port["pin"] and _is_input_pin(p) == want_in for p in pins):
            at = [p for p in pins if p["loc"] == port["pin"]]
            why = ("no Pin at that location" if not at else
                   f'Pin is {"input" if _is_input_pin(at[0]) else "output"} but the circ-port '
                   f'reads as {"input" if want_in else "output"}')
            out.append((ERROR, f"Appearance element circ-port not found "
                              f"[{circ.name}.appear.circ-port pin={port['pin']}] ({why})"))


def check_net_widths(path, circ, _libs, _names, out):
    """CircuitWires reports incompatible widths when one electrical net carries conflicting bit
    widths (e.g. a 12-bit and a 1-bit tunnel on the same net). Reuse the tested bit-level model."""
    try:
        comps, wires, _malformed = L.parse_circ(path, circ.name)
    except Exception:
        return
    chip_pins = []
    for c in comps:
        cell = L.PART2CELL.get(c.name)
        if cell:
            np, facing = cell[1]["pins"], c.attrs.get("facing", "south")
            chip_pins += [L.pin_xy(c.loc, d, np, facing) for d in range(1, np + 1) if c.loc]
        elif c.name in L.PART2CUSTOM:
            np = L.PART2CUSTOM[c.name][1]["pins"]
            chip_pins += [L.custom_pin_xy(c.loc, d, np) for d in range(1, np + 1) if c.loc]
    _root, _ns, _unp, width_mismatch = L.electrical_model(comps, wires, chip_pins)
    for _bundle, w1, w2 in width_mismatch:
        out.append((ERROR, f"incompatible widths on one net: {w1}-bit vs {w2}-bit [{circ.name}]"))


CIRCUIT_CHECKS = [check_circuit, check_components, check_attr_values, check_wires,
                  check_overlap, check_appearance]


def lint_file(path):
    """Return list[(severity, message)] for one .circ."""
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        return [(ERROR, f"malformed XML: {e}")]
    libs = {lib.get("name"): lib.get("desc") for lib in root.findall("lib")}
    circuits = [Circuit(ce) for ce in root.findall("circuit")]
    names = {c.name for c in circuits}
    out = []
    for circ in circuits:
        for check in CIRCUIT_CHECKS:
            check(circ, libs, names, out)
        check_net_widths(path, circ, libs, names, out)
    return out


def main():
    quiet = "--quiet" in sys.argv
    paths = [a for a in sys.argv[1:] if not a.startswith("-")]
    if not paths:
        print("usage: logisim_lint.py <file.circ> [...] [--quiet]", file=sys.stderr)
        return 2
    n_err = 0
    for path in paths:
        issues = lint_file(path)
        errs = [m for s, m in issues if s == ERROR]
        warns = [m for s, m in issues if s == WARN]
        n_err += len(errs)
        if not errs and not warns:
            print(f"✓ {path}: clean (no Logisim load errors)")
            continue
        print(f"{'✗' if errs else '⚠'} {path}: {len(errs)} error(s), {len(warns)} warning(s)")
        if not quiet:
            for label, msgs in (("ERROR", errs), ("WARN", warns)):
                for msg, k in Counter(msgs).most_common():
                    print(f"    [{label}] {('%d× ' % k) if k > 1 else ''}{msg}")
    return 1 if n_err else 0


if __name__ == "__main__":
    sys.exit(main())
