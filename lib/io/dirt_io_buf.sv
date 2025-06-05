//-----------------------------------------------------------------------------
// File:   dirt_io_buf.sv
//
// Author:  Ian Buckley, Ion Concepts LLC.
//
// Parameterizable:
// * Width of datapath.
//
// Description:
// Instantiates bus of Xilinx IO_BUF
//
//
// License: CERN-OHL-P (See LICENSE.md)
//
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ps

module dirt_io_buf
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
	 IOBUF dirt_io_buf_i
	     (
	      .I(I[i]),
	      .IO(IO[i]),
	      .O(O[i]),
	      .T(T[i])
	      );
	 end
      end
   endgenerate


endmodule // dirt_io_buf
