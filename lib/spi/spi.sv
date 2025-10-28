//-----------------------------------------------------------------------------
// File:    spi.sv
//
// Author:  Ian Buckley, Ion Concepts LLC.
//
// Description:
// Interface definition of 4-wire SPI interface
//
// License: CERN-OHL-P (See LICENSE.md)
//
//-----------------------------------------------------------------------------

`timescale 1ns/1ps

`ifndef _SPI_SV_
 `define _SPI_SV_




//
// Declare SPI as a System Verilog interface
// (For help see Section 19 of the System Verilog Reference Manual.
//

/*
 Some assumptions that won't be true for all SPI devices:
 - Write signals on falling edges, read them on rising edges
 -
 */

interface spi_t
  #(
    parameter CLK_HALF_PERIOD = 50,
    parameter ADDRESS = 15,
    parameter DATA = 8
    );

   // Control flags
   bit                has_checks = 1;

   // Actual Signals
   logic	      sclk; // SPI Clock
   logic	      ss_b; // Slave Select (Active low)
   logic	      mosi; // Master Out, Slave In
   logic	      miso; // Master In, Slave Out


   // SPI is Master(One) to Save (Many)
   // declare modport for master and slave interfaces.

   modport master (output sclk, output ss_b, output mosi, input miso);
   modport slave (input sclk, input ss_b, input mosi, output miso);
   modport monitor (input sclk, input ss_b, input mosi, input miso);

   //
   // Tasks for simulation use.
   //

   //
   // SPI Master Write
   //
   task automatic write;
      input logic [ADDRESS-1:0] address;
      input logic [DATA-1:0]	data;

      begin
	 automatic integer counter;
	 sclk = 1;
	 ss_b = 1;
	 mosi = 0; // Somewhat arbitrary
	 // R/W# Cycle
	 #CLK_HALF_PERIOD sclk = 0;
	 ss_b = 0;
	 mosi = 0;
	 counter = ADDRESS;
	 #CLK_HALF_PERIOD sclk = 1;
	 // Address Cycles
	 repeat(ADDRESS) begin
	    #CLK_HALF_PERIOD sclk = 0;
	    counter = counter - 1;
	    mosi = address[counter];
	    #CLK_HALF_PERIOD sclk = 1;
	 end
	 counter = DATA;
	 // Data Cycles
	 repeat(ADDRESS) begin
	    #CLK_HALF_PERIOD sclk = 0;
	    counter = counter - 1;
	    mosi = data[counter];
	    #CLK_HALF_PERIOD sclk = 1;
	 end
	 // Half cycle to end transaction.
	 #CLK_HALF_PERIOD sclk = 0;
	 mosi = 0; // Somewhat arbitrary
	 ss_b = 1;
	 #CLK_HALF_PERIOD sclk = 1; // Prep for next cycle.
      end
   endtask // write

   //
   // SPI Master Read
   //
   task automatic read;
      input logic [ADDRESS-1:0] address;
      output logic [DATA-1:0]	data;

      begin
	 automatic integer counter;
	 sclk = 1;
	 ss_b = 1;
	 mosi = 0; // Somewhat arbitrary
	 // R/W# Cycle
	 #CLK_HALF_PERIOD sclk = 0;
	 ss_b = 0;
	 mosi = 0; // Write
	 counter = ADDRESS;
	 #CLK_HALF_PERIOD sclk = 1;
	 // Address Cycles
	 repeat(ADDRESS) begin
	    #CLK_HALF_PERIOD sclk = 0;
	    counter = counter - 1;
	    mosi = address[counter];
	    #CLK_HALF_PERIOD sclk = 1;
	 end
	 counter = DATA;
	 // Switch active clockedge now.
	 #CLK_HALF_PERIOD sclk = 0;
	 // Data Cycles
	 repeat(ADDRESS) begin
	    #CLK_HALF_PERIOD sclk = 1;
	    counter = counter - 1;
	    data[counter] = miso;
	    #CLK_HALF_PERIOD sclk = 0;
	 end
	 mosi = 0; // Somewhat arbitrary
	 ss_b = 1;
	 #CLK_HALF_PERIOD sclk = 1; // Prep for next cycle.
      end
   endtask // read

// Work around use of svunit definitions in a file seen by logic synth:
 `ifdef FAIL_IF
   //
   // SPI Slave Transaction
   //
   task automatic transaction;
      output logic read_not_write;
      output logic [ADDRESS-1:0] address;
      input logic [DATA-1:0]	 data_in ;
      output logic [DATA-1:0]	 data_out ;

      begin
	 automatic integer counter;
	 miso = 1'bZ;
	 // Wait until Slave Select is asserted
         while (ss_b) @(posedge sclk);
	 // Verify R/W# bit is valid and save it.
	 `FAIL_IF($isunknown(mosi));
	 read_not_write = mosi;
	 // Now process address bits
	 counter = ADDRESS;
	 repeat(ADDRESS) @(posedge sclk) begin
	    counter = counter - 1;
	    // Verify that Slave select stays asserted
	    `FAIL_UNLESS(ss_b === 0);
	    `FAIL_IF($isunknown(ss_b));
	    // Verify address bit is valid and save it.
	    `FAIL_IF($isunknown(mosi));
	    address[counter] = mosi;
	 end
	 counter = DATA;
	 // Now process data bits
	 if (read_not_write) begin
	    // Read transaction
	    // Need to switch to driving MISO on negedge
	    repeat(DATA) @(negedge sclk) begin
	       counter = counter - 1;
	       // Verify that Slave select stays asserted
	       `FAIL_UNLESS(ss_b === 0);
	       `FAIL_IF($isunknown(ss_b));
	       // Verify MOSI stays valid
	       `FAIL_IF($isunknown(mosi));
	       miso = data_in[counter] ;
	    end
	    // Tristate MISO after data transaction ends
	    @(negedge sclk);
	    miso = 1'bZ;
	 end else begin
	    // Write transaction
	    repeat(DATA) @(posedge sclk) begin
	       counter = counter - 1;
	       // Verify that Slave select stays asserted
	       `FAIL_UNLESS(ss_b === 0);
	       `FAIL_IF($isunknown(ss_b));
	       // Verify MOSI stays valid
	       `FAIL_IF($isunknown(mosi));
	       data_out[counter] = mosi;
	    end
	 end // else: !if(read_not_write)
      end
   endtask // transaction
 `endif //  `ifndef FAIL_IF
   
endinterface : spi_t


`endif //  `if

