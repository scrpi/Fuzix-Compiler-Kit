// Microcode-loader testbench (Icarus).
//
// Loads the SINGLE assembler image into the EEPROM model, runs the microcode loader,
// and verifies it reconstructs all 13 control-store SRAMs byte-for-byte. The
// SRAMs are the real async part (is61c64), wired the way the board wires them:
//
//   /CE  tied LOW (chips always selected)
//   /OE  HIGH during the copy (loader drives the shared write-data bus), LOW
//        afterward so the checker can read every chip back
//   /WE  the loader's active-low per-chip select (cs_n[g], a '138 decoder output)
//        ORed with the clock: /WE = cs_n[g] | clk. For the selected chip it pulses
//        LOW while clk is LOW (address/data set up) and rises at the next posedge,
//        latching the byte with the address still valid (is61c64 captures on
//        posedge /WE). This clock-gating is board glue, kept out of the structural
//        loader (hardware.md, D-43).
//
// The loader's correctness criterion is exactly the chip-major slicing contract:
//
//     SRAM[k] addr a  ==  image[k * 2^SEG_AW + a]
//
// so we check each loaded SRAM byte against the EEPROM image directly — no
// separate expected files needed. This makes the boot-copy circuit part of the
// standard test path (toolchain.md §3.5): a functional run loads the one image
// and the loader fans it out, rather than pre-slicing the SRAMs.
//
// Build/run via sim/tb/loader/run.sh (Icarus -gspecify, TIMED; passes -D IMG=...).
// The loader is clocked at a realistic slow boot rate (~500 kHz) so the real cell
// delays are exercised — the 70 ns flash read, 15 ns counter, 10 ns SRAM — and the
// run $fatals on any byte mismatch or timeout (D-47: Icarus is always timed).
`timescale 1ns/1ps
`default_nettype none
module tb_loader;
    localparam NSEG   = 13;
    localparam SEG_AW = 13;
    localparam DEPTH  = (1 << SEG_AW);

    reg clk = 1'b0;
    reg rst_n = 1'b0;                    // active-low boot reset, asserted at t=0
    always #1000 clk = ~clk;            // ~500 kHz boot clock (slow 555); 2 us period
                                        // >> the 70 ns flash read + 15 ns counter clk->Q

    wire [16:0] rom_addr;
    wire [7:0]  rom_data;
    wire [12:0] ld_addr;
    wire [7:0]  ld_wdata;
    wire [NSEG-1:0] cs_n;               // per-chip select, active low (decoder Y0..Y12)
    wire loading;

    // The loader drives the SRAM address during the copy; the checker drives it
    // afterward to read every location back. One shared address bus to all chips.
    reg  [12:0] vaddr = 13'd0;
    wire [12:0] sram_addr = loading ? ld_addr : vaddr;

    // 128 KB control-store EEPROM — the real flash part (sst39sf010a). The loader
    // only reads, so CE#/OE# are tied LOW (continuously selected/output-enabled)
    // and WE# HIGH (no in-system program). A larger pin-compatible part with
    // grounded upper pins presents identically. Loads exactly the microcode image.
    sst39sf010a #(.AW(17), .DW(8), .FILE(`IMG), .LOADW(NSEG*DEPTH)) eeprom (
        .a(rom_addr), .dq(rom_data),
        .ce_n(1'b0), .oe_n(1'b0), .we_n(1'b1)
    );

    uc_loader #(.NSEG(NSEG), .SEG_AW(SEG_AW)) loader (
        .clk(clk), .rst_n(rst_n),
        .rom_addr(rom_addr), .rom_data(rom_data),
        .sram_addr(ld_addr), .sram_wdata(ld_wdata),
        .cs_n(cs_n), .loading(loading)
    );

    // Board wiring of the 13 real SRAMs (is61c64).
    wire [7:0] io [0:NSEG-1];           // per-chip bidirectional data bus
    genvar g;
    generate for (g = 0; g < NSEG; g = g + 1) begin : chip
        // /WE = cs_n[g] | clk: for the selected chip (cs_n[g] low) it pulses low
        // while clk is low and rises at posedge to latch; high otherwise. When the
        // copy ends (seg 13) all cs_n are high, so /WE stays high. Board glue.
        wire we_n = cs_n[g] | clk;
        // /OE: outputs off during the copy, on for read-back.
        wire oe_n = loading;
        // Shared write-data bus the loader drives during the copy; released
        // (High-Z) afterward so the chip drives its own data for read-back.
        assign io[g] = loading ? ld_wdata : 8'bz;

        is61c64 #(.AW(SEG_AW), .DW(8)) u (
            .a(sram_addr), .io(io[g]),
            .ce_n(1'b0), .oe_n(oe_n), .we_n(we_n)
        );
    end endgenerate

    integer a, k, errors, checked;
    reg [7:0] expb, gotb;
    initial begin
        @(negedge clk); @(negedge clk);
        rst_n = 1'b1;                        // release boot reset

        wait (loading == 1'b0);             // copy complete
        @(negedge clk);
        $display("loader: copy done; verifying %0d chips x %0d bytes ...", NSEG, DEPTH);

        errors  = 0;
        checked = 0;
        for (a = 0; a < DEPTH; a = a + 1) begin
            vaddr = a[12:0];
            #100;                            // settle the timed SRAM read (tAA 10 ns)
            for (k = 0; k < NSEG; k = k + 1) begin
                expb = eeprom.mem[k*DEPTH + a];
                gotb = io[k];
                checked = checked + 1;
                if (gotb !== expb) begin
                    errors = errors + 1;
                    if (errors <= 8)
                        $display("  MISMATCH chip %0d addr %0d: got %02x exp %02x",
                                 k, a, gotb, expb);
                end
            end
        end

        if (errors == 0)
            $display("PASS - loader reconstructed all %0d bytes from the single image",
                     checked);
        else
            $fatal(1, "FAIL - %0d of %0d bytes wrong", errors, checked);
        $finish;
    end

    initial begin
        #300000000;                          // > copy time (106k cycles x 2 us ~= 213 ms)
        $fatal(1, "TIMEOUT - loader never deasserted");
    end
endmodule
`default_nettype wire
