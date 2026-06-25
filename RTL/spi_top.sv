// =============================================================================
// Module: spi_top.sv
// Description: Top-level integrating SPI Master and Slave for full-duplex
//              loopback verification with mode-switching support
// =============================================================================

module spi_top #(
    parameter DATA_WIDTH = 8,
    parameter CLK_DIV    = 4
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // Mode selection
    input  logic                  cpol,
    input  logic                  cpha,

    // Master user interface
    input  logic                  start,
    input  logic [DATA_WIDTH-1:0] m_tx_data,    // Master → Slave
    output logic [DATA_WIDTH-1:0] m_rx_data,    // Master ← Slave
    output logic                  m_busy,
    output logic                  m_done,
    output logic                  m_mode_error,

    // Slave user interface
    input  logic [DATA_WIDTH-1:0] s_tx_data,    // Slave → Master
    output logic [DATA_WIDTH-1:0] s_rx_data,    // Slave ← Master
    output logic                  s_rx_valid,
    output logic                  s_frame_error,
    output logic                  s_mode_error,

    // Expose raw SPI bus for probing
    output logic                  sclk,
    output logic                  cs_n,
    output logic                  mosi,
    output logic                  miso
);

    spi_master #(
        .DATA_WIDTH(DATA_WIDTH),
        .CLK_DIV   (CLK_DIV)
    ) u_master (
        .clk        (clk),
        .rst_n      (rst_n),
        .cpol       (cpol),
        .cpha       (cpha),
        .start      (start),
        .tx_data    (m_tx_data),
        .rx_data    (m_rx_data),
        .busy       (m_busy),
        .done       (m_done),
        .mode_error (m_mode_error),
        .sclk       (sclk),
        .cs_n       (cs_n),
        .mosi       (mosi),
        .miso       (miso)
    );

    spi_slave #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_slave (
        .clk        (clk),
        .rst_n      (rst_n),
        .cpol       (cpol),
        .cpha       (cpha),
        .tx_data    (s_tx_data),
        .rx_data    (s_rx_data),
        .rx_valid   (s_rx_valid),
        .tx_load    (),
        .frame_error(s_frame_error),
        .mode_error (s_mode_error),
        .sclk       (sclk),
        .cs_n       (cs_n),
        .mosi       (mosi),
        .miso       (miso)
    );

endmodule
