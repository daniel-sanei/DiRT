//-----------------------------------------------------------------------------
// File:   dirt_obufds.sv
//
// Author:  Ian Buckley, Ion Concepts LLC.
//
// Parameterizable:
// * Width of datapath.
//
// Description:
// Instantiates bus of Xilinx OBUFDS
//
//
// License: CERN-OHL-P (See LICENSE.md)
//
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ps

module dirt_obufds
  #(
    parameter WIDTH = 1
    )
   (
    input wire [WIDTH-1:0]  I,
    output wire [WIDTH-1:0] O,
    output wire [WIDTH-1:0] OB
    );

   genvar		     i;
   generate
      for (i=0; i < WIDTH; i++) begin
	 OBUFDS dirt_obufds_i
	     (
	      .I(I[i]),
	      .O(O[i]),
	      .OB(OB[i])
	      );
      end
   endgenerate


endmodule // dirt_obufds
