// IS61C64AL — 8K x 8 high-speed asynchronous CMOS SRAM (ISSI). The microcode
// control-store part (D-43 BOM): all 13 control-store chips (11 WCS + 2 opcode-
// map) are this device. Datasheet: docs/reference/datasheets/61C64AL.pdf (Rev B2).
//
// Fully static — NO clock, no refresh. Interface is the real chip's pinout:
//   A0-A12   13 address lines                          (param AW)
//   I/O0-7   bidirectional data                        (param DW)
//   /CE      chip enable      (active LOW)
//   /OE      output enable    (active LOW)
//   /WE      write enable     (active LOW)
//
// Truth table (datasheet p.2):
//   /CE  /WE  /OE | I/O
//    H    X    X  | High-Z      (standby / not selected)
//    L    H    H  | High-Z      (selected, output disabled)
//    L    H    L  | D_OUT       (read)
//    L    L    X  | D_IN        (write)
//
// Write is the overlap of /CE LOW and /WE LOW; data is captured on the edge that
// terminates the write — whichever of /WE or /CE returns HIGH first (p.7: "any
// one can go inactive to terminate the Write"). Address and data are sampled at
// that edge.
//
// On the board the boot loader ties /CE LOW, holds /OE HIGH, and a 4->16 decoder
// routes a write pulse to exactly one chip's /WE (hardware.md, D-43); at run time
// /WE is HIGH and the addressed byte drives the control word.
//
// Read-path `specify` delays below are the -10 speed grade (datasheet p.5),
// honored by the timed Icarus engine (-gspecify) and ignored by the zero-delay
// Verilator/functional engine (toolchain.md §5, §10.3). Write-cycle limits
// (tWC 10, tPWE1 9 / tPWE2 8, tSD 7, tAW 9, tHA/tHD 0 ns, datasheet p.7) are not
// yet expressed as timing checks — the boot-copy path is exercised functionally.
`timescale 1ns/1ps
`default_nettype none
module is61c64 #(
    parameter AW = 13,          // A0-A12  (2^13 = 8 Kword)
    parameter DW = 8            // I/O0-7
) (
    input  wire [AW-1:0] a,     // address
    inout  wire [DW-1:0] io,    // bidirectional data
    input  wire          ce_n,  // /CE chip enable   (active LOW)
    input  wire          oe_n,  // /OE output enable (active LOW)
    input  wire          we_n   // /WE write enable  (active LOW)
);
    reg [DW-1:0] mem [0:(1<<AW)-1];

    // Write: capture on the terminating edge. At posedge /WE the write ends if
    // /CE is still LOW; at posedge /CE it ends if /WE is still LOW. Either path
    // samples the address/data present at that instant.
    always @(posedge we_n) if (!ce_n) mem[a] <= io;
    always @(posedge ce_n) if (!we_n) mem[a] <= io;

    // Read: drive I/O only when selected, output-enabled, and not writing.
    wire reading = !ce_n && we_n && !oe_n;
    assign io = reading ? mem[a] : {DW{1'bz}};

    specify
        // Read-cycle access delays, -10 grade (datasheet p.5).
        // Triplet = (output rise, output fall, turn-off to High-Z).
        (a    *> io) = 10;            // tAA   address access time
        (ce_n *> io) = (10, 10, 5);   // tACS  /CE access  / tHZCS  /CE HIGH -> High-Z
        (oe_n *> io) = (6,  6,  5);   // tDOE  /OE access  / tHZOE  /OE HIGH -> High-Z
    endspecify
endmodule
`default_nettype wire
