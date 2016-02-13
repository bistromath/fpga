`timescale 1ns/1ps
`define NS_PER_TICK 1
`define NUM_TEST_CASES 5

`include "sim_exec_report.vh"
`include "sim_clks_rsts.vh"
`include "sim_rfnoc_lib.svh"

module noc_block_loopbacksplit_tb();
  `TEST_BENCH_INIT("noc_block_loopbacksplit",`NUM_TEST_CASES,`NS_PER_TICK);
  localparam BUS_CLK_PERIOD = $ceil(1e9/166.67e6);
  localparam CE_CLK_PERIOD  = $ceil(1e9/200e6);
  localparam NUM_CE         = 1;  // Number of Computation Engines / User RFNoC blocks to simulate
  localparam NUM_STREAMS    = 2;  // Number of test bench streams
  `RFNOC_SIM_INIT(NUM_CE, NUM_STREAMS, BUS_CLK_PERIOD, CE_CLK_PERIOD);
  `RFNOC_ADD_BLOCK(noc_block_loopbacksplit, 0);

  localparam SPP = 600; // Samples per packet

  /********************************************************
  ** Verification
  ********************************************************/
  initial begin : tb_main
    string s;
    logic [31:0] random_word;
    logic [63:0] readback;

    /********************************************************
    ** Test 1 -- Reset
    ********************************************************/
    `TEST_CASE_START("Wait for Reset");
    while (bus_rst) @(posedge bus_clk);
    while (ce_rst) @(posedge ce_clk);
    `TEST_CASE_DONE(~bus_rst & ~ce_rst);

    /********************************************************
    ** Test 2 -- Check for correct NoC IDs
    ********************************************************/
    `TEST_CASE_START("Check NoC ID");
    // Read NOC IDs
    tb_streamer.read_reg(sid_noc_block_loopbacksplit, RB_NOC_ID, readback);
    $display("Read LOOPBACKSPLIT NOC ID: %16x", readback);
    `ASSERT_ERROR(readback == noc_block_loopbacksplit.NOC_ID, "Incorrect NOC ID");
    `TEST_CASE_DONE(1);

    /********************************************************
    ** Test 3 -- Connect RFNoC blocks
    ********************************************************/
    `TEST_CASE_START("Connect RFNoC blocks");
    `RFNOC_CONNECT(noc_block_tb,noc_block_loopbacksplit,SC16,SPP);
    `RFNOC_CONNECT_BLOCK_PORT(noc_block_loopbacksplit,0,noc_block_tb,0,SC16,SPP);
    `RFNOC_CONNECT_BLOCK_PORT(noc_block_loopbacksplit,1,noc_block_tb,1,SC16,SPP);
    `TEST_CASE_DONE(1);

    /********************************************************
    ** Test 4 -- Write / readback user registers
    ********************************************************/
    `TEST_CASE_START("Write / readback user registers");
    random_word = $random();
    tb_streamer.write_user_reg(sid_noc_block_loopbacksplit, noc_block_loopbacksplit.SR_TEST_REG_0, random_word);
    tb_streamer.read_user_reg(sid_noc_block_loopbacksplit, 0, readback);
    $sformat(s, "User register 0 incorrect readback! Expected: %0d, Actual %0d", readback[31:0], random_word);
    `ASSERT_ERROR(readback[31:0] == random_word, s);
    random_word = $random();
    tb_streamer.write_user_reg(sid_noc_block_loopbacksplit, noc_block_loopbacksplit.SR_TEST_REG_1, random_word);
    tb_streamer.read_user_reg(sid_noc_block_loopbacksplit, 1, readback);
    $sformat(s, "User register 1 incorrect readback! Expected: %0d, Actual %0d", readback[31:0], random_word);
    `ASSERT_ERROR(readback[31:0] == random_word, s);
    `TEST_CASE_DONE(1);

    /********************************************************
    ** Test 5 -- Test sequence
    ********************************************************/
    // loopbacksplit's user code is a loopback, so we should receive
    // back exactly what we send
    `TEST_CASE_START("Test sequence");
    fork
      begin
        cvita_payload_t send_payload;
        for (int i = 0; i < SPP/2; i++) begin
          send_payload.push_back(64'(i));
        end
        tb_streamer.send(send_payload);
      end
      begin
        cvita_payload_t recv_payload[0:1];
        cvita_metadata_t md[0:1];
        logic [63:0] expected_value;
        $display("Receiving on DATA port");
        tb_streamer.recv(recv_payload[1],md[1], 1);
        $display("Receiving on CONTROL port");
        tb_streamer.recv(recv_payload[0],md[0], 0);
        for (int i = 0; i < SPP/2; i++) begin
          expected_value = i;
          $sformat(s, "Incorrect value received! Expected: %0d, Received: %0d", expected_value, recv_payload[1][i]);
          `ASSERT_ERROR(recv_payload[1][i] == expected_value, s);
        end
        expected_value = 64'hDEAD_BEEF_DEAD_BEEF;
        $sformat(s, "Incorrect value received! Expected: %0d, Received: %0d", expected_value, recv_payload[0][0]);
        `ASSERT_ERROR(recv_payload[0][0] == expected_value ,s);
      end
    join
    fork
      begin
        cvita_payload_t send_payload;
        for (int i = 0; i < SPP/2; i++) begin
          send_payload.push_back(64'(i));
        end
        tb_streamer.send(send_payload);
      end
      begin
        cvita_payload_t recv_payload[0:1];
        cvita_metadata_t md[0:1];
        logic [63:0] expected_value;
        $display("Receiving on DATA port");
        tb_streamer.recv(recv_payload[1],md[1], 1);
        $display("Receiving on CONTROL port");
        tb_streamer.recv(recv_payload[0],md[0], 0);
        for (int i = 0; i < SPP/2; i++) begin
          expected_value = i;
          $sformat(s, "Incorrect value received! Expected: %0d, Received: %0d", expected_value, recv_payload[1][i]);
          `ASSERT_ERROR(recv_payload[1][i] == expected_value, s);
        end
        expected_value = 64'hDEAD_BEEF_DEAD_BEEF;
        $sformat(s, "Incorrect value received! Expected: %0d, Received: %0d", expected_value, recv_payload[0][0]);
        `ASSERT_ERROR(recv_payload[0][0] == expected_value ,s);
      end
    join
    `TEST_CASE_DONE(1);
    `TEST_BENCH_DONE;

  end
endmodule
