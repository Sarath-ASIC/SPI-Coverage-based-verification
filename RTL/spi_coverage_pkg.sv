// =============================================================================
// Package: spi_coverage_pkg.sv
// Description: Covergroups, assertions, and checker tasks for SPI verification
// =============================================================================

package spi_coverage_pkg;

    // =========================================================================
    // SPI Transaction Record (used in scoreboard & coverage)
    // =========================================================================
    typedef struct {
        logic [7:0] m_tx;   // Master sent
        logic [7:0] s_tx;   // Slave sent
        logic [7:0] m_rx;   // Master received
        logic [7:0] s_rx;   // Slave received
        logic       cpol;
        logic       cpha;
    } spi_txn_t;

    // =========================================================================
    // Mode coverage helper: encode {CPOL,CPHA} as 2-bit mode number
    // =========================================================================
    function automatic logic [1:0] spi_mode(input logic cpol, cpha);
        return {cpol, cpha};
    endfunction

endpackage
