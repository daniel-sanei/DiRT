//-------------------------------------------------------------------------------
// File:    eth_pcs_pma_1g_wrapper.sv
//
// Copyright:  Ian Buckley, Ion Concepts LLC.
//
// Description:
// Wraps Xilinx 1G Ethernet PCS PMA.
//
// License: CERN-OHL-P (See LICENSE.md)
//
//-------------------------------------------------------------------------------
`include "global_defs.svh"

module eth_pcs_pma_1g_wrapper
  #(
        parameter XILINX_CLOCKING=1
    )
   (
    input wire		clk,
    input wire		reset,
    output logic	clk_125,
    // This clock can be between 6.26MHz and 62.5MHz for Ultarscale+ (See PG047 for details)
    input wire		independent_clock_bufg,
    //-------------------------------------------------------------------------------
    // CSR registers
    //-------------------------------------------------------------------------------
    input logic [31:0]	gmii_ctl,
    output logic [31:0]	gmii_stat,
    //-------------------------------------------------------------------------------
    // MDIO Interface
    //-------------------------------------------------------------------------------
    mdio_t.phy phy_mdio,
    //-------------------------------------------------------------------------------
    // GMII Interface
    //-------------------------------------------------------------------------------
    output logic	gmii_reset,
    gmii_t.xilinx_phy phy_gmii,
    //-------------------------------------------------------------------------------
    // Transceiver package pins
    //-------------------------------------------------------------------------------
    input logic		rxp,
    input logic		rxn,
    output logic	txp,
    output logic	txn,
    input logic		gtrefclk_p,
    input logic		gtrefclk_n
    );

   logic [63:0]         mdio_data;
   logic [5:0]          mdio_clk_cnt;
   logic [6:0]          mdio_bit_cnt;
   wire                 reset_x;

   wire                 gtrefclk_out;
   wire                 userclk_out;
   wire                 userclk2_out;
   wire                 rxuserclk_out;
   wire                 rxuserclk2_out;
   wire                 gtpowergood;
   wire                 resetdone;
   wire                 pma_reset_out;
   wire                 mmcm_locked_out;
   wire                 gmii_isolate;
   logic [4:0]          phyaddr;
   logic [4:0]          configuration_vector;
   logic                configuration_valid_reg;
   logic                configuration_valid;
   wire [15:0]          status_vector;
   logic                reset_csr;
   logic                signal_detect;

   always_comb begin
      gmii_stat[0] = gtpowergood;
      gmii_stat[1] = resetdone;
      gmii_stat[2] = pma_reset_out;
      gmii_stat[3] = mmcm_locked_out;
      gmii_stat[4] = gmii_isolate;
      gmii_stat[15:5] = 11'h0; // Unused
      gmii_stat[31:16] = status_vector[15:0];
   end

   always_comb begin
      reset_csr = gmii_ctl[0];
      signal_detect = ~gmii_ctl[1];
      configuration_valid = gmii_ctl[2];
      configuration_vector = gmii_ctl[7:3];
      phyaddr = 5'b0;
      // Always full duplex ethernet, no CSMA-CD
      phy_gmii.col = 1'b0;
      phy_gmii.cs = 1'b0;
   end

   always_comb
     clk_125 = userclk2_out;
   

   //-------------------------------------------------------------------------------
   // Xilinx IP - LogiCORE IP Ethernet 1000BASE-X PCS/PMA (DS264)
   //-------------------------------------------------------------------------------
   generate
      if (XILINX_CLOCKING == 1) begin
         eth_pcs_pma_1g eth_pcs_pma_1g_i0
           (
            .gtrefclk_p(gtrefclk_p),
            .gtrefclk_n(gtrefclk_n),
            .gtrefclk_out(gtrefclk_out),
            .txn(txn),
            .txp(txp),
            .rxn(rxn),
            .rxp(rxp),
            .independent_clock_bufg(independent_clock_bufg),
            .userclk_out(userclk_out),
            .userclk2_out(userclk2_out),
            .rxuserclk_out(rxuserclk_out),
            .rxuserclk2_out(rxuserclk2_out),
            .gtpowergood(gtpowergood),
            .resetdone(resetdone),
            .pma_reset_out(pma_reset_out),
            .mmcm_locked_out(mmcm_locked_out),
            .gmii_txclk(phy_gmii.txclk),
            .gmii_rxclk(phy_gmii.rxclk),
            .gmii_txd(phy_gmii.txd),
            .gmii_tx_en(phy_gmii.txen),
            .gmii_tx_er(phy_gmii.txer),
            .gmii_rxd(phy_gmii.rxd),
            .gmii_rx_dv(phy_gmii.rxdv),
            .gmii_rx_er(phy_gmii.rxer),
            .gmii_isolate(gmii_isolate),
            .mdc(phy_mdio.mdc),
            .mdio_i(phy_mdio.mdo),
            .mdio_o(phy_mdio.mdi),
            .mdio_t(), // Unused
            .phyaddr(phyaddr),
            .configuration_vector(configuration_vector),
            .configuration_valid(configuration_valid_reg),
            .status_vector(status_vector),
            .reset(reset_csr),
            .signal_detect(signal_detect)
            );
      end else if (XILINX_CLOCKING == 0) begin // if (XILINX_CLOCKING == 1)
         eth_pcs_pma_1g eth_pcs_pma_1g_i0
           (
            .gtrefclk_p(gtrefclk_p),
            .gtrefclk_n(gtrefclk_n),
            .gtrefclk_out(gtrefclk_out),
            .txn(txn),
            .txp(txp),
            .rxn(rxn),
            .rxp(rxp),
            .independent_clock_bufg(independent_clock_bufg),
            .userclk_out(userclk_out),
            .userclk2_out(userclk2_out),
            .rxuserclk_out(rxuserclk_out),
            .rxuserclk2_out(rxuserclk2_out),
            .gtpowergood(gtpowergood),
            .resetdone(resetdone),
            .pma_reset_out(pma_reset_out),
            .mmcm_locked_out(mmcm_locked_out),
            .gmii_txclk(), // No connect to prevent multiple driver issues
            .gmii_rxclk(phy_gmii.rxclk),
            .gmii_txd(phy_gmii.txd),
            .gmii_tx_en(phy_gmii.txen),
            .gmii_tx_er(phy_gmii.txer),
            .gmii_rxd(phy_gmii.rxd),
            .gmii_rx_dv(phy_gmii.rxdv),
            .gmii_rx_er(phy_gmii.rxer),
            .gmii_isolate(gmii_isolate),
            .mdc(phy_mdio.mdc),
            .mdio_i(phy_mdio.mdo),
            .mdio_o(phy_mdio.mdi),
            .mdio_t(), // Unused
            .phyaddr(phyaddr),
            .configuration_vector(configuration_vector),
            .configuration_valid(configuration_valid_reg),
            .status_vector(status_vector),
            .reset(reset_csr),
            .signal_detect(signal_detect)
            );
      end
   endgenerate


   assign  gmii_reset = ~resetdone;

   //-------------------------------------------------------------------------------
   // FIXME! - Unprotected clock domain crossing
   //-------------------------------------------------------------------------------
   logic send_config;
   
   always_ff @(posedge userclk2_out) 
     begin
        send_config  <= resetdone;
        configuration_valid_reg <= (gmii_isolate && send_config) || configuration_valid;
     end

endmodule
