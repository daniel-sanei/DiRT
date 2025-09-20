//-----------------------------------------------------------------------------
// File:    axis_rtspi_unit_test.sv
//
// Description:
//  Per ADRV9001 we model a SPI device that:
//     "CSB is the active-low chip select that functions as the bus enable signal driven from the baseband processor to the device (uses the SPI_EN
//     pin). CSB is driven low before the first SCLK rising edge and is normally driven high again after the last SCLK falling edge. The device ignores
//     the clock and data signals while CSB is high. CSB also frames communication to and from the device and returns the SPI to the ready state
//     when it is driven high"
//
//     "The data signals are launched on the falling edge of SCLK and sampled on the rising edge of SCLK by both the baseband processor and
//     the device. SDIO carries the control field from the baseband processor to the device during all transactions, and it carries the write data fields
//     during a write transaction. In a 4-wire SPI configuration, SDO carries the returning data fields to the baseband processor."
//
//-----------------------------------------------------------------------------

`include "svunit_defines.svh"
`include "spi.sv"
`include "axis_rtspi.sv"
`include "drat_protocol.sv"


module axis_rtspi_unit_test;

   timeunit 1ns;
   timeprecision 1ps;

   import drat_protocol::*;
   import svunit_pkg::svunit_testcase;

   string name = "axis_pkt_to_stream_ut";
   svunit_testcase svunit_ut;

   localparam SPI_READ = 1;
   localparam SPI_WRITE = 0;

   logic  clk;
   logic  rst;
   // Watchdog
   int	  timeout;

   // Time
   logic [63:0]	current_time;

   // DUT Signals (non AXIS)
   logic	csr_enable;
   logic [7:0]	csr_sclk_div;
   logic [31:0]	csr_flow_id_response;
   spi_t #(.CLK_HALF_PERIOD(50),.ADDRESS(15),.DATA(8)) spi();



   // Declarations for Stimulus Thread(s)
   DRaTPacket test_packet;
   logic	enable_stimulus;
   logic	enable_response;
   logic	ready_to_test;



   // Declarations for Response Thread(s)
   DRaTPacket response_packet;

   // Pre-Buffer Input Bus
   pkt_stream_t axis_stimulus_pre(.clk(clk));
   // Bus between stimulus buffer and demux4
   pkt_stream_t axis_stimulus_post(.clk(clk));
   // DUT Input bus
   pkt_stream_t axis_stimulus_gated(.clk(clk));
   // DUT Status Bus
   // DUT Output bus
   pkt_stream_t axis_response_gated(.clk(clk));
   // Bus between response vavale and buffer with Time concatenated.
   pkt_stream_t axis_response_pre(.clk(clk));
   // Post Buffer Output bus with Time concatenated.
   pkt_stream_t axis_response_post(.clk(clk));


   //
   // Generate clk. (Nominally 100MHz, but that is arbitrary.)
   //
   initial begin
      clk <= 1'b1;
   end

   always begin
      #5 clk <= ~clk;
   end


   //
   // Provide time that increments on sample clock domain.
   //

   always_ff @(posedge clk) begin
      if (rst)
	current_time <= 0;
      else
	current_time <= current_time + 1 ;
   end

   //----------------------------------
   // This is the UUT that we're
   // running the Unit Tests on
   //----------------------------------

   axis_rtspi axis_rtspi_i0
     (
      .clk(clk),
      .rst(rst),
      // enable pins
      .csr_enable(csr_enable),
      .csr_sclk_div(csr_sclk_div),
      .csr_flow_id_response(csr_flow_id_response),
      // System time in
      .system_time(current_time),
      // External SPI signals
      .spi(spi),
      // Dirt/DRat packetized stream in
      .in_axis(axis_stimulus_gated.axis),
      // Dirt/DRat packetized stream out
      .out_axis(axis_response_gated.axis)
      );

   //-------------------------------------------------------------------------------
   // Buffer input stimulus packet stream.
   // Pass first to a FIFO to buffer test stimulus.
   // Then finally a valve so that the buffer can be loaded, then bursted,
   // at full rate, or be modulated to reduce the rate.
   //-------------------------------------------------------------------------------

   axis_fifo_wrapper  #(
                        .SIZE(10)
                        )
   axis_fifo_stimulus_i (
                         .clk(clk),
                         .rst(rst),
                         .in_axis(axis_stimulus_pre.axis),
                         .out_axis(axis_stimulus_post.axis)
                         );

  
   axis_valve axis_valve_stimulus_i (
                                     .clk(clk),
                                     .rst(rst),
                                     .in_axis(axis_stimulus_post.axis),
                                     .out_axis(axis_stimulus_gated.axis),
                                     .enable(enable_stimulus)
                                     );


   //-------------------------------------------------------------------------------
   // Buffer output response sample stream with dispatch time metadata
   //-------------------------------------------------------------------------------

   axis_valve axis_valve_response_i (
                                     .clk(clk),
                                     .rst(rst),
                                     .in_axis(axis_response_gated.axis),
                                     .out_axis(axis_response_pre.axis),
                                     .enable(enable_response)
                                     );

    axis_fifo_wrapper  #(
                         .SIZE(11)
                         )
    axis_fifo_response_i (
                          .clk(clk),
                          .rst(rst),
                          .in_axis(axis_response_pre.axis),
                          .out_axis(axis_response_post.axis)
                          );







   //===================================
   // Build
   //===================================
   function void build();
      svunit_ut = new(name);
   endfunction


   //===================================
   // Setup for running the Unit Tests
   //===================================
   task setup();
      svunit_ut.setup();
      /* Place Setup Code Here */
      // Reset UUT
      @(posedge clk);
      rst <= 1'b1;
      ready_to_test <= 0;
      csr_enable <= 0;
      csr_sclk_div <= 6;
      csr_flow_id_response <= {DST0,SRC0};
      // Open all valves by default
      enable_stimulus <= 1'b1;
      enable_response <= 1'b1;
      // Take all bench AXIS buses to a quiescent state
      idle_all();
      // De-assert reset after 10 clock cycles.
      @(posedge clk);
      repeat(10) @(posedge clk);
      rst <= 1'b0;

   endtask

   //===================================
   // Here we deconstruct anything we
   // need after running the Unit Tests
   //===================================
   task teardown();
      svunit_ut.teardown();
      /* Place Teardown Code Here */
   endtask // teardown



   //===================================
   // All tests are defined between the
   // SVUNIT_TESTS_BEGIN/END macros
   //
   // Each individual test must be
   // defined between `SVTEST(_NAME_)
   // `SVTEST_END
   //
   // i.e.
   //   `SVTEST(mytest)
   //     <test code>
   //   `SVTEST_END
   //===================================
   `SVUNIT_TESTS_BEGIN

   `SVTEST(test_good_async_command)
   `INFO("Issue a set of well formed SPI_COMMAND_ASYNC packets");
   fork
      begin: load_stimulus
         // Response threads can't run until stimulus loaded.
         ready_to_test <= 0;
         // Close valve after stimulus buffer
         enable_stimulus <= 1'b0;
	 enable_response <= 1'b0;
	 // Setup Packet construction workspace
	 // Single packet payload beat, timestamp set to 0
         initialize_packet_workspace(beats_to_bytes(1),'d0);
	 @(posedge clk);
	 // Simulate CSR interaction that turns on SPI master (With good default CSR state)
	 csr_enable <= 1; 
	 
	 //
	 // Loop over 4 packets
         for (int x = 0 ; x < 4 ; x = x + 1) begin
            populate_spi_command_packet(
					SPI_COMMAND_ASYNC,
					SPI_READ,
					x[14:0],
					8'h0
					);
	    // Push out pkt to Stimulus FIFO
	    axis_stimulus_pre.push_pkt(test_packet);
	    // Increment burst SeqID for next packet
	    test_packet.inc_seq_id();
	 end

	 //
         // Stimulus fully loaded, initialise system for test and release stimulus
         // by opening valve.
         //
         @(negedge clk);
         @(negedge clk);
         // 100% duty cycle on AXIS input bus.
         enable_stimulus <= 1'b1;
	 enable_response <= 1'b1;
         // Let response threads run
         ready_to_test <= 1;
         //
         `INFO("test_good_async_command: Stimulus done");
      end // block: load_stimulus
      //
      begin : slave_BFM
	 automatic logic read_not_write;
	 automatic logic [14:0] address;
	 automatic logic [7:0] data_out;

	 while (!ready_to_test) @(posedge clk);

	 for (int x = 0 ; x < 4 ; x = x + 1) begin
	    spi.transaction(read_not_write,
			     address,
			     x,
			     data_out // Not expecting any data_out
			     );

	 end

	 `INFO("test_good_async_command: Good BFM");
      end // block: slave_BFM

      //
      begin : read_response

	 while (!ready_to_test) @(posedge clk);

	 response_packet = new;
	 for (int x = 0 ; x < 4 ; x = x + 1) begin
            response_packet.copy_to_pkt(axis_response_post);
	    response_packet.assert_spi_response_packet(
						       x, //bit [7:0]  seq_id,
						       16'd24, // bit [15:0] length,
						       {SRC0,DST0}, // flow_id_t flow_id,
						       0, //bit [63:0] timestamp=0,
						       0, //bit [63:0] timestamp_min=0,
						       0, //bit [63:0] timestamp_max=0,
						       SPI_ACK, //spi_status_t spi_status,
						       x, //bit [7:0]  expected_seq_id,
						       x //bit [7:0]  received_seq_id
						       );
	 end // for (x = 0 ; x < 4 ; x = x + 1)
	 `INFO("test_good_async_command:  Good Response");
	 disable watchdog_thread;
      end // block: read_response
      //
      begin : watchdog_thread
         timeout = 100000;
         while(1) begin
            `FAIL_IF(timeout==0);
            timeout = timeout - 1;
            @(posedge clk);
         end
      end
   join
   @(negedge clk);
   `SVTEST_END


    `SVUNIT_TESTS_END




//-------------------------------------------------------------------------------
// Helper tasks to improve code reuse for this specific test bench.
//-------------------------------------------------------------------------------

// Task: idle_all()
// Cause all AXIS buses to go idle.
task idle_all();
   axis_stimulus_pre.axis.idle_master();
   axis_response_post.axis.idle_slave();
endtask // idle_all

//TODO:
// Fills packet in workspace with random payload and pushes the headers to the FIFO
// (Odd collection of functionality but maximizes code reuse)
task populate_spi_command_packet;
   input pkt_type_t pkt_type;
   input logic read_not_write;
   input logic [14:0] address;
   input logic [7:0] data;

   // On last packet of burst change type to INT16_COMPLEX_EOB
   test_packet.set_packet_type(pkt_type);
   // Populate payload beat
   test_packet.set_spi_command(read_not_write,address,data);
   // ...then rewind pointer to head of payload again
   test_packet.rewind_payload;

endtask // populate_header

// Create new packet workspace object and initialize headers
// (Odd collection of functionality but maximizes code reuse)
task initialize_packet_workspace;
   input logic [15:0] payload_bytes;
   input logic [63:0] start_time;

   // Create Object
   test_packet = new;
   // Initialize header fields with default values
   test_packet.init; // Sets most fields to zero.
   // Overide FlowID
   test_packet.set_flow_src(SRC0);
   test_packet.set_flow_dst(DST0);
   // Set packet length to be header plus 1 beat
   test_packet.set_length(16+payload_bytes);
   // Set timestamp of first packet to be 1000...
   test_packet.set_timestamp(start_time);
   // Allocate storage for packet payload beat
   test_packet.allocate_payload();

endtask

endmodule // axis_rtspi_unit_test
