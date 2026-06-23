#!/usr/bin/env node
// tools/viz/digitaljs.js — convert structural Verilog into an interactive DigitalJS
// circuit (docs/toolchain.md §6, "interactive, animated logic — the Logisim
// experience, from code"; P3). Generated from the same Verilog as every other view,
// never authored.
//
//   yosys (the standard yosys2digitaljs synth flow)            -> netlist JSON
//     -> coerce inout->input (DigitalJS has no inout port type, same as netlistsvg)
//     -> yosys2digitaljs core conversion                       -> DigitalJS circuit
//     -> emit <top>.digitaljs.json + a self-contained <top>.html viewer
//
// We drive the library's lower-level core directly (not its process() entry point)
// so we can coerce inout between yosys and the conversion — process() gives no such
// hook, and DigitalJS rejects inout outright.
//
// Usage: node digitaljs.js <top> <outdir> <verilog...>
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');
// The package exposes its core (prepare_yosys_script, yosys2digitaljs, io_ui) via
// the "./core" entry in its exports map; the package root (".") is not exported.
const core = require('yosys2digitaljs/core');

const [top, outdir, ...files] = process.argv.slice(2);
if (!top || !outdir || files.length === 0) {
  console.error('usage: node digitaljs.js <top> <outdir> <verilog...>');
  process.exit(1);
}
// `top` is interpolated into the yosys script (hierarchy -top) and the output paths;
// require a plain Verilog identifier so it can neither inject script nor escape paths.
if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(top)) {
  console.error(`error: TOP must be a Verilog identifier, got '${top}'`);
  process.exit(1);
}
const opts = { fsm: true };

// 1. Synthesize with yosys2digitaljs's own flow, but PIN the top to the requested
//    module. The library's script ends in `hierarchy -auto-top`, which silently
//    picks a different uninstantiated module when several are present — yielding a
//    correctly-named file that holds the WRONG circuit. `hierarchy -top <top>` is
//    deterministic; we keep the rest of the library's flow, staying in lockstep.
let script = core.prepare_yosys_script(files, opts);
if (!script.includes('hierarchy -auto-top')) {
  console.error('error: unexpected yosys2digitaljs script — no `hierarchy -auto-top` to pin');
  process.exit(1);
}
script = script.replace('hierarchy -auto-top', `hierarchy -top ${top}`);

const tmpjson = path.join(os.tmpdir(), `blip_djs_${process.pid}.json`);
try {
  execSync(`yosys -q -p "${script}" -o ${tmpjson}`, { maxBuffer: 1 << 28, stdio: ['ignore', 'ignore', 'inherit'] });
} catch (e) {
  console.error('yosys failed:', e.message);
  process.exit(1);
}
const netlist = JSON.parse(fs.readFileSync(tmpjson, 'utf8'));
fs.unlinkSync(tmpjson);

// 2. DigitalJS has no `inout` port type (same limitation as netlistsvg). Coerce
//    inout->input for the conversion; the nets themselves are unchanged.
for (const m of Object.values(netlist.modules || {})) {
  for (const p of Object.values(m.ports || {})) if (p.direction === 'inout') p.direction = 'input';
  for (const c of Object.values(m.cells || {})) {
    const pd = c.port_directions || {};
    for (const k of Object.keys(pd)) if (pd[k] === 'inout') pd[k] = 'input';
  }
}

// 3. Convert. A shared bidirectional bus (e.g. the control-store data bus) becomes a
//    multi-driver net, which a functional simulator can't resolve: DigitalJS is
//    unit-delay functional logic with no tri-state model (toolchain.md §6 — an
//    intuition view, not an authority). Detect that and say so plainly.
let circuit;
try {
  circuit = core.yosys2digitaljs(netlist, opts);
} catch (e) {
  if (/Multiple sources driving net|Invalid port direction/.test(e.message)) {
    console.error(
`DigitalJS can't simulate '${top}': it has a shared bidirectional bus
  (${e.message}).
DigitalJS is functional, unit-delay logic with no tri-state resolution, so a
multi-driver bus is outside its model. Two ways forward:
  • interactive sim of a block without a tri-state bus:  make digitaljs TOP=uc_loader
  • whole-CPU structure (the bus drawn as wiring):        make viz`);
    process.exit(0);   // an expected, explained dead-end — not a build failure
  }
  throw e;
}
core.io_ui(circuit);

// 4. Emit the circuit JSON and a self-contained viewer. The page loads DigitalJS's
//    official prebuilt bundle (which exposes the `digitaljs` and `$` globals) and
//    instantiates the circuit per its documented API.
fs.mkdirSync(outdir, { recursive: true });
const jsonPath = path.join(outdir, `${top}.digitaljs.json`);
const htmlPath = path.join(outdir, `${top}.html`);
fs.writeFileSync(jsonPath, JSON.stringify(circuit, null, 2));

// Embed the circuit safely inside the inline <script>: escape '<' (so no HDL-derived
// string can spell `</script>`) and the JS-illegal line separators U+2028/U+2029.
const embed = JSON.stringify(circuit)
  .replace(/</g, '\\u003c')
  .replace(/\u2028/g, '\\u2028')
  .replace(/\u2029/g, '\\u2029');

const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>BLIP · ${top} (DigitalJS)</title>
<style>html,body{margin:0;height:100%;font-family:system-ui,sans-serif}#paper{height:100vh;overflow:auto}</style>
<script src="https://tilk.github.io/digitaljs/main.js"></script>
</head>
<body>
<div id="paper"></div>
<script>
  const circuit = new digitaljs.Circuit(${embed});
  const paper = circuit.displayOn($('#paper'));
  circuit.start();
</script>
</body>
</html>`;
fs.writeFileSync(htmlPath, html);

const ndev = Object.keys(circuit.devices).length, ncon = circuit.connectors.length;
console.log(`circuit:  ${jsonPath}  (${ndev} devices, ${ncon} connectors)`);
console.log(`viewer:   ${htmlPath}  (open in a browser — needs network for the DigitalJS bundle)`);
