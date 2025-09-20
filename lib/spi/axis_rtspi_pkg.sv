//-----------------------------------------------------------------------------
// File:    axis_rtspi_pkg.sv
//
// Author:  Ian Buckley, Ion Concepts LLC
//
// Description:
// Sub-system wide shared definitions for axis_rtspi
//
//-----------------------------------------------------------------------------

package axis_rtspi_pkg;

   typedef struct packed {
      logic	  SPI_RW;
      logic	  SPI_A14;
      logic	  SPI_A13;
      logic	  SPI_A12;
      logic	  SPI_A11;
      logic	  SPI_A10;
      logic	  SPI_A9;
      logic	  SPI_A8;
      logic	  SPI_A7;
      logic	  SPI_A6;
      logic	  SPI_A5;
      logic	  SPI_A4;
      logic	  SPI_A3;
      logic	  SPI_A2;
      logic	  SPI_A1;
      logic	  SPI_A0;
      logic	  SPI_D7;
      logic	  SPI_D6;
      logic	  SPI_D5;
      logic	  SPI_D4;
      logic	  SPI_D3;
      logic	  SPI_D2;
      logic	  SPI_D1;
      logic	  SPI_D0;
   } rtspi_command_t;

endpackage : axis_rtspi_pkg
