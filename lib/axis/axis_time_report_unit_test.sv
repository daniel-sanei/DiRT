//-------------------------------------------------------------------------------
// File:    axis_time_report_unit_test.sv
//
// Author:  Ian Buckley, Ion Concepts LLC
//
// Description:
// Verify thtat:
// * Discards ingressing packets due to lack of capacity
//
//
// License: CERN-OHL-P (See LICENSE.md)
//
//-------------------------------------------------------------------------------

`include "global_defs.svh"
`include "svunit_defines.svh"
`include "axis_time_report.sv"
`include "drat_protocol.sv"

module axis_time_report_unit_test;
   timeunit 1ns;
   timeprecision 1ps;
   import drat_protocol::*;
   import svunit_pkg::svunit_testcase;

   string name = "axis_time_report_ut";
   svunit_testcase svunit_ut;


   logic clk;
   logic rst;

   //
   // CSRs
   //
   logic csr_enable;
   logic [15:0] csr_period;
   logic [31:0] csr_flow_id;

   // System time
   logic [63:0] current_time;


   // Bus between UUT egress0 and
   pkt_stream_t out_axis(.clk(clk));

   // Declarations for Stimulus Thread(s)
   logic        enable_stimulus;
   logic        enable_response;
   logic        ready_to_test;

   // Declarations for Response Thread(s)
   DRaTPacket response_packet;

   // Watchdog
   int          timeout;

   //
   // Generate clk
   //
   initial begin
      clk <= 1'b0;
   end

   always
     #5 clk <= ~clk;

   //
   // Provide time that increments on sample clock domain.
   //

   always_ff @(posedge clk) begin
      if (rst)
        current_time <= 0;
      else
        current_time <= current_time + 1 ;
   end

  //===================================
  // This is the UUT that we're
  // running the Unit Tests on
  //===================================


   axis_time_report uut
     (
      .clk(clk),
      .rst(rst),
      //
      // CSR interface
      //
      .csr_enable(csr_enable),
      .csr_period(csr_period),
      .csr_flow_id(csr_flow_id),
      // Current System Time
      .current_time(current_time),
      // Dirt/DRat packetized stream out
      .axis_time_out(out_axis.axis)

      );

   //-------------------------------------------------------------------------------
   // Dump outout
   //-------------------------------------------------------------------------------
   axis_null_sink null_sink_router2eth_i0
     (
      .in_axis(out_axis.axis)
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
      csr_period <= 0;
      csr_flow_id <= 0;
      // Take all bench AXIS buses to a quiescent state
      idle_all();
      // De-assert reset after 10 clock cycles.
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
   endtask


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


  //===================================
  // Test:
  //
  // gross_error_check
  // - Easy simulation just looks at two emited time_reports.
  //
  //===================================
  `SVTEST(gross_error_check)
  `INFO("Simple test for gross errors");

   fork
      begin : load_stimulus
         @(posedge clk);
         csr_enable <= 0;
         csr_period <= 10;
         csr_flow_id <= {DST0,SRC0};
         @(posedge clk);
         csr_enable <= 1;
         ready_to_test <= 1;
         //
         `INFO("gross_error_check: Stimulus Done");
         //
      end // block: load_stimulus


      // Response thread for output
      begin: read_response_out
         // This simulation should produce TBD
         //
         while (!ready_to_test) @(posedge clk);

         response_packet = new;
         response_packet.copy_to_pkt(out_axis);
         response_packet.assert_time_report_packet(
                                                   0,           // SEQ NUM
                                                   {DST0,SRC0}, // FLOWID
                                                   'd2563,      // TIMESTAMP
                                                   'd2000,      // TIMESTAMP MIN
                                                   'd3000,      // TIMESTAMP MAX
                                                   1            // VERBOSE
                                                   );

         response_packet.copy_to_pkt(out_axis);

         response_packet.assert_time_report_packet(
                                                   1,           // SEQ NUM
                                                   {DST0,SRC0}, // FLOWID
                                                   'd5123,      // TIMESTAMP
                                                   'd5000,      // TIMESTAMP MIN
                                                   'd6000,      // TIMESTAMP MAX
                                                   1            // VERBOSE
                                                   );

         `INFO("gross_error_check: Good Response");

         repeat(100) @(posedge clk);
         disable watchdog_thread;
      end // block: read_response_out

      begin : watchdog_thread
         timeout = 10000;
         while(1) begin
            `FAIL_IF(timeout==0);
            timeout = timeout - 1;
            @(negedge clk);
         end
      end
   join

   `SVTEST_END

  //===================================
  // Test:
  //
  // change_period_on_the_fly
  // - Chnage period to be shorter after two time_report packets
  // - verify it changes without long pause
  //===================================
  `SVTEST(change_period_on_the_fly)
   `INFO("Test that shortening period is immediately adopted.");

   fork
      begin : load_stimulus
         @(posedge clk);
         csr_enable <= 0;
         csr_period <= 10;
         csr_flow_id <= {DST1,SRC1};
         @(posedge clk);
         csr_enable <= 1;
         ready_to_test <= 1;
	 repeat(7000) @(posedge clk);
	 csr_period <= 5;
         //
         `INFO("change_period_on_the_fly: Stimulus Done");
         //
      end // block: load_stimulus


      // Response thread for output
      begin: read_response_out
         // This simulation should produce TBD
         //
         while (!ready_to_test) @(posedge clk);

         response_packet = new;
         response_packet.copy_to_pkt(out_axis);
         response_packet.assert_time_report_packet(
                                                   0,           // SEQ NUM
                                                   {DST1,SRC1}, // FLOWID
                                                   'd2563,      // TIMESTAMP
                                                   'd2000,      // TIMESTAMP MIN
                                                   'd3000,      // TIMESTAMP MAX
                                                   1            // VERBOSE
                                                   );

         response_packet.copy_to_pkt(out_axis);

         response_packet.assert_time_report_packet(
                                                   1,           // SEQ NUM
                                                   {DST1,SRC1}, // FLOWID
                                                   'd5123,      // TIMESTAMP
                                                   'd5000,      // TIMESTAMP MIN
                                                   'd6000,      // TIMESTAMP MAX
                                                   1            // VERBOSE
                                                   );
         // Should now trigger the instant that the period is changed
         // as count has exceeded the new period
         response_packet.copy_to_pkt(out_axis);

         response_packet.assert_time_report_packet(
                                                   2,           // SEQ NUM
                                                   {DST1,SRC1}, // FLOWID
                                                   'd7171,         // TIMESTAMP
                                                   'd7000,      // TIMESTAMP MIN
                                                   'd8000,      // TIMESTAMP MAX
                                                   1            // VERBOSE
                                                   );

         response_packet.copy_to_pkt(out_axis);

         response_packet.assert_time_report_packet(
                                                   3,           // SEQ NUM
                                                   {DST1,SRC1}, // FLOWID
                                                   'd8451,         // TIMESTAMP
                                                   'd8000,      // TIMESTAMP MIN
                                                   'd9000,      // TIMESTAMP MAX
                                                   1            // VERBOSE
                                                   );

         `INFO("change_period_on_the_fly: Good Response");

         repeat(100) @(posedge clk);
         disable watchdog_thread;
      end // block: read_response_out

      begin : watchdog_thread
         timeout = 10000;
         while(1) begin
            `FAIL_IF(timeout==0);
            timeout = timeout - 1;
            @(negedge clk);
         end
      end
   join

   `SVTEST_END


     `SVUNIT_TESTS_END

       task idle_all();
          out_axis.axis.idle_slave();
       endtask // idle_all

endmodule
