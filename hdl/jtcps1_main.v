/*  This file is part of JTCPS1.
    JTCPS1 program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTCPS1 program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTCPS1.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 13-1-2020 */
`timescale 1ns/1ps

module jtcps1_main(
    input              rst,
    input              clk,
    input              cen10,
    input              cen10b,
    output             cpu_cen,
    // Timing
    input   [8:0]      V,
    input              LVBL,
    // PPU
    output reg         ppu1_cs,
    output reg         ppu2_cs,
    output reg         ppu_rstn,
    input   [15:0]     mmr_dout,
    // Sound
    output  reg  [7:0] snd_latch0,
    output  reg  [7:0] snd_latch1,
    output             UDSWn,
    output             LDSWn,
    // cabinet I/O
    input   [7:0]      joystick1,
    input   [7:0]      joystick2,
    input   [1:0]      start_button,
    input   [1:0]      coin_input,
    input              service,
    input              tilt,
    // BUS sharing
    input              busreq,
    output             busack,
    output             RnW,
    // For RAM/ROM:
    output      [17:1] addr,
    output      [15:0] cpu_dout,
    // RAM access
    (*keep*) output             ram_cs,
    (*keep*) output             vram_cs,
    (*keep*) input       [15:0] ram_data,
    (*keep*) input              ram_ok,
    // ROM access
    (*keep*) output  reg        rom_cs,
    (*keep*) output      [21:1] rom_addr,
    (*keep*) input       [15:0] rom_data,
    (*keep*) input              rom_ok,
    // DIP switches
    input              dip_pause,
    input              dip_test,
    input    [7:0]     dipsw_a,
    input    [7:0]     dipsw_b,
    input    [7:0]     dipsw_c
);

wire [23:1] A;
wire        BERRn = 1'b1;

//`ifdef SIMULATION
(*keep*) wire [24:0] A_full = {A,1'b0};
//`endif

(*keep*) wire        BRn, BGACKn, BGn;
(*keep*) wire        ASn;
reg         dbus_cs, io_cs, joy_cs, 
            sys_cs, olatch_cs, snd1_cs, snd0_cs;
reg         pre_ram_cs, pre_vram_cs, reg_ram_cs, reg_vram_cs;
reg         dsn_dly;
reg         one_wait;

assign cpu_cen   = cen10;
// As RAM and VRAM share contiguous spaces in the SDRAM
// it is important to prevent overlapping
assign addr      = ram_cs ? {2'b0, A[15:1] } : A[17:1];
assign rom_addr  = A[21:1];

// high during DMA transfer
wire UDSn, LDSn;
assign UDSWn = RnW | UDSn;
assign LDSWn = RnW | LDSn;

// ram_cs and vram_cs signals go down before DSWn signals
// that causes a false read request to the SDRAM. In order
// to avoid that a little bit of logic is needed:
assign ram_cs  = dsn_dly ? reg_ram_cs  : pre_ram_cs;
assign vram_cs = dsn_dly ? reg_vram_cs : pre_vram_cs;

always @(posedge clk) if(cen10) begin
    reg_ram_cs  <= pre_ram_cs;
    reg_vram_cs <= pre_vram_cs;
    dsn_dly     <= &{UDSWn,LDSWn}; // low if any DSWn was low
end

// PAL BUF1 16H
// buf0 = A[23:16]==1001_0000 = 8'h90
// buf1 = A[23:16]==1001_0001 = 8'h91
// buf2 = A[23:16]==1001_0010 = 8'h92

always @(*) begin
    rom_cs     = 1'b0;
    pre_ram_cs = 1'b0;
    pre_vram_cs= 1'b0;
    dbus_cs    = 1'b0;
    io_cs      = 1'b0;
    joy_cs     = 1'b0;
    sys_cs     = 1'b0;
    olatch_cs  = 1'b0;
    snd1_cs    = 1'b0;
    snd0_cs    = 1'b0;
    ppu1_cs    = 1'b0;
    ppu2_cs    = 1'b0;
    one_wait   = 1'b0;

    if( !ASn && BGACKn ) begin // PAL PRG1 12H
        one_wait    = A[23] | ~A[22];
        dbus_cs     = ~|A[23:18]; // all must be zero
        pre_ram_cs  = &A[23:18];
        pre_vram_cs = A[23:18] == 6'b1001_00 && A[17:16]!=2'b11;
        io_cs       = A[23:20] == 4'b1000;
        rom_cs      = A[23:22] == 2'b00;
        if( io_cs ) begin // PAL IOA1 (16P8B @ 12F)
            ppu1_cs  = A[8:6] == 3'b100; // 'h10x
            ppu2_cs  = A[8:6] == 3'b101; // 'h14x
            if( RnW ) begin
                joy_cs = A[8:3] == 6'b000_000;
                sys_cs = A[8:3] == 6'b000_011;
            end else begin // outputs
                olatch_cs = !UDSWn && A[8:3]==6'b00_0110;
                snd1_cs   = !LDSWn && A[8:3]==6'b11_0001;
                snd0_cs   = !LDSWn && A[8:3]==6'b11_0000;
            end
        end
    end    
end

/*
`ifdef SIMULATION
always @(posedge one_wait) begin
    $display("one_wait went high at %t",$time());
    #1000 $finish;
end
`endif
*/
// special registers
always @(posedge clk) begin
    if( rst ) begin
        ppu_rstn   <= 1'b0;
        snd_latch0 <= 8'd0;
        snd_latch1 <= 8'd0;
    end
    else if(cpu_cen) begin
        if( olatch_cs ) begin
            // coin counters and lockers should go in here too
            ppu_rstn <= ~cpu_dout[15];
        end
        if( snd0_cs ) snd_latch0 <= cpu_dout[7:0];
        if( snd1_cs ) snd_latch1 <= cpu_dout[7:0];
    end
end


// Cabinet input
reg [15:0] sys_data;

always @(posedge clk) begin
    if( joy_cs ) sys_data <= { joystick2, joystick1 };
    else if(sys_cs) begin
        case( A[2:1] )
            2'b00: sys_data <= { tilt, dip_test, start_button,
                1'b1, service, coin_input, 8'hff };
            2'b01: sys_data <= { dipsw_a, 8'hff };
            2'b10: sys_data <= { dipsw_b, 8'hff };
            2'b11: sys_data <= { dipsw_c, 8'hff };
        endcase
    end
