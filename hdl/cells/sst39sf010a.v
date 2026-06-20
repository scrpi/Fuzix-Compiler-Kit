// SST39SF010A — 128K x 8 (1 Mbit) Multi-Purpose Flash (SST / Microchip). The
// single microcode boot EEPROM (D-03/D-43): the loader reads it at power-on and
// fans its contents out to the 13 control-store SRAMs. Family datasheet
// SST39SF010A/020A/040 — docs/reference/datasheets/SST39SF010A.pdf.
//
// Interface is the real chip's pinout (JEDEC x8):
//   A0-A16   17 address lines  (AMS = A16 on the 010A)        (param AW)
//   DQ0-7    bidirectional data                               (param DW)
//   CE#      chip enable    (active LOW)
//   OE#      output enable  (active LOW)
//   WE#      write enable   (active LOW)
//
// READ-ONLY model. The boot loader only READS a pre-burned part (D-43): contents
// are loaded from FILE via $readmemh, exactly the bytes the device is programmed
// with (toolchain.md P1, R-SIM-2). The JEDEC Program/Erase command sequences
// (datasheet Table 12 / Figure 6 — 5555h/2AAAh unlock, byte-program, sector/chip
// erase) are NOT modeled; WE#-driven command writes are ignored, so the device
// presents as a pre-burned ROM. This EEPROM holds ONLY the control-store image
// (WCS + opcode-map SRAMs); the firmware monitor/loader is a separate system ROM
// in the memory map (D-31).
//
// Part-agnostic by design (D-43): a larger pin-compatible SST39SF020A/040 grounds
// its upper address pin(s) (A17/A18) and presents the low 128K identically, so
// the model stays at the 128K design size.
//
// Read-cycle `specify` delays below default to the -70 speed grade (slowest —
// conservative for the boot-clock budget); the -45 grade values are noted inline
// (datasheet Table 11). Honored by the timed Icarus engine (-gspecify), ignored
// by the zero-delay engine (toolchain.md §5, §10.3). The boot-copy path itself is
// exercised functionally (zero-delay), so the slow flash read does not gate the
// loader regression — in hardware the boot clock is slowed to meet TAA.
`timescale 1ns/1ps
`default_nettype none
module sst39sf010a #(
    parameter AW    = 17,       // A0-A16  (2^17 = 128 Kbyte)
    parameter DW    = 8,        // DQ0-7
    parameter FILE  = "",       // pre-burned image (Intel/Verilog hex)
    parameter LOADW = 0         // words to load from FILE (0 = whole array)
) (
    input  wire [AW-1:0] a,     // address
    inout  wire [DW-1:0] dq,    // bidirectional data
    input  wire          ce_n,  // CE# chip enable   (active LOW)
    input  wire          oe_n,  // OE# output enable (active LOW)
    input  wire          we_n   // WE# write enable  (active LOW; in-system program not modeled)
);
    reg [DW-1:0] mem [0:(1<<AW)-1];
    initial if (FILE != "") begin
        // Load LOADW words when given (the microcode image fills only the low
        // region of the part), else the whole array.
        if (LOADW != 0) $readmemh(FILE, mem, 0, LOADW-1);
        else            $readmemh(FILE, mem);
    end

    // Read: drive DQ when selected, output-enabled, and WE# inactive (datasheet
    // Fig. 5 — WE# = VIH for a read). High-Z otherwise (standby / output disabled
    // / command-write, when DQ is an input the device does not drive).
    wire reading = !ce_n && !oe_n && we_n;
    assign dq = reading ? mem[a] : {DW{1'bz}};

    specify
        // Read-cycle path delays. Default = -70 grade; [-45 grade] in brackets.
        // Triplet = (output rise, output fall, turn-off to High-Z).
        specparam TAA  = 70,    // [45] tAA   address access time
                  TCE  = 70,    // [45] tCE   CE# access time
                  TOE  = 35,    // [30] tOE   OE# access time
                  TCHZ = 25,    // [15] tCHZ  CE# HIGH -> High-Z
                  TOHZ = 25;    // [15] tOHZ  OE# HIGH -> High-Z
        (a    *> dq) = TAA;
        (ce_n *> dq) = (TCE, TCE, TCHZ);
        (oe_n *> dq) = (TOE, TOE, TOHZ);
    endspecify
endmodule
`default_nettype wire
