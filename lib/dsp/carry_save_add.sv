//-----------------------------------------------------------------------------
// File:   carry_save_add.sv
//
// Author:  Ian Buckley, Ion Concepts LLC.
//
// Parameterizable:
// * Width of datapath.
//
// Description:
// Carry Save Adder (3->2 compressor).
// 
//
// License: CERN-OHL-P (See LICENSE.md)
//
//-----------------------------------------------------------------------------
`default_nettype none
`timescale 1ns/1ps

module carry_save_add
  #(
    parameter WIDTH = 16  
    )
   (
    input wire [WIDTH-1:0]  in0,
    input wire [WIDTH-1:0]  in1,
    input wire [WIDTH-1:0]  in2,    
    //
    output logic [WIDTH-1:0] sum_out, // bit weight [WIDTH-1:0]
    output logic [WIDTH-1:0] carry_out // bit weight [WIDTH:1]
    );

   genvar		     i;
   generate
      for (i=0; i < WIDTH; i++) begin
	 always_comb begin
	    {carry_out[i],sum_out[i]} = in0[i] + in1[i] + in2[i];
	 end
      end
   endgenerate
   
   
endmodule // carry_save_add
