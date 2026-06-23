// Microcode loader (uc_loader) — structural netlist of real chips.
//
// At power-on it copies the single boot EEPROM image into the 13 control-store
// SRAMs, then releases the CPU (D-03, R-CTRL-3; single-EEPROM model D-43). It is
// independent of the CPU — just a counter, a decoder, and its onboard boot EEPROM;
// it streams that image out to the external control-store SRAMs (the WCS, which the
// run-path micro-PC also reads, so they live at the top level, not here).
//
// Structure (the BOM — R-SIM-1, R-SIM-5):
//   * 1x sst39sf010a -> the boot EEPROM, pre-burned with the microcode image (param
//     FILE). The loader's onboard source: read-only here (CE#/OE# tied low, WE# high),
//     its whole address space walked by the counter.
//   * 4x cd74act161  -> a 16-bit binary address counter `cnt`. Async-cleared to 0 by
//     the active-low boot reset; ripple-carry cascade (RCO -> next ENT). (12-bit
//     segment address + 4-bit chip field; the 4096-word store needs no 5th '161.)
//   * 2x sn74ahct138  -> a 4->16 decoder of the chip field seg = cnt[15:12] (a '154 is
//     unobtainable). The low 3 seg bits drive A,B,C of both; cnt[15] picks the
//     half via the complementary enable polarities, so NO inverter is needed.
//
// The decoder does triple duty and removes all glue logic:
//   * Y0..Y12  -> the 13 active-low per-chip selects (`cs_n`).
//   * Y13      -> the done/`loading` line. It is HIGH while seg<13 (copying) and
//     LOW once the counter reaches seg 13 (one past the last chip). Fed back as
//     the count enable, it stops the counter on itself — no comparator, no
//     loading flip-flop. (Y14, Y15 are unused.)
//
// Reset is taken ACTIVE-LOW (`rst_n`, the natural POR/supervisor convention) so it
// drives the '161 CLR# directly and the '138 halves with no inverter. During reset
// the counter is held at 0, so chip 0 address 0 is (harmlessly, idempotently)
// written its own byte; `loading` is HIGH, holding the CPU off.
//
// The actual /WE pulse per chip is the decoder select combined with a clock phase
// (a clean strobe so the byte latches with the address stable) — that clock-gating
// lives in the board/testbench, not here, so this module stays purely structural.
`timescale 1ns/1ps
`default_nettype none
module uc_loader #(
    parameter NSEG   = 13,      // 11 WCS + 2 opcode-LUT  (fixed: the 2x '138 decode)
    parameter SEG_AW = 12,      // 4 Kword per chip       (fixed: the low counter bits)
    parameter FILE   = ""       // the microcode image pre-burned into the boot EEPROM
) (
    input  wire               clk,
    input  wire               rst_n,      // active-LOW boot reset (held low at power-on)
    output wire [SEG_AW-1:0]  sram_addr,  // shared SRAM address (= cnt low bits)
    output wire [7:0]         sram_wdata, // shared write data (= EEPROM byte, a bus wire)
    output wire [NSEG-1:0]    cs_n,       // per-chip select, active LOW (decoder Y0..Y12)
    output wire               loading     // HIGH during copy (decoder seg-13 line)
);
    localparam DEPTH = (1 << SEG_AW);   // words per chip (4096)
    // ---- 16-bit address counter: four '161s, ripple-carry cascade ----------
    wire [15:0] cnt;            // 12-bit segment address (cnt[11:0]) + 4-bit seg (cnt[15:12])
    wire [3:0]  rco;            // ripple carry out of each stage (rco[3] unused)
    wire        count_en;       // = loading: counts while seg < 13, then halts

    cd74act161 c0 (.clk(clk), .clr_n(rst_n), .load_n(1'b1), .enp(count_en), .ent(count_en),
                .p(4'b0000), .q(cnt[3:0]),   .rco(rco[0]));
    cd74act161 c1 (.clk(clk), .clr_n(rst_n), .load_n(1'b1), .enp(count_en), .ent(rco[0]),
                .p(4'b0000), .q(cnt[7:4]),   .rco(rco[1]));
    cd74act161 c2 (.clk(clk), .clr_n(rst_n), .load_n(1'b1), .enp(count_en), .ent(rco[1]),
                .p(4'b0000), .q(cnt[11:8]),  .rco(rco[2]));
    cd74act161 c3 (.clk(clk), .clr_n(rst_n), .load_n(1'b1), .enp(count_en), .ent(rco[2]),
                .p(4'b0000), .q(cnt[15:12]), .rco(rco[3]));

    // ---- 4->16 decode of seg = cnt[15:12]: two '138s -----------------------
    // Low '138: enabled when cnt[15]=0 (G2A# = cnt[15]); outputs seg 0..7.
    // High '138: enabled when cnt[15]=1 (G1   = cnt[15]); outputs seg 8..15.
    wire [7:0] dlo, dhi;
    sn74ahct138 dec_lo (.a(cnt[SEG_AW]), .b(cnt[SEG_AW+1]), .c(cnt[SEG_AW+2]),
                    .g1(1'b1), .g2a_n(cnt[SEG_AW+3]), .g2b_n(1'b0), .y(dlo));
    sn74ahct138 dec_hi (.a(cnt[SEG_AW]), .b(cnt[SEG_AW+1]), .c(cnt[SEG_AW+2]),
                    .g1(cnt[SEG_AW+3]), .g2a_n(1'b0), .g2b_n(1'b0), .y(dhi));

    // ---- boot EEPROM: the loader's onboard microcode source ----------------
    // Pre-burned with the image (param FILE); read-only (CE#/OE# low, WE# high). The
    // counter walks its whole address space; the byte read becomes the SRAM write data.
    wire [SEG_AW+3:0] rom_addr = cnt[SEG_AW+3:0];   // 16-bit EEPROM address (= cnt)
    wire [7:0]        rom_data;                     // the byte currently under rom_addr
    (* purpose = "microcode image (boot ROM)" *)
    sst39sf010a #(.AW(17), .DW(8), .FILE(FILE), .LOADW(NSEG*DEPTH)) eeprom (
        .a({1'b0, rom_addr}), .dq(rom_data), .ce_n(1'b0), .oe_n(1'b0), .we_n(1'b1)
    );

    // ---- pure wiring -------------------------------------------------------
    assign cs_n       = {dhi[4:0], dlo[7:0]};   // seg 12..0 selects (active low)
    assign loading    = dhi[5];                 // seg-13 line: HIGH copying, LOW done
    assign count_en   = dhi[5];                 // counter halts itself at seg 13
    assign sram_addr  = cnt[SEG_AW-1:0];        // = cnt[11:0]
    assign sram_wdata = rom_data;               // shared EEPROM/SRAM data bus
endmodule
`default_nettype wire
