// =============================================================================
// Module: spi_master.sv
// Description: SPI Master supporting all 4 modes (CPOL/CPHA), full-duplex,
//              configurable clock divider, and mode switching capability
// =============================================================================

module spi_master #(
    parameter DATA_WIDTH  = 8,
    parameter CLK_DIV     = 4        // SCK = sys_clk / (2 * CLK_DIV)
)(
    // System
    input  logic                  clk,
    input  logic                  rst_n,

    // SPI Mode Control
    input  logic                  cpol,       // Clock Polarity
    input  logic                  cpha,       // Clock Phase

    // User Interface
    input  logic                  start,
    input  logic [DATA_WIDTH-1:0] tx_data,
    output logic [DATA_WIDTH-1:0] rx_data,
    output logic                  busy,
    output logic                  done,
    output logic                  mode_error, // Detected protocol error

    // SPI Bus
    output logic                  sclk,
    output logic                  cs_n,
    output logic                  mosi,
    input  logic                  miso
);

    // -------------------------------------------------------------------------
    // Internal signals
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE    = 3'd0,
        CS_LOW  = 3'd1,
        TRANSFER= 3'd2,
        CS_HIGH = 3'd3,
        DONE    = 3'd4
    } state_t;

    state_t                   state, next_state;

    logic [$clog2(CLK_DIV)-1:0] clk_cnt;
    logic                       sclk_en;
    logic                       sclk_r;
    logic                       sclk_rising, sclk_falling;

    logic [DATA_WIDTH-1:0]      tx_shift;
    logic [DATA_WIDTH-1:0]      rx_shift;
    logic [$clog2(DATA_WIDTH):0]bit_cnt;
    logic                       sample_edge, shift_edge;

    logic [2:0]                 cs_cnt;
    logic                       prev_cpol, prev_cpha;
    logic                       mode_switch_guard; // prevent hot-mode-switch mid transfer

    // -------------------------------------------------------------------------
    // Clock divider & SCK generation
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt <= '0;
            sclk_r  <= 1'b0;
        end else if (sclk_en) begin
            if (clk_cnt == CLK_DIV - 1) begin
                clk_cnt <= '0;
                sclk_r  <= ~sclk_r;
            end else
                clk_cnt <= clk_cnt + 1;
        end else begin
            clk_cnt <= '0;
            sclk_r  <= cpol; // idle level = CPOL
        end
    end

    assign sclk_rising  = sclk_en && (clk_cnt == CLK_DIV-1) && !sclk_r;
    assign sclk_falling = sclk_en && (clk_cnt == CLK_DIV-1) &&  sclk_r;

    // Drive SCK output according to CPOL
    assign sclk = cs_n ? cpol : sclk_r;

    // -------------------------------------------------------------------------
    // Sample / Shift edge selection based on CPHA
    // CPHA=0: sample on first edge (leading), shift on trailing
    // CPHA=1: sample on second edge (trailing), shift on leading
    // -------------------------------------------------------------------------
    always_comb begin
        if (!cpha) begin
            // CPOL=0: leading=rising, trailing=falling
            // CPOL=1: leading=falling, trailing=rising
            sample_edge = cpol ? sclk_falling : sclk_rising;
            shift_edge  = cpol ? sclk_rising  : sclk_falling;
        end else begin
            sample_edge = cpol ? sclk_rising  : sclk_falling;
            shift_edge  = cpol ? sclk_falling : sclk_rising;
        end
    end

    // -------------------------------------------------------------------------
    // FSM - Sequential
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    // -------------------------------------------------------------------------
    // FSM - Combinational
    // -------------------------------------------------------------------------
    always_comb begin
        next_state = state;
        case (state)
            IDLE:     if (start)              next_state = CS_LOW;
            CS_LOW:   if (cs_cnt == 3'd3)     next_state = TRANSFER;
            TRANSFER: if (bit_cnt == DATA_WIDTH && !sclk_en)
                                              next_state = CS_HIGH;
            CS_HIGH:  if (cs_cnt == 3'd3)     next_state = DONE;
            DONE:                             next_state = IDLE;
            default:                          next_state = IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Counters and Shift Registers
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cs_n        <= 1'b1;
            sclk_en     <= 1'b0;
            busy        <= 1'b0;
            done        <= 1'b0;
            mode_error  <= 1'b0;
            tx_shift    <= '0;
            rx_shift    <= '0;
            rx_data     <= '0;
            bit_cnt     <= '0;
            cs_cnt      <= '0;
            mosi        <= 1'b0;
            prev_cpol   <= 1'b0;
            prev_cpha   <= 1'b0;
            mode_switch_guard <= 1'b0;
        end else begin
            done       <= 1'b0;
            mode_error <= 1'b0;

            case (state)
                IDLE: begin
                    cs_n      <= 1'b1;
                    sclk_en   <= 1'b0;
                    busy      <= 1'b0;
                    bit_cnt   <= '0;
                    cs_cnt    <= '0;
                    mode_switch_guard <= 1'b0;
                    if (start) begin
                        tx_shift  <= tx_data;
                        prev_cpol <= cpol;
                        prev_cpha <= cpha;
                        busy      <= 1'b1;
                    end
                end

                CS_LOW: begin
                    cs_n   <= 1'b0;
                    cs_cnt <= cs_cnt + 1;
                    // pre-drive MOSI for CPHA=0
                    if (cs_cnt == 3'd0 && !cpha)
                        mosi <= tx_shift[DATA_WIDTH-1];
                end

                TRANSFER: begin
                    sclk_en <= 1'b1;
                    mode_switch_guard <= 1'b1;

                    // Detect illegal mid-transfer mode switch
                    if ((cpol !== prev_cpol || cpha !== prev_cpha) && mode_switch_guard)
                        mode_error <= 1'b1;

                    // Shift out on shift_edge
                    if (shift_edge && bit_cnt < DATA_WIDTH) begin
                        tx_shift <= {tx_shift[DATA_WIDTH-2:0], 1'b0};
                        mosi     <= tx_shift[DATA_WIDTH-2]; // next bit
                        bit_cnt  <= bit_cnt + 1;
                    end

                    // Sample in on sample_edge
                    if (sample_edge)
                        rx_shift <= {rx_shift[DATA_WIDTH-2:0], miso};

                    // End of transfer
                    if (bit_cnt == DATA_WIDTH) begin
                        sclk_en <= 1'b0;
                    end
                end

                CS_HIGH: begin
                    cs_n    <= 1'b1;
                    cs_cnt  <= cs_cnt + 1;
                    rx_data <= rx_shift;
                end

                DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                end
            endcase
        end
    end

endmodule
