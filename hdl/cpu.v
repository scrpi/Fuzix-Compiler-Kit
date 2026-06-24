// cpu — BLIP top-level (SCAFFOLD). Boots its microcode, then runs. Self-contained on the
// control-store side (its own boot EEPROM + WCS); the SYSTEM BUS (A/D//RD//WR) leaves the CPU
// so the testbench can attach a memory model outside the CPU under test (R-SIM-3).
//
// The power-on handoff is driven entirely by uc_loader's `loading` output (the decoder's
// seg-13 line, which the loader's counter latches by halting). `loading` IS the boot/run
// state — there is no separate state machine. It fans out:
//   loading=1 (BOOT): the loader copies the EEPROM into the control store; the micro-PC is
//     held at 0; the architectural registers are held cleared (reg reset = rst_n & run); and
//     the memory bus is inhibited (no transfer off the meaningless boot control word).
//   loading=0 (RUN):  copy done. The micro-PC walks the store, the datapath registers follow
//     the control word, and memory transfers are live. A system reset re-runs the copy.
//
// Structure (the integrator wires real chips + the factored blocks):
//   uc_loader       -> boot loader: owns the microcode EEPROM (param FILE), copies it into the
//                      control store at power-on; emits `loading`.
//   sn74ahct04      -> run = ~loading, plus the two COUNT-enable inversions for PC/MAR.
//   sn74ahct08      -> reg reset = rst_n & run (hold the registers cleared through boot).
//   microsequencer  -> the 12-bit micro-PC (INC/JUMP/BRANCH/WAIT/DISPATCH_IR).
//   register16 (x2) -> PC and MAR: the universal '163-counter register board (D-36).
//   sn74ahct157 (x4)-> the address mux: PC vs MAR onto the MMU per MMU_ADDR_SRC.
//   memory_interface-> MDR + the external bus port (A/D//RD//WR); the MMU identity map.
//   IR  ('157 x4 + '574) -> the opcode register: latches from MDR on IR_LOAD (real fetch),
//                      or from `ir_drive` when `ir_inject` (privileged debug deposit, R-DBG-5).
//   microcode_store -> the 11 WCS SRAMs (88-bit control word) + boot path.
//   opcode_lut      -> the 2 opcode->start-address LUT SRAMs; run-addressed by {PAGE, IR}.
//   control_word_decoder -> the datapath section's one-hot strobes, now CONSUMED by the
//                      register/bus/memory datapath above (was observation-only).
//
// REAL FETCH (what this wiring newly enables): a fetch microword drives MMU_ADDR_SRC=
// TRANSLATE_PC + MEM_OP=READ, so PC addresses memory through the MMU and the byte lands in
// MDR; PC_CTRL=COUNT advances PC off-bus; a following IR_LOAD=OPCODE latches IR from MDR and
// DISPATCH_IR vectors on it. The opcode now arrives from memory, not from `ir_drive`.
//
// SCAFFOLD (hardware.md §2 still landing): the Z bus is currently driven only by MDR (the
// read path) — the ALU and the register LEFT drivers are not built, so `LEFT_SRC`/`Z_DEST`
// for the ALU side and PC/MAR load-from-Z high byte are inert. The CC/flag datapath is also
// absent, so the microconditions still come from the `cond_drive` debug tap.
`timescale 1ns/1ps
`default_nettype none
module cpu #(
    parameter FILE = ""              // the microcode image (burned into the loader's EEPROM)
) (
    input  wire         clk,
    input  wire         rst_n,       // active-low power-on reset
    // privileged debug interface (R-DBG-5)
    input  wire         ir_inject,   // 1 = force IR from ir_drive (debug); 0 = real fetch (IR<-MDR)
    input  wire [7:0]   ir_drive,    // debug opcode deposit (used when ir_inject)
    input  wire [15:0]  cond_drive,  // CC/microcondition lines (the CC datapath is not built yet)
    // system bus — memory is modelled in the harness (R-SIM-3; interface.md §2)
    output wire [23:0]  a,           // physical address A[23:0]
    inout  wire [7:0]   d,           // data bus D[7:0]
    output wire         rd_n,        // /RD
    output wire         wr_n,        // /WR
    // observability — privileged debug taps (R-DBG-5)
    output wire         loading,     // HIGH while the boot copy runs
    output wire [11:0]  upc,         // the micro-PC once running
    output wire [87:0]  cw,          // the 88-bit control word read from the WCS
    output wire [11:0]  lut_out,     // opcode-LUT dispatch target {lut_hi[3:0], lut_lo}
    output wire [7:0]   ir_q,        // IR contents (the dispatch index)
    output wire [15:0]  pc_q         // PC contents
);
    localparam NSEG  = 13;           // 11 WCS + 2 opcode-LUT

    wire [11:0]     loader_addr;     // loader's control-store address during boot
    wire [7:0]      loader_wdata;    // loader's boot write data (= the EEPROM byte)
    wire [NSEG-1:0] cs_sel_n;        // per-chip select (active low) from the loader
    wire            run;             // = ~loading

    wire [87:0]     cw_wcs;          // the 88-bit control word (WCS SRAMs 0..10)

    // --- boot loader: owns the microcode EEPROM, copies it -> control store --
    (* purpose = "microcode loader" *)
    uc_loader #(.FILE(FILE)) loader (
        .clk(clk), .rst_n(rst_n),
        .sram_addr(loader_addr), .sram_wdata(loader_wdata),
        .cs_n(cs_sel_n), .loading(loading)
    );

    // --- control-word decoder: datapath section -> one-hot datapath strobes --
    // The 64-bit datapath section is cw_wcs[87:24]. Only the fields the current datapath
    // consumes are wired out; the rest stay internal (still observable as dut.dec.*).
    wire [3:0]  ir_load_n;
    wire [15:0] left_src_n;
    wire [3:0]  pc_ctrl_n, mar_ctrl_n;
    wire [3:0]  mem_op_n, mmu_addr_n;
    wire [15:0] z_dest_n;
    (* purpose = "datapath decoder" *)
    control_word_decoder dec (
        .cw_dp(cw_wcs[87:24]),
        .ir_load_n(ir_load_n), .left_src_n(left_src_n),
        .pc_ctrl_n(pc_ctrl_n), .mar_ctrl_n(mar_ctrl_n),
        .mem_op_n(mem_op_n), .mmu_addr_n(mmu_addr_n), .z_dest_n(z_dest_n)
    );

    // --- inverters: run = ~loading, and the PC/MAR COUNT enables ------------
    // PC_CTRL/MAR_CTRL=COUNT is the active-low strobe *_ctrl_n[2]; the '163 ENP wants it
    // active HIGH, so invert. (load_n and drive_left_n already match the '163/'541 pins.)
    wire [5:0] inv_y;
    (* purpose = "run=~loading; PC/MAR count enables" *)
    sn74ahct04 inv (.a({3'b000, mar_ctrl_n[2], pc_ctrl_n[2], loading}), .y(inv_y));
    assign run          = inv_y[0];      // ~loading
    wire   pc_count_en  = inv_y[1];      // ~PC_CTRL[COUNT]
    wire   mar_count_en = inv_y[2];      // ~MAR_CTRL[COUNT]

    // --- reg reset = rst_n & run (hold registers cleared through the boot copy) --
    wire [3:0] and_y;
    (* purpose = "reg reset = rst_n & run" *)
    sn74ahct08 rstgate (.a({3'b000, rst_n}), .b({3'b000, run}), .y(and_y));
    wire reg_reset_n = and_y[0];

    // --- PC and MAR: two universal '163-counter register boards (D-36) ------
    // Z bus: currently driven only by MDR (the read path). A FULL16 load takes both bytes
    // (load_lo_n = load_hi_n = *_CTRL[LOAD]); COUNT is the off-bus +1; LEFT drive is dormant
    // (no ALU consumer yet) but wired to the real LEFT_SRC strobe.
    wire [7:0]  mdr_q;
    wire [15:0] z = {8'h00, mdr_q};
    wire [15:0] pc_w, mar_w;
    wire [15:0] pc_left, mar_left;       // LEFT drives (unused until the ALU lands)

    (* purpose = "PC register" *)
    register16 pc_reg (
        .clk(clk), .reset_n(reg_reset_n), .z_in(z),
        .load_lo_n(pc_ctrl_n[1]), .load_hi_n(pc_ctrl_n[1]),
        .count_en(pc_count_en), .drive_left_n(left_src_n[6]),
        .q(pc_w), .left_out(pc_left)
    );
    (* purpose = "MAR register" *)
    register16 mar_reg (
        .clk(clk), .reset_n(reg_reset_n), .z_in(z),
        .load_lo_n(mar_ctrl_n[1]), .load_hi_n(mar_ctrl_n[1]),
        .count_en(mar_count_en), .drive_left_n(left_src_n[7]),
        .q(mar_w), .left_out(mar_left)
    );
    assign pc_q = pc_w;

    // --- address mux: PC vs MAR onto the MMU per MMU_ADDR_SRC ---------------
    // sel = mmu_addr_n[1] (TRANSLATE_PC active-low): 0 -> PC, else MAR (DIRECT_PHYSICAL maps
    // here too, harmlessly, until that path is built).
    wire [15:0] addr_logical;
    (* purpose = "addr mux PC/MAR [3:0]" *)
    sn74ahct157 am0 (.a(pc_w[3:0]),   .b(mar_w[3:0]),   .sel(mmu_addr_n[1]), .g_n(1'b0), .y(addr_logical[3:0]));
    (* purpose = "addr mux PC/MAR [7:4]" *)
    sn74ahct157 am1 (.a(pc_w[7:4]),   .b(mar_w[7:4]),   .sel(mmu_addr_n[1]), .g_n(1'b0), .y(addr_logical[7:4]));
    (* purpose = "addr mux PC/MAR [11:8]" *)
    sn74ahct157 am2 (.a(pc_w[11:8]),  .b(mar_w[11:8]),  .sel(mmu_addr_n[1]), .g_n(1'b0), .y(addr_logical[11:8]));
    (* purpose = "addr mux PC/MAR [15:12]" *)
    sn74ahct157 am3 (.a(pc_w[15:12]), .b(mar_w[15:12]), .sel(mmu_addr_n[1]), .g_n(1'b0), .y(addr_logical[15:12]));

    // --- MDR + external bus port (the MMU identity map + the system-bus pins) --
    wire [7:0] mdr_left;             // MDR -> LEFT low lane (unused until the ALU lands)
    (* purpose = "MDR + memory bus port" *)
    memory_interface mi (
        .clk(clk),
        .mem_op_n(mem_op_n), .z_dest_mdr_n(z_dest_n[7]), .left_src_mdr_n(left_src_n[10]),
        .bus_inhibit(loading),
        .addr(addr_logical), .z_lo(z[7:0]),
        .mdr_q(mdr_q), .left_lo(mdr_left),
        .a(a), .d(d), .rd_n(rd_n), .wr_n(wr_n)
    );

    // --- opcode register IR: latch from MDR on IR_LOAD, or from ir_drive (debug) --
    // inner mux: IR_LOAD=OPCODE -> MDR (the fetched byte); else hold IR. (sel=ir_load_n[1]:
    // 0=OPCODE picks A=MDR, 1=HOLD picks B=IR.) outer mux: ir_inject picks ir_drive over the
    // inner result. The '574 registers it, breaking the hold feedback loop.
    wire [7:0] ir, ir_inner, ir_d;
    (* purpose = "IR src: MDR vs hold [3:0]" *)
    sn74ahct157 iri0 (.a(mdr_q[3:0]), .b(ir[3:0]), .sel(ir_load_n[1]), .g_n(1'b0), .y(ir_inner[3:0]));
    (* purpose = "IR src: MDR vs hold [7:4]" *)
    sn74ahct157 iri1 (.a(mdr_q[7:4]), .b(ir[7:4]), .sel(ir_load_n[1]), .g_n(1'b0), .y(ir_inner[7:4]));
    (* purpose = "IR src: inject vs fetch [3:0]" *)
    sn74ahct157 iro0 (.a(ir_inner[3:0]), .b(ir_drive[3:0]), .sel(ir_inject), .g_n(1'b0), .y(ir_d[3:0]));
    (* purpose = "IR src: inject vs fetch [7:4]" *)
    sn74ahct157 iro1 (.a(ir_inner[7:4]), .b(ir_drive[7:4]), .sel(ir_inject), .g_n(1'b0), .y(ir_d[7:4]));
    (* purpose = "opcode register IR" *)
    sn74ahct574 ir_reg (.Q(ir), .D(ir_d), .CLK(clk), .OE_n(1'b0));
    assign ir_q = ir;

    // --- microsequencer: computes the next micro-PC from the sequencer section --
    wire [11:0] lut_data;
    (* purpose = "micro-sequencer (next uPC)" *)
    microsequencer useq (
        .clk(clk), .clr_n(run),
        .useq_op(cw_wcs[2:0]), .next_addr(cw_wcs[14:3]),
        .ucond_sel(cw_wcs[18:15]), .ucond_pol(cw_wcs[19]),
        .cond(cond_drive), .lut_data(lut_data), .upc(upc)
    );

    // --- control store: 11 WCS chips (the 88-bit word) + 2 opcode-LUT chips --
    wire [7:0]  lut_lo, lut_hi;     // opcode-LUT bytes (SRAMs 11, 12)
    (* purpose = "WCS (88-bit control word)" *)
    microcode_store #(.NWCS(11)) store (
        .clk(clk), .upc(upc), .loader_addr(loader_addr), .loading(loading),
        .wdata(loader_wdata), .wbuf_oe_n(run), .oe_n(loading),
        .cs_n(cs_sel_n[10:0]), .cw(cw_wcs)
    );
    (* purpose = "opcode LUT (dispatch)" *)
    opcode_lut lut (
        .clk(clk), .loader_addr(loader_addr), .dispatch_page(cw_wcs[22]), .ir(ir), .loading(loading),
        .wdata(loader_wdata), .wbuf_oe_n(run), .oe_n(loading),
        .cs_n(cs_sel_n[12:11]), .lut_lo(lut_lo), .lut_hi(lut_hi)
    );

    assign cw       = cw_wcs;
    assign lut_data = {lut_hi[3:0], lut_lo};
    assign lut_out  = lut_data;
endmodule
`default_nettype wire
