//-----------------------------------------------------------------------------
// File:   dirt_ibufds.sv
//
// Author:  Ian Buckley, Ion Concepts LLC.
//
// Parameterizable:
// * Width of datapath.
//
// Description:
// Instantiates bus of Xilinx IBUFDS
//
//
// License: CERN-OHL-P (See LICENSE.md)
//
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ps

module dirt_ibufds
  #(
    parameter WIDTH = 1,
    parameter DIFF_TERM = "TRUE",
    parameter IBUF_LOW_PWR = "TRUE"
    )
   (
    input wire [WIDTH-1:0]  I,
    input wire [WIDTH-1:0]  IB,
    output wire [WIDTH-1:0] O
    );

   genvar		     i;
   generate
      for (i=0; i < WIDTH; i++) begin
	 IBUFDS # (
             .DIFF_TERM (DIFF_TERM),
             .IBUF_LOW_PWR (IBUF_LOW_PWR)
             )
	     dirt_ibufds_i
	     (
	      .I(I[i]),
	      .IB(IB[i]),
	      .O(O[i])
	      );
      end
   endgenerate


endmodule // dirt_ibufds
