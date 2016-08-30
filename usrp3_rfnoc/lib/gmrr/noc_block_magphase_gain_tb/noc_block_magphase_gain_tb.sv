//
// Copyright 2014 Ettus Research LLC
//
`timescale 1ns/1ps
`define NS_PER_TICK 1
`define NUM_TEST_CASES 6

`define SIM_TIMEOUT_US 200

`include "sim_exec_report.vh"
`include "sim_clks_rsts.vh"
`include "sim_rfnoc_lib.svh"

module noc_block_magphase_gain_tb();
  `TEST_BENCH_INIT("noc_block_magphase_gain_tb",`NUM_TEST_CASES,`NS_PER_TICK);
  localparam BUS_CLK_PERIOD = $ceil(1e9/166.67e6);
  localparam CE_CLK_PERIOD  = $ceil(1e9/200e6);
  localparam NUM_CE         = 1;  // Number of Computation Engines / User RFNoC blocks to simulate
  localparam NUM_STREAMS    = 4;  // Number of test bench streams
  `RFNOC_SIM_INIT(NUM_CE, NUM_STREAMS, BUS_CLK_PERIOD, CE_CLK_PERIOD);
  `RFNOC_ADD_BLOCK(noc_block_magphase_gain, 0);

  localparam SPP         = 256; // Samples per packet
  localparam NUM_PASSES  = 2;

//  localparam VECTOR_SIZE = SPP;
//  localparam ALPHA       = int'($floor(1.0*(2**31-1)));
//  localparam BETA        = int'($floor(1.0*(2**31-1)));

  /********************************************************
  ** Verification
  ********************************************************/
  initial begin : tb_main
    shortint send_value[0:SPP];
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
    tb_streamer.read_reg(sid_noc_block_magphase_gain, RB_NOC_ID, readback);
    $display("Read mag/phase NOC ID: %16x", readback);
    `ASSERT_ERROR(readback == noc_block_magphase_gain.NOC_ID, "Incorrect NOC ID");
    `TEST_CASE_DONE(1);

    /********************************************************
    ** Test 3 -- Connect RFNoC blocks
    ********************************************************/
    `TEST_CASE_START("Connect RFNoC blocks");
    `RFNOC_CONNECT_BLOCK_PORT(noc_block_tb,0,noc_block_magphase_gain,0,SC16,SPP);
    `RFNOC_CONNECT_BLOCK_PORT(noc_block_magphase_gain,0,noc_block_tb,0,SC16,SPP);
    `TEST_CASE_DONE(1);

    /********************************************************
    ** Test 4 -- Setup predistorter
    ********************************************************/
    `TEST_CASE_START("Setup Mag/Phase block");
    //TODO set magnitude and phase gains here
    tb_streamer.write_reg(sid_noc_block_magphase_gain, noc_block_magphase_gain.SR_MAG_GAIN, 256);
    tb_streamer.write_reg(sid_noc_block_magphase_gain, noc_block_magphase_gain.SR_PHASE_GAIN, 256);
    `TEST_CASE_DONE(1);

    /********************************************************
    ** Test 5 -- Test vectors
    ********************************************************/
    for (int l = 0; l < SPP; l++) begin
       //TODO this should be a sine wave not a linear input
       send_value[l] = 16'(128*2*l);
    end
    `TEST_CASE_START("Send test vectors");
    begin
      cvita_payload_t send_payload;
      cvita_metadata_t tx_md;
      for (int i = 0; i < SPP/2; i++) begin
        send_payload.push_back({send_value[i],16'b0,send_value[i+1], 16'b0});
      end
      tx_md.eob = 1'b1;
      tb_streamer.send(send_payload, tx_md);
    end
    `TEST_CASE_DONE(1);
    `TEST_CASE_START("Receive output vectors");
    begin
      cvita_payload_t recv_payload;
      cvita_metadata_t rx_md;
      int unsigned expected_value, index, lut, lut_next, remainder;
      shortint unsigned recv_value[0:SPP];
      string s;
      $display("Receiving from stream %0d...", 0);
      tb_streamer.recv(recv_payload, rx_md, 0);
      $display("done receiving from stream %0d", 0);
      `ASSERT_ERROR(rx_md.eob == 1'b1, "EOB bit not set!");
      for(int k = 0; k < SPP/2; k++) begin
          recv_value[k] = recv_payload[k][63:48];
          recv_value[k+1] = recv_payload[k][31:16];
      end
//            expected_value = lut + remainder*(lut_next-lut)/512;
//            $sformat(s, "Incorrect value received on predistorter output %0d! Expected: %0d, Received: %0d (index %0d, remainder %0d, lut %0d, lut_next %0d, send_value %0d)", g, expected_value, recv_value[m], index, remainder, lut, lut_next, send_value[m]);
//            `ASSERT_ERROR(recv_value[m] == expected_value, s);
    end
    `TEST_CASE_DONE(1);
    `TEST_BENCH_DONE;

  end
endmodule
