// microcode_store — the writable control store (WCS): the 11 byte-wide SRAMs that hold
// the 88-bit horizontal control word, plus their boot-write path. Structural netlist of
// real chips (R-SIM-1, R-SIM-5; microcode.md §3, hardware.md §4).
//
// One micro-address (`addr`) reads one 88-bit control word out, byte k = SRAM k. The same
// chips are written during boot: the loader fans the EEPROM byte onto every SRAM's I/O
// through a per-chip isolation buffer, strobing one chip's /WE at a time.
//
// Structure (the BOM), per chip g (0..10):
//   sn74ahct541  -> boot-write isolation buffer. Enabled (oe1_n=wbuf_oe_n=run, LOW in
//                   boot) to drive the shared EEPROM byte onto this SRAM's I/O during the
//                   copy; tri-stated in run so the SRAM drives its own control-word byte.
//   is61c64      -> the WCS SRAM (8 K part, A12 grounded -> 4096-word store, D-49). /CE
//                   tied low; /OE = oe_n (= loading: write in boot, read in run); /WE the
//                   per-chip strobe.
`timescale 1ns/1ps
`default_nettype none
module microcode_store #(
    parameter NWCS = 11             // 88-bit word over 11 byte-wide SRAMs
) (
    input  wire [11:0]      addr,       // control-store address (µPC in run, loader in boot)
    input  wire [7:0]       wdata,      // boot write data (= the EEPROM byte)
    input  wire             wbuf_oe_n,  // boot-write buffer enable, active LOW (= run)
    input  wire             oe_n,       // SRAM /OE, active LOW (= loading)
    input  wire [NWCS-1:0]  we_n,       // per-chip /WE strobe (active LOW)
    output wire [8*NWCS-1:0] cw          // the 88-bit control word (byte k = SRAM k)
);
    wire [7:0] io [0:NWCS-1];
    genvar g;
    generate for (g = 0; g < NWCS; g = g + 1) begin : chip
        sn74ahct541 wbuf (.a(wdata), .oe1_n(wbuf_oe_n), .oe2_n(1'b0), .y(io[g]));
        is61c64 #(.AW(13), .DW(8)) sram (
            .a({1'b0, addr}), .io(io[g]), .ce_n(1'b0), .oe_n(oe_n), .we_n(we_n[g])
        );
        assign cw[8*g +: 8] = io[g];
    end endgenerate
endmodule
`default_nettype wire
