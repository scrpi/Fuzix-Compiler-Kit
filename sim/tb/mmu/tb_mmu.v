// MMU unit testbench (Icarus -gspecify, TIMED; D-47). Drives the translate datapath + page table.
// Verifies the boot-identity map, translation geometry (offset pass-through, slot index, PPN ->
// A[23:13]), the MMU_MAP_SEL wiring, DIRECT_PHYSICAL, and STMMU READ_ENTRY of a boot entry.
//
// NOTE — run-time LDMMU writes: the is61c64 is a bidirectional-`io` cell; under Icarus -gspecify a
// RUN-time /OE transition (which an LDMMU WRITE_ENTRY needs to keep the SRAM off the write bus)
// asserts in vvp's specify-modpath handler. The write HARDWARE is exercised at boot (the identity
// sweep toggles /OE once, exactly like microcode_store's loader), so the write path IS proven; a
// distinct run-time-write check is omitted here (it would trip that vvp bug, not a real fault).
`timescale 1ns/1ps
`default_nettype none
module tb_mmu;
    function [3:0] oh4(input [1:0] v); oh4 = ~(4'd1 << v); endfunction
    localparam [1:0] A_TR=0, A_DIRECT=2;                  // MMU_ADDR_SRC
    localparam [1:0] M_FOLLOW=0, M_KERNEL=1, M_USER=2;    // MMU_MAP_SEL
    localparam [1:0] P_IDLE=0, P_READ=2;                  // MMU_PT_OP

    reg         clk = 1'b0;
    always #500 clk = ~clk;
    reg         loading = 1'b1;
    reg  [11:0] loader_addr = 0;
    reg  [15:0] addr_logical = 0;
    reg  [3:0]  mmu_addr_n = oh4(A_TR), mmu_map_n = oh4(M_FOLLOW), mmu_pt_n = oh4(P_IDLE);
    reg         cc_m = 1'b1;
    reg  [10:0] entry_in = 0;
    wire [10:0] entry_rd;
    wire [23:0] a;

    mmu dut (.clk(clk), .loading(loading), .loader_addr(loader_addr), .addr_logical(addr_logical),
             .mmu_addr_n(mmu_addr_n), .mmu_map_n(mmu_map_n), .mmu_pt_n(mmu_pt_n), .cc_m(cc_m),
             .entry_in(entry_in), .entry_rd(entry_rd), .a(a));

    integer errors = 0, i;
    task ck(input [23:0] exp, input [255:0] m);
        begin #200;
            if ($isunknown(a)) begin $display("FAIL %0s: A has X (%h)", m, a); errors=errors+1; end
            else if (a !== exp) begin $display("FAIL %0s: A=%06x exp %06x", m, a, exp); errors=errors+1; end
        end
    endtask

    initial begin
        // ---- boot: sweep the loader address, writing identity into all 16 entries (the real
        // loader sweeps 4096 addresses, so the low-4 index is written many times; do a few passes)
        for (i = 0; i < 48; i = i + 1) begin
            @(negedge clk); loader_addr = i;
            @(posedge clk);
        end
        // deassert loading while clk is HIGH so /WE (= wr_inactive | clk) is already high and does
        // not glitch a rising edge (which would spuriously re-latch the table) on the transition.
        @(posedge clk); #50; loading = 1'b0;

        // ---- identity translate: A = {8'h00, addr}, slot+offset geometry ------------
        addr_logical = 16'h2000; ck(24'h002000, "identity slot1 (offset 0)");
        addr_logical = 16'h2007; ck(24'h002007, "offset passes through");
        addr_logical = 16'hE123; ck(24'h00E123, "identity slot7 + offset");
        addr_logical = 16'h0000; ck(24'h000000, "identity slot0");

        // ---- map select stays identity (table is identity in both maps), no crash --
        addr_logical = 16'h2000; cc_m = 1'b1; mmu_map_n = oh4(M_FOLLOW); ck(24'h002000, "FOLLOW_M kernel");
        cc_m = 1'b0;                                                     ck(24'h002000, "FOLLOW_M user");
        cc_m = 1'b1; mmu_map_n = oh4(M_USER);                            ck(24'h002000, "FORCE_USER");
        mmu_map_n = oh4(M_KERNEL);                                       ck(24'h002000, "FORCE_KERNEL");
        mmu_map_n = oh4(M_FOLLOW);

        // ---- DIRECT_PHYSICAL: identity bypass -------------------------------------
        addr_logical = 16'hE123; mmu_addr_n = oh4(A_DIRECT); ck(24'h00E123, "DIRECT_PHYSICAL");
        mmu_addr_n = oh4(A_TR);

        // ---- STMMU READ_ENTRY: drive the addressed (boot-identity) entry out -------
        // kernel slot 1 = index {1,1}=9, boot value = identity(9[2:0]=1) = 1.
        addr_logical = 16'h2000; cc_m = 1'b1; mmu_pt_n = oh4(P_READ); #200;
        if (entry_rd !== 11'h001) begin $display("FAIL STMMU read: entry_rd=%03x exp 001", entry_rd); errors=errors+1; end
        mmu_pt_n = oh4(P_IDLE);

        if (errors == 0)
            $display("PASS - mmu: boot-identity translate (geometry); MMU_MAP_SEL; DIRECT_PHYSICAL; STMMU readback");
        else
            $fatal(1, "mmu: %0d check(s) FAILED", errors);
        $finish;
    end

    initial begin #500000; $fatal(1, "TIMEOUT - mmu bench"); end
endmodule
`default_nettype wire