end

// Data bus input
(*keep*) reg  [15:0] cpu_din;

always @(*) begin
    case( { joy_cs | sys_cs, ram_cs | vram_cs, rom_cs, ppu2_cs } )
        4'b10_00: cpu_din = sys_data;
        4'b01_00: cpu_din = ram_data;
        4'b00_10: cpu_din = rom_data;
        4'b00_01: cpu_din = mmr_dout;
        default:  cpu_din = 16'hffff;
    endcase
end

// DTACKn generation
wire       inta_n;
reg [2:0]  wait_cycles;
(*keep*) wire       bus_cs =   |{ rom_cs, pre_ram_cs, pre_vram_cs };
(*keep*) wire       bus_busy = |{ rom_cs & ~rom_ok, (pre_ram_cs|pre_vram_cs) & ~ram_ok,
                          wait_cycles[0] };
reg        DTACKn;

always @(posedge clk, posedge rst) begin : dtack_gen
    reg       last_ASn;
    if( rst ) begin
        DTACKn      <= 1'b1;
        wait_cycles <= 3'b111;
    end else /*if(cen10b)*/ begin
        last_ASn <= ASn;
        if( !ASn && last_ASn ) begin // for falling edge of ASn
            DTACKn <= 1'b1; 
            wait_cycles <= 3'b111;
        end else if( !ASn  ) begin
            // The original hardware always waits for 250ns
            // on each bus access, except if one_wait signal is
            // set low. Then it waits on a secondary input, which
            // seems to be tied high on the schematics.
            if( cen10 ) begin
                wait_cycles[2] <= 1'b0;
                wait_cycles[1] <= wait_cycles[2];
            end
            if( !wait_cycles[1] ) wait_cycles[0] <= ~one_wait;
            if( bus_cs ) begin
                if (!bus_busy) DTACKn <= 1'b0;
            end
            else DTACKn <= 1'b0;
        end
    end
end 

// interrupt generation
reg        int1, // VBLANK
           int2; // ??
(*keep*) wire [2:0] FC;
assign inta_n = ~&{ FC[2], FC[1], FC[0], ~ASn }; // interrupt ack.

always @(posedge clk, posedge rst) begin : int_gen
    reg last_LVBL, last_V256;
    if( rst ) begin
        int1 <= 1'b1;
        int2 <= 1'b1;
    end else begin
        last_LVBL <= LVBL;
        last_V256 <= V[8];

        if( !inta_n ) begin
            int1 <= 1'b1;
            int2 <= 1'b1;
        end
        else if(dip_pause) begin
            //if( V[8] && !last_V256 ) int2 <= 1'b0;
            if( !LVBL && last_LVBL ) int1 <= 1'b0;
        end
    end
end

assign busack = ~BGACKn;

jtframe_68kdma #(.BW(1)) u_arbitration(
    .clk        (  clk          ),
    .cen        ( cen10b        ),
    .rst        (  rst          ),
    .cpu_BRn    (  BRn          ),
    .cpu_BGACKn (  BGACKn       ),
    .cpu_BGn    (  BGn          ),
    .cpu_ASn    (  ASn          ),
    .cpu_DTACKn (  DTACKn       ),
    .dev_br     (  busreq       )
);

fx68k u_cpu(
    .clk        ( clk         ),
    .extReset   ( rst         ),
    .pwrUp      ( rst         ),
    .enPhi1     ( cen10       ),
    .enPhi2     ( cen10b      ),

    // Buses
    .eab        ( A           ),
    .iEdb       ( cpu_din     ),
    .oEdb       ( cpu_dout    ),


    .eRWn       ( RnW         ),
    .LDSn       ( LDSn        ),
    .UDSn       ( UDSn        ),
    .ASn        ( ASn         ),
    .VPAn       ( inta_n      ),
    .FC0        ( FC[0]       ),
    .FC1        ( FC[1]       ),
    .FC2        ( FC[2]       ),

    .BERRn      ( BERRn       ),
    // Bus arbitrion
    .HALTn      ( 1'b1        ),
    .BRn        ( BRn         ),
    .BGACKn     ( BGACKn      ),
    .BGn        ( BGn         ),

    .DTACKn     ( DTACKn      ),
    .IPL0n      ( 1'b1        ),
    .IPL1n      ( int1        ), // VBLANK
    .IPL2n      ( int2        ),

    // Unused
    .oRESETn    (             ),
    .oHALTEDn   (             ),
    .VMAn       (             ),
    .E          (             )
);

`ifdef SIMULATION
integer fdebug;

initial begin
    fdebug=$fopen("debug.log","w");
end

always @(posedge rom_cs) begin
    $fdisplay(fdebug,"%X",A_full);
end
`endif

endmodule