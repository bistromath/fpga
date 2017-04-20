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
  localparam NUM_CE         = 2;  // Number of Computation Engines / User RFNoC blocks to simulate
  localparam NUM_STREAMS    = 2;  // Number of test bench streams
  `RFNOC_SIM_INIT(NUM_CE, NUM_STREAMS, BUS_CLK_PERIOD, CE_CLK_PERIOD);
  reg [15:0] taps[0:127];
  initial 
    $readmemh("/home/nick/clabs/clabs_15/uhd/fpga-src/usrp3/lib/gmrr/predistort_tb/sine.list", taps);

  `RFNOC_ADD_BLOCK(noc_block_integrated_predistorter, 0);

/*  `RFNOC_ADD_BLOCK_CUSTOM(noc_block_magphase_gain_mag, 0);
  `RFNOC_ADD_BLOCK_CUSTOM(noc_block_magphase_gain_norm, 1);
  noc_block_integrated_predistorter noc_block_magphase_gain (
	.ce_clk(ce_clk), .ce_rst(ce_rst),
	.bus_clk(bus_clk), .bus_rst(bus_rst),
	.i_tdata({noc_block_magphase_gain_norm_i_tdata, noc_block_magphase_gain_mag_i_tdata}),
	.i_tlast({noc_block_magphase_gain_norm_i_tlast, noc_block_magphase_gain_mag_i_tlast}),
	.i_tvalid({noc_block_magphase_gain_norm_i_tvalid, noc_block_magphase_gain_mag_i_tvalid}),
	.i_tready({noc_block_magphase_gain_norm_i_tready, noc_block_magphase_gain_mag_i_tready}),
	.o_tdata({noc_block_magphase_gain_norm_o_tdata, noc_block_magphase_gain_mag_o_tdata}),
	.o_tlast({noc_block_magphase_gain_norm_o_tlast, noc_block_magphase_gain_mag_o_tlast}),
	.o_tvalid({noc_block_magphase_gain_norm_o_tvalid, noc_block_magphase_gain_mag_o_tvalid}),
	.o_tready({noc_block_magphase_gain_norm_o_tready, noc_block_magphase_gain_mag_o_tready})
  );*/

  localparam SPP         = 256; // Samples per packet
  localparam NUM_PASSES  = 2;

