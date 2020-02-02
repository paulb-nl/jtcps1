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

// Scroll 1 is 512x512, 8x8 tiles
// Scroll 2 is 1024x1024 16x16 tiles
// Scroll 3 is 2048x2048 32x32 tiles

module jtcps1_tilemap(
    input              rst,
    input              clk,

    input      [ 8:0]  vrender, // 1 line ahead of vdump
    input      [ 2:0]  size,    // hot one encoding. bit 0=8x8, bit 1=16x16, bit 2=32x32
    // control registers
    input      [15:0]  vram_base,
    input      [15:0]  hpos,
    input      [15:0]  vpos,

    input              start,
    output reg         done,

    output reg [23:1]  vram_addr,
    input      [15:0]  vram_data,
    input              vram_ok,
    output reg         vram_cs,

    output reg [22:0]  rom_addr,    // up to 1 MB
    output reg         rom_half,    // selects which half to read
    input      [31:0]  rom_data,
    output reg         rom_cs,
    input              rom_ok,

    output reg [ 8:0]  buf_addr,
    output reg [ 8:0]  buf_data,
    output reg         buf_wr
);

reg [10:0] vn;
reg [10:0] hn;
reg [31:0] pxl_data;

reg [ 5:0] st;
reg [ 5:0] tilecnt;
reg [ 5:0] tilemax;

reg [21:0] tile_addr;
reg [15:0] code,attr;

reg  [11:0] scan;
reg  [ 2:0] rom_id;

always @(*) begin
    case(size)
        3'b1:  begin
            scan    = { vn[8],   hn[8:3], vn[7:3] };
            rom_id  = 3'b001;
            tilemax = 6'd57; /* 8x8 tiles */
        end
        3'b10: begin
            scan    = { vn[9:8], hn[9:4], vn[7:4] };
            rom_id  = 3'b010;
            tilemax = 6'd29; /* 16x16 tiles */
        end
        3'b100: begin
            scan = { vn[10:8], hn[10:5], vn[7:5] };
            rom_id = 3'b011;
            tilemax = 6'd15; /* 32x32 tiles */
        end
    endcase
end

function [3:0] colour;
    input [31:0] c;
    input        flip;
    colour = flip ? { c[24], c[16], c[ 8], c[0] } : 
                    { c[31], c[23], c[15], c[7] };
endfunction

wire     vflip = attr[6];
wire     hflip = attr[5];
wire [4:0] pal = attr[4:0];
// assign rom_half = hn[3] ^ hflip;

always @(posedge clk or posedge rst) begin
    if(rst) begin
        rom_cs          <= 1'b0;
        vram_cs         <= 1'b0;
        buf_wr          <= 1'b0;
        done            <= 1'b0;
        st              <= 0;
        rom_addr        <= 23'd0;
        code            <= 16'd0;
    end else begin
        st <= st+1;
        case( st ) 
            0: begin
                rom_addr[22:20] <= rom_id;
                rom_cs   <= 1'b0;
                vram_cs  <= 1'b0;
                /* verilator lint_off WIDTH */
                vn       <= vpos + {7'd0, vrender};
                /* verilator lint_on WIDTH */
                hn       <= 
                      size[0] ? { hpos[10:3], 3'b0 } :
                    ( size[1] ? { hpos[10:4], 4'b0 } : { hpos[10:5], 5'b0 } );
                buf_addr <= 9'h1ff- (
                    size[0] ? {2'b0, hpos[2:0]} : (size[1] ? {1'b0,hpos[3:0]} : hpos[4:0]) );
                tilecnt  <= 6'b0;
                buf_wr   <= 1'b0;
                done     <= 1'b0;
                if(!start) begin
                    st   <= 0;
                end
            end
            1: begin
                vram_addr <= { vram_base, 7'd0 } + { 10'd0, scan, 1'b0};
                vram_cs   <= 1'b1;
            end
            3: begin
                if( vram_ok ) begin
                    code         <= vram_data;
                    vram_addr[1] <= 1'b1;
                    st <= 50;
                end else st<=st;
            end
            51: begin
                if( vram_ok ) begin
                    attr    <= vram_data;
                    st <= 4;
                end else st<=st;
                end
            4: begin
                rom_half <= hflip;
                case (1'b1)
                    size[0]: rom_addr[19:0] <= { 1'b0, code, vn[2:0] ^ {3{vflip}} };
                    size[1]: rom_addr[19:0] <= { code, vn[3:0] ^{4{vflip}} };
                    size[2]: rom_addr[19:0] <= { code[13:0], vn[4:0] ^{5{vflip}}, hflip };
                endcase
                rom_cs    <= 1'b1;
                hn <= hn + ( size[0] ? 10'h8 : (size[1] ? 10'h10 : 10'h20 ));
            end
            6: if(rom_ok) begin
                vram_addr <= { vram_base, 7'd0 } + { 10'd0, scan, 1'b0};
                pxl_data <= rom_data;   // 32 bits = 32/4 = 8 pixels
                rom_half <= ~rom_half;
            end else st<=6;
            7,8,9,10,    11,12,13,14, 
            16,17,18,19, 20,21,22,23,
            25,26,27,28, 29,30,31,32,
            34,35,36,37, 38,39,40,41: begin
                buf_wr   <= 1'b1;
                buf_addr <= buf_addr+9'd1;
                buf_data <= { pal, colour(pxl_data, hflip) };
                pxl_data <= hflip ? pxl_data>>1 : pxl_data<<1;
                if( buf_addr == 9'd447 ) begin
                    buf_wr <= 1'b0;
                    done <= 1'b1;
                    st <= 0;
                end
            end
            15: begin
                if( size[0] /*8*/) begin
                    st <= 2; // scan again
                    tilecnt <= tilecnt+1; // 8x tile done
                end else if(rom_ok) begin
                    pxl_data <= rom_data;
                    rom_half <= ~rom_half;
                    if(size[2] /*32*/)
                        rom_addr[0] <= ~rom_addr[0];
                end else st<=st;
            end
            24: begin
                if( size[1] /*16*/ ) begin
                    st <= 2; // scan again
                    tilecnt <= tilecnt+1; // 16x tile done
                end else if(rom_ok) begin
                    pxl_data <= rom_data;
                    rom_half <= ~rom_half;
                end else st<=st;
            end
            33: begin
                if(rom_ok) begin
                    pxl_data <= rom_data;
                    rom_half <= ~rom_half;
                end else st<=st;
            end
            42: begin
                st      <= 2; // 32x tile done
                tilecnt <= tilecnt+1;
            end
        endcase
    end
end

endmodule