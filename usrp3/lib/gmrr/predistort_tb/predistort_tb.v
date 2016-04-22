//
// Copyright 2012-2013 Ettus Research LLC
//

`timescale 1ns / 1ps

module predistort_tb();
//   xlnx_glbl glbl (.GSR(),.GTS());

   localparam STR_SINK_FIFOSIZE = 9;

   reg clk, reset;
   always
     #100 clk = ~clk;

   initial clk = 0;
   initial reset = 1;
   initial #1000 reset = 0;

   initial $dumpfile("predistort_tb.vcd");
   initial $dumpvars(0,predistort_tb);

   initial #1000000 $finish;

   wire [15:0] i_tdata;
   wire [15:0] o_tdata;
   wire        i_tvalid, i_tready, i_tlast, o_tvalid, o_tlast, o_tready;

   wire [15:0] taps_tdata;
   wire        taps_tvalid, taps_tlast, taps_tready;

   reg         c_tvalid;

   counter #(.WIDTH(16)) ca (
      .clk(clk), .reset(reset), .clear(0),
      .max(16'h7FFF),
      .i_tlast(0), .i_tvalid(c_tvalid), .i_tready(),
      .o_tdata(i_tdata[15:4]), .o_tlast(i_tlast), .o_tvalid(i_tvalid), .o_tready(i_tready)
   );
   assign i_tdata[3:0] = 4'b0;

   //TODO gotta load taps into that thing
   predistort #(.WIDTH(16), .DEPTH(7), .DROPBITS(10)) predist (
      .clk(clk), .reset(reset), .clear(0),
      .i_tdata(i_tdata), .i_tlast(i_tlast), .i_tvalid(i_tvalid), .i_tready(i_tready),
      .o_tdata(o_tdata), .o_tlast(), .o_tvalid(o_tvalid), .o_tready(o_tready),
      .taps_tdata(taps_tdata), .taps_tlast(taps_tlast), .taps_tvalid(taps_tvalid), .taps_tready(taps_tready)
   );

   initial
     begin
   @(negedge reset);
   repeat (100)
     @(posedge clk);
   c_tvalid <= 1;
     end

   assign o_tready = 1;

endmodule // predistort_tb
