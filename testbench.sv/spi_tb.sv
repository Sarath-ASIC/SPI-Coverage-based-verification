// =============================================================================
// Testbench: spi_tb.sv  (VCS-compatible)
// NOTE: spi_coverage_pkg is defined in design.sv — do NOT redeclare here
// =============================================================================
`timescale 1ns/1ps

// =============================================================================
module spi_tb;
    import spi_coverage_pkg::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter DATA_WIDTH = 8;
    parameter CLK_DIV    = 4;
    parameter CLK_PERIOD = 10;

    // =========================================================================
    // DUT Signals
    // =========================================================================
    logic                  clk, rst_n;
    logic                  cpol, cpha;
    logic                  start;
    logic [DATA_WIDTH-1:0] m_tx_data, m_rx_data;
    logic                  m_busy, m_done, m_mode_error;
    logic [DATA_WIDTH-1:0] s_tx_data, s_rx_data;
    logic                  s_rx_valid, s_frame_error, s_mode_error;
    logic                  sclk, cs_n, mosi, miso;

    // =========================================================================
    // DUT Instantiation — explicit port connections (VCS compatible)
    // =========================================================================
    spi_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .CLK_DIV   (CLK_DIV)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .cpol         (cpol),
        .cpha         (cpha),
        .start        (start),
        .m_tx_data    (m_tx_data),
        .m_rx_data    (m_rx_data),
        .m_busy       (m_busy),
        .m_done       (m_done),
        .m_mode_error (m_mode_error),
        .s_tx_data    (s_tx_data),
        .s_rx_data    (s_rx_data),
        .s_rx_valid   (s_rx_valid),
        .s_frame_error(s_frame_error),
        .s_mode_error (s_mode_error),
        .sclk         (sclk),
        .cs_n         (cs_n),
        .mosi         (mosi),
        .miso         (miso)
    );

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // Scoreboard & Statistics
    // =========================================================================
    int pass_cnt = 0;
    int fail_cnt = 0;
    int txn_cnt  = 0;

    spi_txn_t txn_log[$];

    // =========================================================================
    // COVERGROUP: SPI Mode Coverage
    // =========================================================================
    covergroup cg_spi_mode @(posedge m_done);
        cp_cpol : coverpoint cpol { bins c0={0}; bins c1={1}; }
        cp_cpha : coverpoint cpha { bins p0={0}; bins p1={1}; }
        cp_mode : cross cp_cpol, cp_cpha;
    endgroup

    // =========================================================================
    // COVERGROUP: Data Pattern Coverage
    // =========================================================================
    covergroup cg_data_pattern @(posedge m_done);
        cp_m_tx: coverpoint m_tx_data {
            bins all_zeros = {8'h00};
            bins all_ones  = {8'hFF};
            bins mid_range = {[8'h01:8'hFE]};
        }
        cp_s_tx: coverpoint s_tx_data {
            bins all_zeros = {8'h00};
            bins all_ones  = {8'hFF};
            bins mid_range = {[8'h01:8'hFE]};
        }
    endgroup

    // =========================================================================
    // COVERGROUP: Error Scenario Coverage
    // =========================================================================
    covergroup cg_errors @(posedge clk);
        cp_frame_err : coverpoint s_frame_error { bins seen={1}; }
        cp_mode_err_m: coverpoint m_mode_error  { bins seen={1}; }
        cp_mode_err_s: coverpoint s_mode_error  { bins seen={1}; }
    endgroup

    // =========================================================================
    // COVERGROUP: Mode Switching
    // =========================================================================
    covergroup cg_mode_switch @(posedge m_done);
        cp_mode_trans: coverpoint {cpol,cpha} {
            bins m0_to_m1 = (2'b00 => 2'b01);
            bins m0_to_m2 = (2'b00 => 2'b10);
            bins m0_to_m3 = (2'b00 => 2'b11);
            bins m1_to_m0 = (2'b01 => 2'b00);
            bins m1_to_m2 = (2'b01 => 2'b10);
            bins m2_to_m0 = (2'b10 => 2'b00);
            bins m2_to_m3 = (2'b10 => 2'b11);
            bins m3_to_m0 = (2'b11 => 2'b00);
            bins m3_to_m1 = (2'b11 => 2'b01);
        }
    endgroup

    // =========================================================================
    // Coverage Instantiation
    // =========================================================================
    cg_spi_mode     cov_mode   = new();
    cg_data_pattern cov_data   = new();
    cg_errors       cov_errors = new();
    cg_mode_switch  cov_switch = new();

    // =========================================================================
    // SVA: Protocol Assertions
    // =========================================================================
    // A1: CS must be low before any SCLK edge
    property p_cs_before_sclk;
        @(posedge clk) $rose(sclk) |-> !cs_n;
    endproperty
    A_CS_BEFORE_SCLK: assert property (p_cs_before_sclk)
        else $error("[SVA FAIL] SCLK rose while CS_N was HIGH");

    // A2: SCLK idle level must match CPOL when CS is high
    property p_sclk_idle_level;
        @(posedge clk) cs_n |-> (sclk === cpol);
    endproperty
    A_SCLK_IDLE: assert property (p_sclk_idle_level)
        else $error("[SVA FAIL] SCLK idle level != CPOL");

    // A3: busy must clear after done
    property p_busy_after_done;
        @(posedge clk) $rose(m_done) |=> !m_busy;
    endproperty
    A_BUSY_AFTER_DONE: assert property (p_busy_after_done)
        else $error("[SVA FAIL] m_busy still high after m_done");

    // A4: done is single-cycle pulse
    property p_done_pulse;
        @(posedge clk) $rose(m_done) |=> !m_done;
    endproperty
    A_DONE_PULSE: assert property (p_done_pulse)
        else $error("[SVA FAIL] m_done not a single-cycle pulse");

    // A5: rx_valid is single-cycle pulse
    property p_rxvalid_pulse;
        @(posedge clk) $rose(s_rx_valid) |=> !s_rx_valid;
    endproperty
    A_RXVALID_PULSE: assert property (p_rxvalid_pulse)
        else $error("[SVA FAIL] s_rx_valid not a single-cycle pulse");

    // =========================================================================
    // Task: Reset
    // =========================================================================
    task do_reset();
        rst_n     = 0;
        start     = 0;
        cpol      = 0;
        cpha      = 0;
        m_tx_data = 8'h00;
        s_tx_data = 8'h00;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);
        $display("[%0t] Reset complete", $time);
    endtask

    // =========================================================================
    // Task: Single SPI Transaction
    // =========================================================================
    task automatic do_transaction(
        input logic [DATA_WIDTH-1:0] m_data,
        input logic [DATA_WIDTH-1:0] s_data,
        input logic                  i_cpol,
        input logic                  i_cpha,
        input string                 test_name
    );
        spi_txn_t txn;
        $display("[%0t] START: %s | Mode%0d (CPOL=%0b CPHA=%0b) | M->S=0x%02X S->M=0x%02X",
                 $time, test_name, {i_cpol,i_cpha}, i_cpol, i_cpha, m_data, s_data);

        @(posedge clk);
        wait (!m_busy);
        @(posedge clk);

        cpol      = i_cpol;
        cpha      = i_cpha;
        m_tx_data = m_data;
        s_tx_data = s_data;
        @(posedge clk);

        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        @(posedge m_done);
        @(posedge clk);

        // Scoreboard: master RX == slave TX
        if (m_rx_data === s_data) begin
            $display("[%0t] PASS: Master rcvd 0x%02X (expected 0x%02X)",
                     $time, m_rx_data, s_data);
            pass_cnt++;
        end else begin
            $error("[%0t] FAIL: Master rcvd 0x%02X expected 0x%02X",
                   $time, m_rx_data, s_data);
            fail_cnt++;
        end

        // Scoreboard: slave RX == master TX
        if (s_rx_data === m_data) begin
            $display("[%0t] PASS: Slave  rcvd 0x%02X (expected 0x%02X)",
                     $time, s_rx_data, m_data);
            pass_cnt++;
        end else begin
            $error("[%0t] FAIL: Slave  rcvd 0x%02X expected 0x%02X",
                   $time, s_rx_data, m_data);
            fail_cnt++;
        end

        txn.m_tx = m_data; txn.s_tx = s_data;
        txn.m_rx = m_rx_data; txn.s_rx = s_rx_data;
        txn.cpol = i_cpol;  txn.cpha = i_cpha;
        txn_log.push_back(txn);
        txn_cnt++;

        @(posedge clk);
    endtask

    // =========================================================================
    // Task: SCLK idle level check
    // =========================================================================
    task check_sclk_idle(input logic i_cpol);
        @(posedge clk);
        if (sclk !== i_cpol)
            $error("[CLK_ALIGN] FAIL: SCLK idle=%0b expected CPOL=%0b", sclk, i_cpol);
        else
            $display("[CLK_ALIGN] PASS: SCLK idle matches CPOL=%0b", i_cpol);
    endtask

    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, spi_tb);

        do_reset();

        // -----------------------------------------------------------------
        // TEST 1: All 4 SPI Modes
        // -----------------------------------------------------------------
        $display("\n=== TEST 1: All 4 SPI Modes ===");
        do_transaction(8'hA5, 8'h5A, 1'b0, 1'b0, "Mode0");
        do_transaction(8'hA5, 8'h5A, 1'b0, 1'b1, "Mode1");
        do_transaction(8'hA5, 8'h5A, 1'b1, 1'b0, "Mode2");
        do_transaction(8'hA5, 8'h5A, 1'b1, 1'b1, "Mode3");

        // -----------------------------------------------------------------
        // TEST 2: Boundary Values
        // -----------------------------------------------------------------
        $display("\n=== TEST 2: Boundary Data Values ===");
        do_transaction(8'h00, 8'h00, 1'b0, 1'b0, "AllZeros_M0");
        do_transaction(8'hFF, 8'hFF, 1'b0, 1'b0, "AllOnes_M0");
        do_transaction(8'h00, 8'h00, 1'b1, 1'b1, "AllZeros_M3");
        do_transaction(8'hFF, 8'hFF, 1'b1, 1'b1, "AllOnes_M3");
        // Walking ones — explicit calls (VCS safe, no foreach on literals)
        do_transaction(8'h01, 8'hFE, 1'b0, 1'b0, "Walk_b0");
        do_transaction(8'h02, 8'hFD, 1'b0, 1'b0, "Walk_b1");
        do_transaction(8'h04, 8'hFB, 1'b0, 1'b0, "Walk_b2");
        do_transaction(8'h08, 8'hF7, 1'b0, 1'b0, "Walk_b3");
        do_transaction(8'h10, 8'hEF, 1'b0, 1'b0, "Walk_b4");
        do_transaction(8'h20, 8'hDF, 1'b0, 1'b0, "Walk_b5");
        do_transaction(8'h40, 8'hBF, 1'b0, 1'b0, "Walk_b6");
        do_transaction(8'h80, 8'h7F, 1'b0, 1'b0, "Walk_b7");

        // -----------------------------------------------------------------
        // TEST 3: Mode Switching
        // -----------------------------------------------------------------
        $display("\n=== TEST 3: Mode Switching ===");
        do_transaction(8'hDE, 8'hAD, 1'b0, 1'b0, "Sw_M0");
        do_transaction(8'hBE, 8'hEF, 1'b0, 1'b1, "Sw_M0toM1");
        do_transaction(8'hCA, 8'hFE, 1'b1, 1'b0, "Sw_M1toM2");
        do_transaction(8'hBA, 8'hBE, 1'b1, 1'b1, "Sw_M2toM3");
        do_transaction(8'hF0, 8'h0F, 1'b0, 1'b0, "Sw_M3toM0");

        // -----------------------------------------------------------------
        // TEST 4: Repeated same-mode (clock stability)
        // -----------------------------------------------------------------
        $display("\n=== TEST 4: Repeated Mode0 Transfers ===");
        do_transaction(8'h11, 8'hEE, 1'b0, 1'b0, "Rep_M0_1");
        do_transaction(8'h22, 8'hDD, 1'b0, 1'b0, "Rep_M0_2");
        do_transaction(8'h33, 8'hCC, 1'b0, 1'b0, "Rep_M0_3");
        do_transaction(8'h44, 8'hBB, 1'b0, 1'b0, "Rep_M0_4");
        do_transaction(8'h55, 8'hAA, 1'b1, 1'b1, "Rep_M3_1");
        do_transaction(8'h66, 8'h99, 1'b1, 1'b1, "Rep_M3_2");
        do_transaction(8'h77, 8'h88, 1'b1, 1'b1, "Rep_M3_3");
        do_transaction(8'h88, 8'h77, 1'b1, 1'b1, "Rep_M3_4");

        // -----------------------------------------------------------------
        // TEST 5: Random stimulus
        // -----------------------------------------------------------------
        $display("\n=== TEST 5: Random Stimulus ===");
        begin
            logic [7:0] rtx, stx;
            logic       rcp, rch;
            integer i;
            for (i = 0; i < 32; i++) begin
                rtx = $urandom();
                stx = $urandom();
                rcp = $urandom_range(0,1);
                rch = $urandom_range(0,1);
                do_transaction(rtx, stx, rcp, rch, "Random");
            end
        end

        // -----------------------------------------------------------------
        // TEST 6: Clock Alignment Check
        // -----------------------------------------------------------------
        $display("\n=== TEST 6: Clock Phase Alignment ===");
        wait(cs_n === 1'b1);
        cpol = 1'b0; repeat(2) @(posedge clk); check_sclk_idle(1'b0);
        cpol = 1'b1; repeat(2) @(posedge clk); check_sclk_idle(1'b1);

        // -----------------------------------------------------------------
        // TEST 7: Error Injection (mode switch mid-transfer)
        // -----------------------------------------------------------------
        $display("\n=== TEST 7: Error Injection ===");
        cpol = 1'b0; cpha = 1'b0;
        m_tx_data = 8'h55; s_tx_data = 8'hAA;
        start = 1'b1; @(posedge clk); start = 1'b0;
        repeat(CLK_DIV * 4) @(posedge clk);
        cpol = 1'b1; // intentional mid-transfer violation
        wait(m_done || m_mode_error);
        if (m_mode_error)
            $display("[%0t] PASS: Mode error flag asserted correctly", $time);
        cpol = 1'b0;
        do_reset();

        // -----------------------------------------------------------------
        // FINAL REPORT
        // -----------------------------------------------------------------
        repeat(10) @(posedge clk);
        $display("\n");
        $display("=======================================================");
        $display("  SPI VERIFICATION REPORT");
        $display("=======================================================");
        $display("  Transactions  : %0d", txn_cnt);
        $display("  Checks PASS   : %0d", pass_cnt);
        $display("  Checks FAIL   : %0d", fail_cnt);
        $display("-------------------------------------------------------");
        $display("  Mode Coverage      : %.1f%%", cov_mode.get_coverage());
        $display("  Data Coverage      : %.1f%%", cov_data.get_coverage());
        $display("  Error Coverage     : %.1f%%", cov_errors.get_coverage());
        $display("  Mode Switch Cov    : %.1f%%", cov_switch.get_coverage());
        $display("=======================================================");
        if (fail_cnt == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d FAILURES DETECTED ***", fail_cnt);
        $display("=======================================================\n");
        $finish;
    end

    // =========================================================================
    // Timeout Watchdog
    // =========================================================================
    initial begin
        #2_000_000;
        $error("SIMULATION TIMEOUT");
        $finish;
    end

    // =========================================================================
    // Protocol Monitor
    // =========================================================================
    always @(posedge sclk)
        if (!cs_n)
            $display("[MON %0t] SCLK+ MOSI=%0b MISO=%0b Mode{%0b,%0b}",
                     $time, mosi, miso, cpol, cpha);

    always @(negedge sclk)
        if (!cs_n)
            $display("[MON %0t] SCLK- MOSI=%0b MISO=%0b Mode{%0b,%0b}",
                     $time, mosi, miso, cpol, cpha);

    always @(negedge cs_n)
        $display("[MON %0t] CS_ASSERT  CPOL=%0b CPHA=%0b", $time, cpol, cpha);

    always @(posedge cs_n)
        $display("[MON %0t] CS_DEASSERT", $time);

endmodule
