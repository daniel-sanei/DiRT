//-------------------------------------------------------------------------------
// File:    axi_packet_gate_wrapper.sv
//
// Description: Wrap Ettus axi_packet_gate with system verilog interfaces.
//
//-------------------------------------------------------------------------------
`default_nettype none

module axi_packet_gate_wrapper
  #(
    parameter SIZE = 10, // log2 of the buffer size (must be >= MTU of packet)
    parameter USE_AS_BUFF = 0     // Allow the packet gate to be used as a buffer (uses more RAM)
    ) (
       input wire                 clk,
       input wire                 reset,

       input wire                 error,
       // Input Bus
       axis_t.slave in_axis,
       // Output bus
       axis_t.master out_axis);



       logic [in_axis.WIDTH-1:0]  i_tdata;
       logic                      i_tvalid;
       logic                      i_tlast;
       logic                      i_tready;

       logic [out_axis.WIDTH-1:0] o_tdata;
       logic                      o_tvalid;
       logic                      o_tlast;
       logic                      o_tready;

   always_comb begin
      i_tdata = in_axis.tdata;
      i_tvalid = in_axis.tvalid;
      i_tlast = in_axis.tlast;
      in_axis.tready = i_tready;
      out_axis.tdata = o_tdata;
      out_axis.tvalid = o_tvalid;
      out_axis.tlast = o_tlast;
      o_tready = out_axis.tready;
   end

   axi_packet_gate
     #(
       .WIDTH(in_axis.WIDTH),
       .SIZE(11),
       .USE_AS_BUFF(1)
       ) packet_gate_i0
       (
        .clk(clk),
        .reset(reset),
        .clear(1'b0),

        .i_tdata(i_tdata),
        .i_tlast(i_tlast),
        .i_terror(error), // MSB of TDATA bus is error
        .i_tvalid(i_tvalid),
        .i_tready(i_tready),

        .o_tdata(o_tdata),
        .o_tlast(o_tlast),
        .o_tvalid(o_tvalid),
        .o_tready(o_tready)
        ) ;


endmodule // axi_packet_gate_wrapper

`default_nettype wire
