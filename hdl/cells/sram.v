// Behavioral async SRAM — models one control-store SRAM (8 Kx8). Async read;
// synchronous write port used by the boot loader at power-on (after boot the
// WCS is read-only to the running CPU). All 13 control-store chips (11 WCS +
// 2 opcode-map) are this part; the map chips use only their low 512 words at
// run time but are loaded uniformly (see boot_loader.v). FUNCTIONAL model;
// datasheet timing added later (toolchain.md §10.3).
`timescale 1ns/1ps
`default_nettype none
module sram #(
    parameter AW = 13,          // 2^13 = 8 Kword
    parameter DW = 8
) (
    input  wire          clk,
    input  wire [AW-1:0] addr,
    input  wire [DW-1:0] wdata,
    input  wire          we,
    output wire [DW-1:0] rdata
);
    reg [DW-1:0] mem [0:(1<<AW)-1];
    always @(posedge clk) if (we) mem[addr] <= wdata;
    assign rdata = mem[addr];
endmodule
`default_nettype wire