//  localparam VECTOR_SIZE = SPP;
//  localparam ALPHA       = int'($floor(1.0*(2**31-1)));
//  localparam BETA        = int'($floor(1.0*(2**31-1)));

  int sin_1_32nd[32] = {     0,   6596,  12922,  18719,  23749,  27808,  30727,  32389,
                         32725,  31721,  29418,  25911,  21344,  15902,   9809,   3315,
                         -3315,  -9809, -15902, -21344, -25911, -29418, -31721, -32725, 
                        -32389, -30727, -27808, -23749, -18719, -12922,  -6596,      0
                        };

  int cos_1_32nd[32] = { 32767,  32096,  30111,  26894,  22575,  17333,  11380,   4962,
                         -1660,  -8213, -14430, -20057, -24862, -28650, -31264, -32599,
                        -32599, -31264, -28650, -24862, -20057, -14430,  -8213,  -1660,
                          4962,  11380,  17333,  22575,  26894,  30111,  32096,  32767
                       };

  /********************************************************
  ** Verification
  ********************************************************/
  initial begin : tb_main
    shortint i_value[0:SPP], q_value[0:SPP];
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
    tb_streamer.read_reg(sid_noc_block_integrated_predistorter, RB_NOC_ID, readback);
    $display("Read mag/phase NOC ID: %16x", readback);
    `ASSERT_ERROR(readback == noc_block_integrated_predistorter.NOC_ID, "Incorrect NOC ID");
    `TEST_CASE_DONE(1);

    /********************************************************
    ** Test 3 -- Connect RFNoC blocks
    ********************************************************/
    `TEST_CASE_START("Connect RFNoC blocks");
    `RFNOC_CONNECT_BLOCK_PORT(noc_block_tb,0,noc_block_integrated_predistorter,0,SC16,SPP);
    `RFNOC_CONNECT_BLOCK_PORT(noc_block_integrated_predistorter,0,noc_block_tb,0,SC16,SPP);
//    `RFNOC_CONNECT_BLOCK_PORT(noc_block_magphase_gain_norm,0,noc_block_tb,1,SC16,SPP);
    `TEST_CASE_DONE(1);

    /********************************************************
    ** Test 4 -- Setup predistorter
    ********************************************************/
    `TEST_CASE_START("Setup Mag/Phase block");
    //TODO set magnitude and phase gains here
    tb_streamer.write_reg(sid_noc_block_integrated_predistorter, noc_block_integrated_predistorter.SR_MAG_GAIN, 256);
    tb_streamer.write_reg(sid_noc_block_integrated_predistorter, noc_block_integrated_predistorter.SR_SQUELCH_LEVEL, 8000);
    /* load predistorter tables */
    begin
      logic [31:0] send_word;
      for (int o = 0; o < 4; o++) begin
        $display("Writing taps for predistorter %0d", o);
        for (int n = 0; n < 127; n++) begin
            send_word[31:16] = 0;
            send_word[15:0]  = taps[n];
            tb_streamer.write_reg(sid_noc_block_integrated_predistorter, noc_block_integrated_predistorter.SR_AXI_CONFIG+2*o, send_word);
            if (n==127)
                tb_streamer.write_reg(sid_noc_block_integrated_predistorter, noc_block_integrated_predistorter.SR_AXI_CONFIG+2*o+1, 32'b1);
        end
      end
    end
    `TEST_CASE_DONE(1);

    /********************************************************
    ** Test 5 -- Test vectors
    ********************************************************/
    for (int l = 0; l < SPP; l+=1) begin
       i_value[l] = 16'(cos_1_32nd[l%32]);
       q_value[l] = 16'(0);//sin_1_32nd[l%32]);
    end
    `TEST_CASE_START("Send test vectors");
    begin
      cvita_payload_t send_payload;
      cvita_metadata_t tx_md;
      for (int i = 0; i < SPP/2; i++) begin
        send_payload.push_back({i_value[i],q_value[i],i_value[i+1], q_value[i+1]});
      end
      tx_md.eob = 1'b1;
      tb_streamer.send(send_payload, tx_md);
    end
    `TEST_CASE_DONE(1);
    `TEST_CASE_START("Receive output vectors");
    begin
      cvita_payload_t recv_payload[0:1];
      cvita_metadata_t rx_md[0:1];
      shortint unsigned recv_mags[0:SPP];
      shortint unsigned recv_norm[0:SPP*2];
      string s;
      $display("Receiving from stream %0d...", 0);
      tb_streamer.recv(recv_payload[0], rx_md[0], 0);
      $display("done receiving.");
      $display("Receiving from stream %0d...", 1);
      tb_streamer.recv(recv_payload[1], rx_md[1], 1);
      $display("done receiving.");
      `ASSERT_ERROR(rx_md[0].eob == 1'b1, "EOB bit not set on stream 0!");
      `ASSERT_ERROR(rx_md[1].eob == 1'b1, "EOB bit not set on stream 1!");
      for(int k = 0; k < SPP/2; k++) begin
          recv_mags[k] = recv_payload[0][k][63:48];
          recv_mags[k+1] = recv_payload[0][k][31:16];

          recv_norm[k] = recv_payload[1][k][63:48];
          recv_norm[k+1] = recv_payload[1][k][47:32];
          recv_norm[k+2] = recv_payload[1][k][31:16];
          recv_norm[k+3] = recv_payload[1][k][15:0];
      end
//            expected_value = lut + remainder*(lut_next-lut)/512;
//            $sformat(s, "Incorrect value received on predistorter output %0d! Expected: %0d, Received: %0d (index %0d, remainder %0d, lut %0d, lut_next %0d, send_value %0d)", g, expected_value, recv_value[m], index, remainder, lut, lut_next, send_value[m]);
//            `ASSERT_ERROR(recv_value[m] == expected_value, s);
    end
    `TEST_CASE_DONE(1);
    `TEST_BENCH_DONE;

  end
endmodule
