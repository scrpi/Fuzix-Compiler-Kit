// Microcode loader (uc_loader) — fans the single EEPROM image out to the 13 control-store SRAMs
// at power-on, then releases the CPU (D-03, R-CTRL-3; refined by the single-
// EEPROM decision). One reflashable image; the loader distributes it.
//
// The image is CHIP-MAJOR with uniform 2^SEG_AW segments, so the loader is pure
// binary address-slicing — no mod-N counter, no per-chip depth special-casing:
//
//     a 17-bit counter walks 0 .. NSEG*2^SEG_AW - 1
//        rom_addr   = cnt                         (drive the EEPROM)
//        sram_addr  = cnt[SEG_AW-1:0]             (shared to all 13 SRAMs)
//        we one-hot = decode(cnt[.. :SEG_AW])     (cnt's high bits pick the chip)
//        sram_wdata = rom_data                    (EEPROM byte, async)
//
//   In hardware: a 74-series counter ('161 chain) + a 4:16 decoder ('154) on the
//   high bits + a shared write-data/address bus. This is the FUNCTIONAL model of
//   that circuit; structural 74-series form + datasheet timing come later
//   (toolchain.md §4.1). `loading` is high during the copy and gates the CPU.
`timescale 1ns/1ps
`default_nettype none
module uc_loader #(
    parameter NSEG   = 13,      // 11 WCS + 2 opcode-map
    parameter SEG_AW = 13       // uniform 8 Kword segment per chip
) (
    input  wire               clk,
    input  wire               rst,        // active-high; held at power-on
    output wire [SEG_AW+3:0]  rom_addr,   // 17-bit EEPROM address (4 seg bits + SEG_AW)
    input  wire [7:0]         rom_data,
    output wire [SEG_AW-1:0]  sram_addr,  // shared to every SRAM
    output wire [7:0]         sram_wdata, // shared write data
    output wire [NSEG-1:0]    we,         // one-hot per-chip write enable
    output reg                loading
);
    localparam LAST = NSEG * (1 << SEG_AW) - 1;   // last byte index to copy

    reg [SEG_AW+3:0] cnt;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt     <= 0;
            loading <= 1'b1;
        end else if (loading) begin
            if (cnt == LAST) loading <= 1'b0;
            cnt <= cnt + 1'b1;
        end
    end

    wire [3:0] seg = cnt[SEG_AW+3:SEG_AW];        // which chip this byte belongs to

    assign rom_addr   = cnt;
    assign sram_addr  = cnt[SEG_AW-1:0];
    assign sram_wdata = rom_data;
    assign we = (loading && !rst) ? ({{(NSEG-1){1'b0}}, 1'b1} << seg)
                                  : {NSEG{1'b0}};
endmodule
`default_nettype wire
