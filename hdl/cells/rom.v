// Behavioral ROM — models the single boot EEPROM (the 128 KB control-store part,
// D-03/D-43). Async (combinational) read — the boot loader only reads at power-on.
// This EEPROM holds ONLY the control-store image (WCS + opcode-map SRAMs); its
// spare capacity is unused (the firmware monitor/loader is a separate system ROM
// in the memory map, D-31). The physical board may populate this with a larger
// in-stock part whose upper address pins are grounded — it presents identically,
// so the model stays at the 128 KB design size. FUNCTIONAL model; datasheet specify
// timing is attached later (toolchain.md §10.3) when the boot-copy fidelity is
// itself under timing test. The contents are the assembler's single image
// (microcode/build/blip_microcode.hex) — the exact bytes the EEPROM is burned
// with (toolchain.md P1, R-SIM-2).
`timescale 1ns/1ps
`default_nettype none
module rom #(
    parameter AW    = 17,       // 2^17 = 128 KiB control-store EEPROM
    parameter DW    = 8,
    parameter FILE  = "",
    parameter LOADW = 0         // words to load from FILE (0 = whole array)
) (
    input  wire [AW-1:0] addr,
    output wire [DW-1:0] data
);
    reg [DW-1:0] mem [0:(1<<AW)-1];
    initial if (FILE != "") begin
        // Load exactly LOADW words when given (the microcode image fills only the
        // low region of the part), else the whole array.
        if (LOADW != 0) $readmemh(FILE, mem, 0, LOADW-1);
        else            $readmemh(FILE, mem);
    end
    assign data = mem[addr];
endmodule
`default_nettype wire
