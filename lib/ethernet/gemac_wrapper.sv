//-----------------------------------------------------------------------------
// File:   gemac_wrapper.sv
//
// Author:  Ian Buckley, Ion Concepts LLC.
//
// Description:
//   Wrap Ettus 1G ethernet MAC with DiRT interfaces
//   Translate 68bit AXIS Ethernet interface to MAC 8bit interfaces
//-----------------------------------------------------------------------------
`default_nettype none

module gemac_wrapper
  #(
    parameter RX_FLOW_CTRL=0,
    parameter PORTNUM=8'd0
    )
   (
    input wire  clk,
    input wire  clk125,
    input wire  rst,
    //-------------------------------------------------------------------------------
    // GMII Interface
    //-------------------------------------------------------------------------------
    output logic gmii_reset,
    gmii_t.mac mac_gmii, // Legal GMII, true source synchronous
    //-------------------------------------------------------------------------------
    // AXIS interfaces
    //-------------------------------------------------------------------------------
    axis_t.slave in_axis,
    axis_t.master out_axis
    );

   localparam           PAUSE_RESPECT_EN = 1'b0;
   localparam           PAUSE_REQUEST_EN = 1'b0;

   // Exploded in_axis bus
   logic [63:0]         rx_tdata;
   logic                rx_tvalid;
   logic                rx_tready;
   logic                rx_tlast;
   logic [3:0]          rx_tuser;

   // Exploded out_axis bus
   logic [63:0]         tx_tdata;
   logic                tx_tvalid;
   logic                tx_tready;
   logic                tx_tlast;
   logic [3:0]          tx_tuser;

   // 8bit RX interface to MAC	
   logic [7:0]          rx_data;
   logic                rx_valid;
   logic                rx_error;
   logic                rx_ack;

   // 8bit TX interface to MAC
   logic [7:0]          tx_data;
   logic                tx_valid;
   logic                tx_error;
   logic                tx_ack;

   logic                tx_reset;
   logic                rx_reset;
   logic                pause_req;
   logic                pause_request_en;
   logic [15:0]         pause_time, pause_thresh, pause_time_req, rx_fifo_space;

   synchronizer #(.FALSE_PATH_TO_IN(1),.INITIAL_VAL(1),.STAGES(2)) reset_sync_tx
     (.clk(mac_gmii.txclk),.rst(1'b0),.in(rst),.out(tx_reset));
   synchronizer #(.FALSE_PATH_TO_IN(1),.INITIAL_VAL(1),.STAGES(2)) reset_sync_rx
     (.clk(mac_gmii.rxclk),.rst(1'b0),.in(rst),.out(rx_reset));

   //-------------------------------------------------------------------------------
   // Ettus 1G MAC
   //-------------------------------------------------------------------------------

   simple_gemac simple_gemac_i0
     (
      .clk125(clk125),
      .reset(rst),
      // GMII interface
      .GMII_GTX_CLK(mac_gmii.txclk), // OUTPUT, legal GMII
      .GMII_TX_EN(mac_gmii.txen),
      .GMII_TX_ER(mac_gmii.txer),
      .GMII_TXD(mac_gmii.txd),
      .GMII_RX_CLK(mac_gmii.rxclk),
      .GMII_RX_DV(mac_gmii.rxdv),
      .GMII_RX_ER(mac_gmii.rxer),
      .GMII_RXD(mac_gmii.rxd),
      // Pause frame interface
      .pause_req(RX_FLOW_CTRL ? pause_req : 1'b0),
      .pause_time_req(RX_FLOW_CTRL ? pause_time_req : 16'd0),
      .pause_respect_en(PAUSE_RESPECT_EN),
      // unicast/broadcast/multicast address filtering
      // (Set to be promisicious)
      .ucast_addr(48'h0),
      .mcast_addr(48'h0),
      .pass_ucast(1'b0),
      .pass_mcast(1'b0),
      .pass_bcast(1'b0),
      .pass_pause(1'b0),
      .pass_all(1'b1),
      // 8bit RX MAC interface
      .rx_clk(), // Passes out mac_gmii.rxclk
      .rx_data(rx_data),
      .rx_valid(rx_valid),
      .rx_error(rx_error),
      .rx_ack(rx_ack),
      // 8bit TX MAC interface
      .tx_clk(mac_gmii.txclk),
      .tx_data(tx_data),
      .tx_valid(tx_valid),
      .tx_error(tx_error),
      .tx_ack(tx_ack),
      .debug()
      );

   //-------------------------------------------------------------------------------
   // RX: 8bit FIFO -> 68bit Ethernet AXIS
   //-------------------------------------------------------------------------------
   wire                 rx_ll_eof;
   wire                 rx_ll_error;
   wire                 rx_ll_src_rdy;
   wire                 rx_ll_dst_rdy;
   wire [7:0]           rx_ll_data;

   wire [63:0]          rx_tdata_int;
   wire [3:0]           rx_tuser_int;
   wire                 rx_tlast_int;
   wire                 rx_tvalid_int;
   wire                 rx_tready_int;

   rxmac_to_ll8 rxmac_to_ll8_i0
     (
      .clk(mac_gmii.rxclk),
      .reset(rx_reset),
      .clear(1'b0),
      // RX MAC interface
      .rx_data(rx_data),
      .rx_valid(rx_valid),
      .rx_error(rx_error),
      .rx_ack(rx_ack),
      // 8bit FIFO interface
      .ll_data(rx_ll_data),
      .ll_sof(),  // ignore sof
      .ll_eof(rx_ll_eof),
      .ll_error(rx_ll_error),
      .ll_src_rdy(rx_ll_src_rdy),
      .ll_dst_rdy(rx_ll_dst_rdy));

   ll8_to_axi64 #(.START_BYTE(6), .LABEL(PORTNUM)) ll8_to_axi64_i0
     (
      .clk(mac_gmii.rxclk),
      .reset(rx_reset),
      .clear(1'b0),
      // 8bit FIFO interface
      .ll_data(rx_ll_data),
      .ll_eof(rx_ll_eof),
      .ll_error(rx_ll_error),
      .ll_src_rdy(rx_ll_src_rdy),
      .ll_dst_rdy(rx_ll_dst_rdy),
      // 64bit+4bit AXIS
      .axi64_tdata(rx_tdata_int),
      .axi64_tlast(rx_tlast_int),
      .axi64_tuser(rx_tuser_int),
      .axi64_tvalid(rx_tvalid_int),
      .axi64_tready(rx_tready_int));

   axis_fifo_512x69_2clk axis_fifo_512x69_2clk_i0
     (
      .s_aresetn(~rx_reset), // Active low, Async
      // Input
      .s_aclk(mac_gmii.rxclk),
      .s_axis_tvalid(rx_tvalid_int),
      .s_axis_tready(rx_tready_int),
      .s_axis_tdata(rx_tdata_int),
      .s_axis_tuser(rx_tuser_int),
      .s_axis_tlast(rx_tlast_int),
      // Output
      .m_aclk(clk),
      .m_axis_tvalid(rx_tvalid),
      .m_axis_tready(rx_tready),
      .m_axis_tdata(rx_tdata),
      .m_axis_tuser(rx_tuser),
      .m_axis_tlast(rx_tlast)
      );

    always_comb begin
        out_axis.tdata  = {rx_tuser,rx_tdata};
        out_axis.tvalid = rx_tvalid;
        out_axis.tlast  = rx_tlast;
        rx_tready       = out_axis.tready;
    end

   //-------------------------------------------------------------------------------
   // TX: 68bit Ethernet AXIS -> 8bit FIFO
   //-------------------------------------------------------------------------------

   wire 	  tx_ll_eof;
   wire           tx_ll_src_rdy;
   wire           tx_ll_dst_rdy;
   wire [7:0]     tx_ll_data;

   wire [63:0]    tx_tdata_int;
   wire [3:0]     tx_tuser_int;
   wire           tx_tlast_int;
   wire           tx_tvalid_int;
   wire           tx_tready_int;

   always_comb begin
      {tx_tuser,tx_tdata} = in_axis.tdata;
      tx_tvalid           = in_axis.tvalid;
      tx_tlast            = in_axis.tlast;
      in_axis.tready      = tx_tready;
   end

   axis_fifo_512x69_2clk axis_fifo_512x69_2clk_i1
     (
      .s_aresetn(~tx_reset), // Active low, Async
      // Input
      .s_aclk(clk),
      .s_axis_tvalid(tx_tvalid),
      .s_axis_tready(tx_tready),
      .s_axis_tdata(tx_tdata),
      .s_axis_tuser(tx_tuser),
      .s_axis_tlast(tx_tlast),
      // Output
      .m_aclk(mac_gmii.rxclk),
      .m_axis_tvalid(tx_tvalid_int),
      .m_axis_tready(tx_tready_int),
      .m_axis_tdata(tx_tdata_int),
      .m_axis_tuser(tx_tuser_int),
      .m_axis_tlast(tx_tlast_int)
      );

   axi64_to_ll8 #(.START_BYTE(6)) axi64_to_ll8_i1
     (
      .clk(mac_gmii.txclk),
      .reset(tx_reset),
      .clear(1'b0),
      .axi64_tdata(tx_tdata_int),
      .axi64_tlast(tx_tlast_int),
      .axi64_tuser(tx_tuser_int),
      .axi64_tvalid(tx_tvalid_int),
      .axi64_tready(tx_tready_int),
      .ll_data(tx_ll_data),
      .ll_eof(tx_ll_eof),
      .ll_src_rdy(tx_ll_src_rdy),
      .ll_dst_rdy(tx_ll_dst_rdy)
      );

   ll8_to_txmac ll8_to_txmac_i1
     (
      .clk(mac_gmii.txclk),
      .reset(tx_reset),
      .clear(1'b0),
      .ll_data(tx_ll_data),
      .ll_eof(tx_ll_eof),
      .ll_src_rdy(tx_ll_src_rdy),
      .ll_dst_rdy(tx_ll_dst_rdy),
      .tx_data(tx_data),
      .tx_valid(tx_valid),
      .tx_error(tx_error),
      .tx_ack(tx_ack)
      );

   //-------------------------------------------------------------------------------
   // Pause Frame Processing
   //-------------------------------------------------------------------------------
   generate
      if (RX_FLOW_CTRL==1)
	flow_ctrl_rx flow_ctrl_rx_i0
	  (
           .pause_request_en(pause_request_en),
           .pause_time(pause_time),
           .pause_thresh(pause_thresh),
	   .rx_clk(mac_gmii.rxclk),
           .rx_reset(rx_reset),
           .rx_fifo_space(rx_fifo_space),
	   .txclk(mac_gmii.txclk),
           .tx_reset(tx_reset),
           .pause_req(pause_req),
           .pause_time_req(pause_time_req)
           );
   endgenerate

endmodule // gemac_wrapper
`default_nettype wire
