// =============================================================================
// Module: spi_slave.sv
// Description: SPI Slave supporting all 4 modes (CPOL/CPHA), full-duplex,
//              autonomous mode detection, and error flagging
// =============================================================================

module spi_slave #(
    parameter DATA_WIDTH = 8
)(
    // System
    input  logic                  clk,
    input  logic                  rst_n,

    // SPI Mode Control (must match master)
    input  logic                  cpol,
    input  logic                  cpha,

    // User Interface
    input  logic [DATA_WIDTH-1:0] tx_data,      // Data to send back to master
    output logic [DATA_WIDTH-1:0] rx_data,      // Data received from master
    output logic                  rx_valid,     // Pulse when rx_data is valid
    output logic                  tx_load,      // Request new tx_data
    output logic                  frame_error,  // CS deasserted mid-frame
    output logic                  mode_error,   // Unexpected clock edge

    // SPI Bus
    input  logic                  sclk,
    input  logic                  cs_n,
    input  logic                  mosi,
    output logic                  miso
);

    // -------------------------------------------------------------------------
    // Synchronizers (2-FF) for async SPI signals
    // -------------------------------------------------------------------------
    logic sclk_s1, sclk_s2, sclk_s3;
    logic cs_n_s1, cs_n_s2, cs_n_s3;
    logic mosi_s1, mosi_s2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {sclk_s1, sclk_s2, sclk_s3} <= '0;
            {cs_n_s1, cs_n_s2, cs_n_s3} <= '1;
            {mosi_s1, mosi_s2}           <= '0;
        end else begin
            sclk_s1 <= sclk;  sclk_s2 <= sclk_s1;  sclk_s3 <= sclk_s2;
            cs_n_s1 <= cs_n;  cs_n_s2 <= cs_n_s1;  cs_n_s3 <= cs_n_s2;
            mosi_s1 <= mosi;  mosi_s2 <= mosi_s1;
        end
    end

    // Edge detection on synchronized SCLK
    logic sclk_rising_sync, sclk_falling_sync;
    logic cs_n_falling, cs_n_rising;

    assign sclk_rising_sync  = !sclk_s3 &&  sclk_s2;
    assign sclk_falling_sync =  sclk_s3 && !sclk_s2;
    assign cs_n_falling      =  cs_n_s3 && !cs_n_s2;
    assign cs_n_rising       = !cs_n_s3 &&  cs_n_s2;

    // -------------------------------------------------------------------------
    // Sample / Shift edge selection (same logic as master)
    // -------------------------------------------------------------------------
    logic sample_edge, shift_edge;

    always_comb begin
        if (!cpha) begin
            sample_edge = cpol ? sclk_falling_sync : sclk_rising_sync;
            shift_edge  = cpol ? sclk_rising_sync  : sclk_falling_sync;
        end else begin
            sample_edge = cpol ? sclk_rising_sync  : sclk_falling_sync;
            shift_edge  = cpol ? sclk_falling_sync : sclk_rising_sync;
        end
    end

    // -------------------------------------------------------------------------
    // Transfer state
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        IDLE     = 2'd0,
        ACTIVE   = 2'd1,
        COMPLETE = 2'd2
    } slave_state_t;

    slave_state_t state;

    logic [DATA_WIDTH-1:0]      rx_shift;
    logic [DATA_WIDTH-1:0]      tx_shift;
    logic [$clog2(DATA_WIDTH):0]bit_cnt;
    logic                       cpha_first_done; // CPHA=1: skip first shift edge

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            rx_shift       <= '0;
            tx_shift       <= '0;
            rx_data        <= '0;
            bit_cnt        <= '0;
            rx_valid       <= 1'b0;
            tx_load        <= 1'b0;
            frame_error    <= 1'b0;
            mode_error     <= 1'b0;
            miso           <= 1'b0;
            cpha_first_done<= 1'b0;
        end else begin
            rx_valid    <= 1'b0;
            tx_load     <= 1'b0;
            frame_error <= 1'b0;
            mode_error  <= 1'b0;

            case (state)
                // ----------------------------------------------------------
                IDLE: begin
                    bit_cnt         <= '0;
                    cpha_first_done <= 1'b0;
                    if (cs_n_falling) begin
                        state    <= ACTIVE;
                        tx_shift <= tx_data;
                        tx_load  <= 1'b1;
                        // Pre-drive MISO for CPHA=0
                        if (!cpha)
                            miso <= tx_data[DATA_WIDTH-1];
                    end
                end

                // ----------------------------------------------------------
                ACTIVE: begin
                    // Abort if CS deasserted mid-frame
                    if (cs_n_rising) begin
                        if (bit_cnt != DATA_WIDTH)
                            frame_error <= 1'b1;
                        state   <= IDLE;
                        rx_data <= rx_shift;
                        rx_valid<= (bit_cnt == DATA_WIDTH);
                    end

                    // Sample MOSI on sample_edge
                    if (sample_edge && !cs_n_s2) begin
                        rx_shift <= {rx_shift[DATA_WIDTH-2:0], mosi_s2};
                        bit_cnt  <= bit_cnt + 1;

                        if (bit_cnt == DATA_WIDTH - 1) begin
                            // Last bit sampled – latch received byte
                            rx_data  <= {rx_shift[DATA_WIDTH-2:0], mosi_s2};
                            rx_valid <= 1'b1;
                            state    <= COMPLETE;
                        end
                    end

                    // Shift MISO on shift_edge
                    if (shift_edge && !cs_n_s2) begin
                        if (!cpha || cpha_first_done) begin
                            tx_shift <= {tx_shift[DATA_WIDTH-2:0], 1'b0};
                            miso     <= tx_shift[DATA_WIDTH-2];
                        end
                        cpha_first_done <= 1'b1;
                    end

                    // Unexpected edge while CS is high = mode error
                    if ((sclk_rising_sync || sclk_falling_sync) && cs_n_s2)
                        mode_error <= 1'b1;
                end

                // ----------------------------------------------------------
                COMPLETE: begin
                    if (cs_n_rising)
                        state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
