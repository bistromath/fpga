//
// Copyright 2017 Nick Foster
//

//OK. A lot of your problem seems to be that you're suddenly injecting or
//dropping a fuckload of samples. What if, instead, we kept a counter and
//just introduced or dropped ONE SAMPLE PER PACKET until we caught up?
//This is a MUCH SAFER way of doing what you're trying to do. It also
//neatly solves the tlast problem of potentially producing huge packets.
//`default_nettype none
module delay_better
  #(parameter MAX_LEN_LOG2=10,
    parameter WIDTH=16)
   (input clk, input reset, input clear,
    input [MAX_LEN_LOG2-1:0] len, //delay amount
    input [WIDTH-1:0] i_tdata, input i_tlast, input i_tvalid, output i_tready,
    output [WIDTH-1:0] o_tdata, output o_tlast, output o_tvalid, input o_tready);

   reg [MAX_LEN_LOG2-1:0] delay_count;
   reg [WIDTH-1:0] last_sample;

   localparam STATE_WAITING_FOR_FIRST_INPUT = 0;
   localparam STATE_ADVANCE_PRIMED = 1;
   localparam STATE_ADVANCE_TRIGGER = 2;
   localparam STATE_DELAY_PRIMED = 3;
   localparam STATE_DELAY_TRIGGER = 4;
   localparam STATE_RUNNING = 5;
   reg [2:0] state;

   //ok the state diagram works like this
   //when you're RUNNING: you're just clocking samples
   //in and out.
   //when you're ADVANCING: you drop the FIRST SAMPLE OF
   //EACH PACKET until you catch up
   //when you're DELAYING: you look for incoming TLAST
   //and, when you see it, go into a state where you
   //mask it, then on the next clock cycle assert it
   //along with TVALID.
   
   wire input_valid = i_tvalid & o_tready;
   wire eop = input_valid & i_tlast;

   always @(posedge clk) begin
     if(reset|clear) begin
       delay_count <= 0;
       state <= STATE_RUNNING;
       last_sample <= 0;
     end
     else
       case(state)
         STATE_ADVANCE_PRIMED: begin
           if(eop) begin
             state <= STATE_ADVANCE_TRIGGER; //tvalid will go low until the start of the next packet.
             last_sample <= i_tdata;
           end
         end
	 STATE_ADVANCE_TRIGGER: begin //just skip one at the beginning
	   if(input_valid) begin
	     delay_count <= delay_count - 1;
	     state <= STATE_RUNNING;
	   end
	 end
         STATE_DELAY_PRIMED: begin //produce but don't consume. delay tlast.
           if(eop) begin
             state <= STATE_DELAY_TRIGGER;
             last_sample <= i_tdata;
           end
         end
	 STATE_DELAY_TRIGGER: begin
           delay_count <= delay_count + 1;
           state <= STATE_RUNNING;
         end
         STATE_RUNNING: begin
           if(delay_count > len)
             state <= STATE_ADVANCE_PRIMED;
           else if(delay_count < len)
             state <= STATE_DELAY_PRIMED;
         end
       endcase
   end

   //ok the hard combinatorial part.
   //i_tready: we're ready to take input:
   //  IF o_tready AND state != STATE_DELAY_TRIGGER
   //o_tvalid: our data is valid on the output:
   //  IF i_tvalid AND state != STATE_ADVANCE_TRIGGER
   //o_tlast: it's the last sample in a packet:
   //  IF i_tlast AND state != STATE_DELAY_PRIMED
   //  OR state == STATE_DELAY_TRIGGER


   assign i_tready = o_tready & (state != STATE_DELAY_TRIGGER);
   assign o_tvalid = (i_tvalid & (state != STATE_ADVANCE_TRIGGER))
                   | (state == STATE_DELAY_TRIGGER);
   assign o_tlast  = (i_tlast & (state != STATE_DELAY_PRIMED))
                   | (state == STATE_DELAY_TRIGGER);
   assign o_tdata = (state == STATE_DELAY_TRIGGER) ? last_sample : i_tdata;

endmodule // delay_better
//`default_nettype wire
