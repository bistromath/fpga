`timescale 1ns/1ps
`define NS_PER_TICK 1
`define NUM_TEST_CASES 7

`include "sim_exec_report.vh"
`include "sim_clks_rsts.vh"
`include "sim_rfnoc_lib.svh"

module noc_block_delay_tb();
  `TEST_BENCH_INIT("noc_block_delay",`NUM_TEST_CASES,`NS_PER_TICK);
  localparam BUS_CLK_PERIOD = $ceil(1e9/166.67e6);
  localparam CE_CLK_PERIOD  = $ceil(1e9/200e6);
  localparam NUM_CE         = 1;  // Number of Computation Engines / User RFNoC blocks to simulate
  localparam NUM_STREAMS    = 1;  // Number of test bench streams
  `RFNOC_SIM_INIT(NUM_CE, NUM_STREAMS, BUS_CLK_PERIOD, CE_CLK_PERIOD);
  `RFNOC_ADD_BLOCK(noc_block_delay, 0);

  localparam SPP = 32; // Samples per packet

  /********************************************************
  ** Verification
  ********************************************************/
  initial begin : tb_main
    string s;
    logic [31:0] idelay, qdelay;
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
    tb_streamer.read_reg(sid_noc_block_delay, RB_NOC_ID, readback);
    $display("Read LOOPBACKSPLIT NOC ID: %16x", readback);
    `ASSERT_ERROR(readback == noc_block_delay.NOC_ID, "Incorrect NOC ID");
    `TEST_CASE_DONE(1);

    /********************************************************
    ** Test 3 -- Connect RFNoC blocks
    ********************************************************/
    `TEST_CASE_START("Connect RFNoC blocks");
    `RFNOC_CONNECT(noc_block_tb,noc_block_delay,SC16,SPP);
    `RFNOC_CONNECT(noc_block_delay,noc_block_tb,SC16,SPP);
    `TEST_CASE_DONE(1);

    /********************************************************
    ** Test 4 -- Write / readback user registers
    ********************************************************/
    `TEST_CASE_START("Write / readback user registers");
    idelay = 32'd7;
    qdelay = 32'd0;
    tb_streamer.write_user_reg(sid_noc_block_delay, noc_block_delay.SR_DELAY_I, idelay);
    tb_streamer.write_user_reg(sid_noc_block_delay, noc_block_delay.SR_PKT_SIZE, SPP*4);
    tb_streamer.write_user_reg(sid_noc_block_delay, noc_block_delay.SR_ENABLE_DIFF, 32'd1);
    tb_streamer.read_user_reg(sid_noc_block_delay, 0, readback);
    $sformat(s, "User register 0 incorrect readback! Expected: %0d, Actual %0d", readback[31:0], idelay);
    `ASSERT_ERROR(readback[31:0] == idelay, s);
    tb_streamer.write_user_reg(sid_noc_block_delay, noc_block_delay.SR_DELAY_Q, qdelay);
    `TEST_CASE_DONE(1);

    /********************************************************
    ** Test 5 -- Test sequence
    ********************************************************/
    `TEST_CASE_START("Test sequence");
    fork
      begin
        cvita_payload_t send_payload;
        for (int i = 0; i < SPP/2; i++) begin
          send_payload.push_back({16'(i*2), 16'(i*2), 16'(i*2+1), 16'(i*2+1)});
        end
        tb_streamer.send(send_payload);
      end
      begin
        cvita_payload_t recv_payload;
        cvita_metadata_t md;
        logic [63:0] expected_value;
        integer expected_i0, expected_q0;
        $display("Receiving on DATA port");
        tb_streamer.recv(recv_payload,md, 0);
        for (int i = 0; i < SPP/2; i++) begin
          expected_i0 = i*2-idelay;
          expected_q0 = i*2-qdelay;
          expected_value = {expected_i0 < 0 ? 16'b0 : 16'(expected_i0),
                            expected_q0 < 0 ? 16'b0 : 16'(expected_q0),
                            (expected_i0+1) < 0 ? 16'b0 : 16'(expected_i0+1),
                            (expected_q0+1) < 0 ? 16'b0 : 16'(expected_q0+1)};
          $sformat(s, "Incorrect value received! Expected: %0x, Received: %0x", expected_value, recv_payload[i]);
          `ASSERT_ERROR(recv_payload[i] == expected_value, s);
        end
      end
    join
    `TEST_CASE_DONE(1);

    /********************************************************
    ** Test 5 -- Un-delay everything, test advance.
    **           Note that, because of the way tlast
    **           was handled, we got the whole packet
    **           last time (i.e., SPP>600). So this time
    **           there's nothing left in the pipeline.
    ********************************************************/
    `TEST_CASE_START("Test sequence -- undelay");
    tb_streamer.write_user_reg(sid_noc_block_delay, noc_block_delay.SR_DELAY_I, 32'd0);
    tb_streamer.write_user_reg(sid_noc_block_delay, noc_block_delay.SR_DELAY_Q, 32'd0);
    fork
      begin
        cvita_payload_t send_payload;
        for (int i = 0; i < SPP/2; i++) begin
          send_payload.push_back({16'(i*2), 16'(i*2), 16'(i*2+1), 16'(i*2+1)});
        end
        tb_streamer.send(send_payload);
        tb_streamer.send(send_payload);
      end
      begin
        cvita_payload_t recv_payload;
        cvita_metadata_t md;
        logic [63:0] expected_value;
        integer expected_i0, expected_q0;
        $display("Receiving on DATA port");
        tb_streamer.recv(recv_payload,md, 0);
        for (int i = 0; i < SPP/2; i++) begin
          expected_i0 = i*2+idelay;
          expected_q0 = i*2+qdelay;
          expected_value = {16'(expected_i0),
                            16'(expected_q0),
                            16'(expected_i0+1),
                            16'(expected_q0+1)};
          $sformat(s, "Incorrect value received! Expected: %0x, Received: %0x", expected_value, recv_payload[i]);
          `ASSERT_ERROR(recv_payload[i] == expected_value, s);
        end
      end
    join
    `TEST_CASE_DONE(1);
    `TEST_CASE_START("Test sequence -- another one for good luck");
    fork
      begin
        cvita_payload_t send_payload;
        for (int i = 0; i < SPP/2; i++) begin
          send_payload.push_back({16'(i*2), 16'(i*2), 16'(i*2+1), 16'(i*2+1)});
        end
        tb_streamer.send(send_payload);
      end
      begin
        cvita_payload_t recv_payload;
        cvita_metadata_t md;
        logic [63:0] expected_value;
        integer expected_i0, expected_q0;
        $display("Receiving on DATA port");
        tb_streamer.recv(recv_payload,md, 0);
        for (int i = 0; i < SPP/2; i++) begin
          expected_i0 = i*2+idelay;
          expected_q0 = i*2+qdelay;
          expected_value = {16'(expected_i0),
                            16'(expected_q0),
                            16'(expected_i0+1),
                            16'(expected_q0+1)};
          $sformat(s, "Incorrect value received! Expected: %0x, Received: %0x", expected_value, recv_payload[i]);
          `ASSERT_ERROR(recv_payload[i] == expected_value, s);
        end
      end
    join
    `TEST_CASE_DONE(1);
    `TEST_BENCH_DONE;

  end
endmodule
