// Boot-loader testbench (Icarus).
//
// Loads the SINGLE assembler image into the EEPROM model, runs the boot loader,
// and verifies it reconstructs all 13 control-store SRAMs byte-for-byte. The
// loader's correctness criterion is exactly the chip-major slicing contract:
//
//     SRAM[k] addr a  ==  image[k * 2^SEG_AW + a]
//
// so we check each loaded SRAM byte against the EEPROM image directly — no
// separate expected files needed. This makes the boot-copy circuit part of the
// standard test path (toolchain.md §3.5): a functional run loads the one image
// and the loader fans it out, rather than pre-slicing the SRAMs.
//
// Build/run via sim/loader/run.sh, which passes -D IMG="<path to .hex>".
`timescale 1ns/1ps
`default_nettype none
module tb_loader;
    localparam NSEG   = 13;
    localparam SEG_AW = 13;
    localparam DEPTH  = (1 << SEG_AW);

    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    wire [16:0] rom_addr;
    wire [7:0]  rom_data;
    wire [12:0] ld_addr;
    wire [7:0]  ld_wdata;
    wire [NSEG-1:0] we;
    wire loading;

    // The loader drives the SRAM address during the copy; the checker drives it
    // afterward to read every location back.
    reg  [12:0] vaddr = 13'd0;
    wire [12:0] sram_addr = loading ? ld_addr : vaddr;

    // 128 KB control-store EEPROM (the design size; a larger in-stock part with
    // grounded upper pins presents identically). Loads exactly the microcode image.
    rom #(.AW(17), .DW(8), .FILE(`IMG), .LOADW(NSEG*DEPTH)) eeprom (
        .addr(rom_addr), .data(rom_data)
    );

    boot_loader #(.NSEG(NSEG), .SEG_AW(SEG_AW)) loader (
        .clk(clk), .rst(rst),
        .rom_addr(rom_addr), .rom_data(rom_data),
        .sram_addr(ld_addr), .sram_wdata(ld_wdata),
        .we(we), .loading(loading)
    );

    wire [7:0] rdata [0:NSEG-1];
    genvar g;
    generate for (g = 0; g < NSEG; g = g + 1) begin : chip
        sram #(.AW(SEG_AW), .DW(8)) u (
            .clk(clk), .addr(sram_addr), .wdata(ld_wdata),
            .we(we[g]), .rdata(rdata[g])
        );
    end endgenerate

    integer a, k, errors, checked;
    reg [7:0] expb, gotb;
    initial begin
        @(negedge clk); @(negedge clk);
        rst = 1'b0;

        wait (loading == 1'b0);             // copy complete
        @(negedge clk);
        $display("loader: copy done; verifying %0d chips x %0d bytes ...", NSEG, DEPTH);

        errors  = 0;
        checked = 0;
        for (a = 0; a < DEPTH; a = a + 1) begin
            vaddr = a[12:0];
            #1;                              // settle async SRAM read
            for (k = 0; k < NSEG; k = k + 1) begin
                expb = eeprom.mem[k*DEPTH + a];
                gotb = rdata[k];
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
            $display("FAIL - %0d of %0d bytes wrong", errors, checked);
        $finish;
    end

    initial begin
        #6000000;                            // > copy time (106k cycles x 10ns)
        $display("TIMEOUT - loader never deasserted");
        $finish;
    end
endmodule
`default_nettype wire
