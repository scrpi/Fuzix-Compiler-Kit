// opcode_lut — the opcode→start-address LUT: the 2 byte-wide SRAMs that translate
// {DISPATCH_PAGE, IR} into a microroutine's 12-bit start address, plus the boot-write path
// and the run-time address mux. Structural netlist of real chips (R-SIM-1, R-SIM-5;
// microcode.md §2, D-40/D-41, D-49).
//
// The LUT holds 512 entries ({PAGE, IR} = 9 bits); each entry's 12-bit µPC start address
// is split low byte (chip 0) + high 4 bits (chip 1). Addressing:
//   boot (loading=1): the shared loader address — the copy writes all 4096 words.
//   run  (loading=0): {3'b000, DISPATCH_PAGE, IR} — the opcode indexes its routine entry,
//                     which the microsequencer loads into µPC on DISPATCH_IR.
//
// Structure (the BOM):
//   3x sn74ahct157  -> the 12-bit address mux (SEL = loading ? loader_addr : {PAGE, IR}).
//   2x sn74ahct541  -> boot-write isolation buffers (enabled in boot, tri-stated in run).
//   2x is61c64      -> the LUT SRAMs (8 K part, A12 grounded; D-49). /CE low; /OE = oe_n
//                      (= loading); /WE the per-chip strobe.
`timescale 1ns/1ps
`default_nettype none
module opcode_lut (
    input  wire [11:0] loader_addr,  // boot: the shared control-store address (loader counter)
    input  wire        dispatch_page,// run: opcode-LUT page (control-word DISPATCH_PAGE)
    input  wire [7:0]  ir,           // run: the opcode register
    input  wire        loading,      // 1 = boot (loader_addr), 0 = run ({PAGE, IR})
    input  wire [7:0]  wdata,        // boot write data (= the EEPROM byte)
    input  wire        wbuf_oe_n,    // boot-write buffer enable, active LOW (= run)
    input  wire        oe_n,         // SRAM /OE, active LOW (= loading)
    input  wire [1:0]  we_n,         // per-chip /WE strobe (active LOW): [0]=low byte, [1]=high
    output wire [7:0]  lut_lo,       // entry low byte  (SRAM 0)
    output wire [7:0]  lut_hi        // entry high byte (SRAM 1; only the low 4 bits are used)
);
    // address mux: run = {PAGE, IR} (512-entry LUT), boot = loader address
    wire [11:0] run_addr = {3'b000, dispatch_page, ir};
    wire [11:0] addr;
    sn74ahct157 a0 (.a(run_addr[3:0]),  .b(loader_addr[3:0]),  .sel(loading), .g_n(1'b0), .y(addr[3:0]));
    sn74ahct157 a1 (.a(run_addr[7:4]),  .b(loader_addr[7:4]),  .sel(loading), .g_n(1'b0), .y(addr[7:4]));
    sn74ahct157 a2 (.a(run_addr[11:8]), .b(loader_addr[11:8]), .sel(loading), .g_n(1'b0), .y(addr[11:8]));

    // the 2 LUT SRAMs + their boot-write buffers
    wire [7:0] io [0:1];
    genvar g;
    generate for (g = 0; g < 2; g = g + 1) begin : chip
        sn74ahct541 wbuf (.a(wdata), .oe1_n(wbuf_oe_n), .oe2_n(1'b0), .y(io[g]));
        is61c64 #(.AW(13), .DW(8)) sram (
            .a({1'b0, addr}), .io(io[g]), .ce_n(1'b0), .oe_n(oe_n), .we_n(we_n[g])
        );
    end endgenerate
    assign lut_lo = io[0];
    assign lut_hi = io[1];
endmodule
`default_nettype wire
