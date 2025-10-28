//-----------------------------------------------------------------------------
// File:    port_1000basex.sv
//
// Author:  Ian Buckley, Ion Concepts LLC.
//
// Description:
// Provdes 68 b AXIS interface to core passing ethernet frames.
// Instantiates Xilinx PCS/PMA IP for transceiver
// Uses legacy Ettus 1G MAC
//
//
//
// License: CERN-OHL-P (See LICENSE.md)
//
//-----------------------------------------------------------------------------
`include "global_defs.svh"

module port_1000basex
  (
   input wire	       clk,
   input wire	       rst,
   // For Ultrascale+ this can be between 6.25MHz and 62.5MHz (See PG047)
   input wire	       independent_clock_bufg,
   // CSR interface
   input wire [31:0]   csr_gmii_ctl,
   output logic [31:0] csr_gmii_stat,
   //-------------------------------------------------------------------------------
   // Transceiver clock
   //-------------------------------------------------------------------------------
   input wire	       refclk_p,
   input wire	       refclk_n,
   //-------------------------------------------------------------------------------
   // External Ethernet Base-X
   //-------------------------------------------------------------------------------
   input wire	       rx_p,
   input wire	       rx_n,
   output wire	       tx_p,
   output wire	       tx_n,
   //-------------------------------------------------------------------------------
   // Ethernet Management
   //-------------------------------------------------------------------------------
   //i2c.master i2c_sfp,
   //-------------------------------------------------------------------------------
   // Ethernet packet AXIS Busses
   //-------------------------------------------------------------------------------
   axis_t.master axis_ethernet_out,
   axis_t.slave axis_ethernet_in
   );

   //-------------------------------------------------------------------------------
   // 125MHz clock domain driven from PCS/PMA
   //-------------------------------------------------------------------------------
   wire clk_125;

   // Ethernet specific buses
   gmii_t gmii_eth0();
   mdio_t phy_mdio();
   
   //-------------------------------------------------------------------------------
   // MAC for external ethernet PCS/PMA
   // Wrapper on Ettus 1G MAC provides clock domain handoff,
   // interface conversion to DiRT, and FIFO buffering.
   //-------------------------------------------------------------------------------
   gemac_wrapper
     #(
       .RX_FLOW_CTRL(0),
       .PORTNUM(8'd0)
       )
   gemac_wrapper_i0
     (
      .clk(clk),
      .clk125(clk_125),
      .rst(rst),
      //-------------------------------------------------------------------------------
      // GMII Interface
      //-------------------------------------------------------------------------------
      .gmii_reset(),
      .mac_gmii(gmii_eth0),
      //-------------------------------------------------------------------------------
      // AXIS interfaces
      //-------------------------------------------------------------------------------
      .in_axis(axis_ethernet_in),
      .out_axis(axis_ethernet_out)
      );
   

   //-------------------------------------------------------------------------------
   // 1G Ethernet PCS/PMA wrapper
   //-------------------------------------------------------------------------------
   eth_pcs_pma_1g_wrapper
     #(
       .XILINX_CLOCKING(1'b0) // Avoid multidriver issue on GMII txclk
       )
   eth_pcs_pma_1g_wrapper_i0
     (
      .clk          (clk),
      .reset        (rst),
      .clk_125      (clk_125),
      .independent_clock_bufg(independent_clock_bufg),
      //-------------------------------------------------------------------------------
      // CSR registers
      //-------------------------------------------------------------------------------
      .gmii_ctl     (csr_gmii_ctl),
      .gmii_stat    (csr_gmii_stat),
      //-------------------------------------------------------------------------------
      // MDIO Interface
      //-------------------------------------------------------------------------------
      .phy_mdio     (phy_mdio),
      //-------------------------------------------------------------------------------
      // GMII Interface
      //-------------------------------------------------------------------------------
      .phy_gmii     (gmii_eth0),
      //-------------------------------------------------------------------------------
      // Transceiver package pins
      //-------------------------------------------------------------------------------
      .gtrefclk_p   (refclk_p),
      .gtrefclk_n   (refclk_n),
      .rxp          (rx_p),
      .rxn          (rx_n),
      .txp          (tx_p),
      .txn          (tx_n)
      );

endmodule // port_1000basex

      
      
      
