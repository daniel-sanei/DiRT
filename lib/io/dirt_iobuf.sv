//-----------------------------------------------------------------------------
// File:   dirt_iobuf.sv
//
// Author:  Ian Buckley, Ion Concepts LLC.
//
// Parameterizable:
// * Width of datapath.
//
// Description:
// Instantiates bus of Xilinx IOBUF
//
//
// License: CERN-OHL-P (See LICENSE.md)
//
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ps

module dirt_iobuf
  #(
    parameter WIDTH = 1
    )
   (
    input wire [WIDTH-1:0]  I,
    input wire [WIDTH-1:0]  T, // Tristates output buffer when asserted HIGH.
    inout wire [WIDTH-1:0]  IO,
    output wire [WIDTH-1:0] O 
    );

   genvar		     i;
   generate
      for (i=0; i < WIDTH; i++) begin
	 IOBUF dirt_iobuf_i
	     (
	      .I(I[i]),
	      .IO(IO[i]),
	      .O(O[i]),
	      .T(T[i])
	      );
      end
   endgenerate


endmodule // dirt_iobuf
