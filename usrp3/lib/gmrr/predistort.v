//a predistorter is basically just a ram_to_fifo block.
//taps are loaded in serially to each predistorter,
//and the i_t* input is the (8-bit truncated) input sample data.
//The o_t* output is the lookup table output.
//The lookup table output has to be linearly
//interpolated using the truncated bits of the input
//data. to do the interpolation, you need t[i] and t[i+1].
//either you have to rig up a thing that registers t[i] and
//grabs t[i+1] so you can interpolate, or you can double
//the size of your lookup table...
//
//or, you can do it right. ram_2port just instantiates an assload
//of registers. you really just want to do a modified ram_2port that
//has an output data width of twice the actual dwidth and gives you
//t[i+1] as well as t[i]. just make it have two outputs for each port.
//done.
//
//you really don't even need a 2port RAM, but hey, optimization will
//remove the ports you don't use.
//
//now you have t[i] and t[i+1], and you need to interpolate.
//
//to do this, you first calculate d_t = t[i+1] - t[i].
//
//then get the remainder (truncated bits of the input). NOT ROUNDED.
//
//then just do out = t[i] + d_t * r
//
//TODO scaling for the truncated bits? need to handle scaling and
//roundoff.
//
//or you could just do it right and register things. let's see, how does
//this work. you have two AXI streams being output from ram_2port_next.
//like this:
//
//
//
//  i  --------  [ ram 2port ]  --t[i]-fxf----------------------- [     ]
//               [           ]          f                         [ add ]
//               [           ]          \-- [ sub ] -- [      ] - [     ]
//               [    next   ]  --t[i+1]-f- [     ]    [ mult ]
//                                                     [      ]
//  r ------------------------------------------------ [      ]
//
//  it seems like the short story is, if you make everything an AXI
//  stream, you don't have to worry about alignment. so let's do that.
//
//  WIDTH == input width, output width
//  DEPTH == entries in the table
//
//  i_t* == address data input (i)
//  o_t* == output data (t[i])
//  taps_t* == taps stream
//
//  you should mask taps_tvalid in the caller so that taps only get loaded
//  into the desired predistorter.
//
//  problem. when you have t[i] and t[i+1], those are really separate
//  streams. you need a split stream FIFO to decouple them.
//
//  this is analogous to splitting a complex stream into I/Q. split_complex
//  only works on identical downstream paths.
//
//  we can make that guarantee for the SUB inputs, but not for the other
//  fork. maybe we can use a split_complex style duplication for that path, and
//  a split_stream_fifo on t[i]... but that implies you can no longer do the
//  split complex thing because the t[i] path will have a FIFO while the t[i+1]
//  path will not. solution: put a FIFO on the t[i+1] line. problem fuckin'
//  solved.

