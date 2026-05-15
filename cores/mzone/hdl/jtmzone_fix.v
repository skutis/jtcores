/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTCORES program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>. */

module jtmzone_fix(
    // video inputs
    input        [8:0] hdump,
    input        [8:0] vdump,
    input              flip,

    // VRAM
    input        [7:0] vram1,
    input        [7:0] cram1,

    // shared memory requests
    output       [9:0] ram_addr,
    output       [11:0] rom_addr,

    output       [3:0] color,
    output             hflip
);

wire [2:0] tile_py;
wire [5:0] tile_x, addr_x_full;
wire [4:0] addr_x, addr_y;

assign tile_x = hdump[8:3];
assign addr_x_full = flip ? 6'd35-tile_x : tile_x;
assign addr_x = addr_x_full[4:0];
assign addr_y = flip ? ~vdump[7:3] : vdump[7:3];

assign ram_addr = { addr_y, addr_x };
assign tile_py  = flip ? ~vdump[2:0] : vdump[2:0];
assign rom_addr = { cram1[7], vram1, tile_py ^ {3{cram1[5]}} };
assign color    = cram1[3:0];
assign hflip    = cram1[6];

endmodule