module predistort
  #(parameter WIDTH=16, parameter DEPTH=7)
   (input clk, input reset, input clear,
    input [WIDTH-1:0] i_tdata, input i_tlast, input i_tvalid, output i_tready,
    output [WIDTH-1:0] o_tdata, output o_tlast, output o_tvalid, input o_tready,
    input [WIDTH-1:0] taps_tdata, input taps_tlast, input taps_tvalid, output taps_tready)


  wire [WIDTH-1:0] index_tdata;
  wire index_tlast, index_tvalid, index_tready;

  wire [WIDTH-1:0] remainder_tdata;
  wire remainder_tlast, remainder_tvalid, remainder_tready;

  wire [WIDTH-1:0] lut_tdata;
  wire lut_tlast, lut_tvalid, lut_tready;

  wire [WIDTH-1:0] lut_next_tdata;
  wire lut_next_tlast, lut_next_tvalid, lut_next_tready;

  wire [WIDTH-1:0] lut_next_fifo_tdata;
  wire lut_next_fifo_tlast, lut_next_fifo_tvalid, lut_next_fifo_tready;

  wire [WIDTH-1:0] lut_next_fifo_tdata;
  wire lut_next_fifo_tlast, lut_next_fifo_tvalid, lut_next_fifo_tready;

  wire [WIDTH-1:0] lut_stream0_tdata;
  wire lut_stream0_tlast, lut_stream0_tvalid, lut_stream0_tready;

  wire [WIDTH-1:0] lut_stream1_tdata;
  wire lut_stream1_tlast, lut_stream1_tvalid, lut_stream1_tready;

  wire [WIDTH-1:0] dt_tdata;
  wire dt_tlast, dt_tvalid, dt_tready;

  wire [WIDTH-1:0] interp_tdata;
  wire interp_tlast, interp_tvalid, interp_tready;

  assign taps_tready = 1'b1;
  reg [DEPTH-1:0] write_addr;
  always @(posedge clk)
     if(reset | clear)
        write_addr <= 0;
     else
        if(taps_tvalid & taps_tready)
           if(taps_tlast)
              write_addr <= 0;
           else
              write_addr <= write_addr + 1;

  //split the input stream into two separate AXI streams -- one has the LUT
  //index, the other has the remainder.
  split_stream_fifo #(.WIDTH(WIDTH), .ACTIVE_MASK(4'b0011)) input_splitter (
    .clk(clk), .reset(reset), .clear(clear),
    .i_tdata(i_tdata), .i_tlast(i_tlast), .i_tvalid(i_tvalid), .i_tready(i_tready),
    .o0_tdata(index_tdata), .o0_tlast(index_tlast), .o0_tvalid(index_tvalid), .o0_tready(index_tready),
    .o1_tdata(remainder_tdata), .o1_tlast(remainder_tlast), .o1_tvalid(remainder_tvalid), .o1_tready(remainder_tready)
 );

  assign index_tdata_clip = index_tdata[WIDTH-1:WIDTH-DEPTH];
  assign remainder_tdata_clip = remainder_tdata[WIDTH-DEPTH-1:0];

  //here's your LUT
  ram_2port_next #(.DWIDTH(WIDTH), .AWIDTH(DEPTH)) lut (
     .clka(clk), .ena(1'b1), .wea(taps_tvalid), .addra(write_addr), .dia(taps_tdata), .doa(),
     .clkb(clk), .enb(index_tready & index_tvalid), .web(1'b0), .addrb(index_tdata_clip), .dib({WIDTH{1'b1}}), .dob(lut_tdata), .dob_next(lut_next_tdata));

  //this cribs ram_to_fifo.v
  assign index_tready = ~lut_tvalid | lut_tready;
  always @(posedge clk)
     if(reset | clear)
     begin
        lut_tready <= 1'b0;
        lut_tlast <= 1'b0;
     end
     else
     begin
        lut_tvalid <= (index_tready & index_tvalid) | (lut_tvalid & ~lut_tready);
        if(index_tready & index_tvalid)
           lut_tlast <= index_tlast;
     end

  //TODO the FIFO stuff here is broken. yes, it's synchronous, but you
  //don't have separate AXI streams for each right now, so you can't feed two
  //FIFOs... i mean you probably can because it's all synchronous, and just
  //ignore the other tready...? you can't ignore tready because if things get
  //out of sync downstream one could fill up before the other.
  //IOW you need to add a bespoke split_stream in here to do the tready/tvalid
  //massaging necessary for this to work.

   axi_fifo_short #(.WIDTH(WIDTH+1)) lut_fifo (
      .clk(clk), .reset(reset), .clear(clear),
      .i_tdata({lut_tlast, lut_tdata}), .i_tvalid(lut_tvalid), .i_tready(lut_tready),
      .o_tdata({lut_fifo_tlast, lut_fifo_tdata}), .o_tvalid(lut_fifo_tvalid), .o_tready(lut_fifo_tready)
   );

   axi_fifo_short #(.WIDTH(WIDTH+1)) lut_next_fifo (
      .clk(clk), .reset(reset), .clear(clear),
      .i_tdata({lut_tlast, lut_next_tdata}), .i_tvalid(lut_tvalid), .i_tready(lut_next_tready),
      .o_tdata({lut_next_fifo_tlast, lut_next_fifo_tdata}), .o_tvalid(lut_next_fifo_tvalid), .o_tready(lut_next_fifo_tready)
   );

   //now we're buffered and can split the stream with a split_stream_fifo for
   //use with the sub block and the final mult block (see diagram above)
   split_stream_fifo #(.WIDTH(WIDTH), .ACTIVE_MASK(4'b0011)) lut_splitter (
      .clk(clk), .reset(reset), .clear(clear),
      .i_tdata(lut_fifo_tdata), .i_tlast(lut_fifo_tlast), .i_tvalid(lut_fifo_tvalid), .i_tready(lut_fifo_tready),
      .o0_tdata(lut_stream0_tdata), .o0_tlast(lut_stream0_tlast), .o0_tvalid(lut_stream0_tvalid), .o0_tready(lut_stream0_tready),
      .o1_tdata(lut_stream1_tdata), .o1_tlast(lut_stream1_tlast), .o1_tvalid(lut_stream1_tvalid), .o1_tready(lut_stream1_tready)
   );

   //now we're free to use lut and lut_next with our downstream blocks without
   //fear of shit getting blocked up. no more constipation!

   addsub #(.WIDTH(WIDTH)) sub (
     .clk(clk), .reset(reset),
     .i0_tdata(lut_next_fifo_tdata), .i0_tlast(lut_next_fifo_tlast), .i0_tvalid(lut_next_fifo_tvalid), .i0_tready(lut_next_fifo_tready),
     .i1_tdata(lut_stream0_tdata), .i1_tlast(lut_stream0_tlast), .i1_tvalid(lut_stream0_tvalid), .i1_tready(lut_stream0_tready),
     .diff_tdata(dt_tdata), .diff_tlast(dt_tlast), .diff_tvalid(dt_tvalid), .diff_tready(dt_tready)
  );

  //then there's a multiplier to mult the remainder by the difference
  //TODO figure out the bitwidths and rounding
  mult #(.WIDTH_A(WIDTH), .WIDTH_B(WIDTH), .WIDTH_P(WIDTH+10), .DROP_TOP_P(10)) mult_inst (
     .clk(clk), .reset(reset),
     .a_tdata(remainder_tdata_clip),
     .a_tlast(remainder_tlast),
     .a_tvalid(remainder_tvalid),
     .a_tready(remainder_tready),
     .b_tdata(dt_tdata),
     .b_tlast(dt_tlast),
     .b_tvalid(dt_tvalid),
     .b_tready(dt_tready),
     .p_tdata(interp_tdata),
     .p_tlast(interp_tlast),
     .p_tvalid(interp_tvalid),
     .p_tready(interp_tready)
  );

  //and finally an adder to sum the correction with the stream1.
  addsub #(.WIDTH(WIDTH)) add (
    .clk(clk), .reset(reset),
    .i0_tdata(lut_stream1_tdata), .i0_tlast(lut_stream1_tdata), .i0_tvalid(lut_stream1_tvalid), .i0_tready(lut_stream1_tready),
    .i1_tdata(interp_tdata), .i1_tlast(interp_tlast), .i1_tvalid(interp_tvalid), .i1_tready(interp_tready),
    .sum_tdata(o_tdata), .sum_tlast(o_tlast), .sum_tvalid(o_tvalid), .sum_tready(o_tready)
 );
endmodule
