//
// Copyright 2017 Nick Foster
//

module delay_better
  #(parameter MAX_LEN_LOG2=10,
    parameter WIDTH=16)
   (input clk, input reset, input clear,
    input [MAX_LEN_LOG2-1:0] len,
    input [MAX_LEN_LOG2-1:0] max_spp,
    input [WIDTH-1:0] i_tdata, input i_tlast, input i_tvalid, output i_tready,
    output [WIDTH-1:0] o_tdata, output o_tlast, output o_tvalid, input o_tready);

   reg [MAX_LEN_LOG2-1:0] delay_count;
   reg [WIDTH-1:0] last_sample;
   reg [MAX_LEN_LOG2-1:0] spp_count;

   localparam STATE_WAITING_FOR_FIRST_INPUT = 0;
   localparam STATE_ADVANCE = 1;
   localparam STATE_DELAY = 2;
   localparam STATE_RUNNING = 3;
   reg [1:0] state;

   //how to handle tlast? you could conceivably produce a massive fuck-all packet if your delay is large enough.
   //instead, let's make it a settings register so that this block also resizes packets coming in.
   //you could also just have a "maximum SPP" input so that tlast is preserved except during delay events.
   //TODO use spp_count
   always @(posedge clk) begin
     if(reset|clear) begin
       delay_count <= 0;
       state <= STATE_WAITING_FOR_FIRST_INPUT;
       last_sample <= 0;
       spp_count <= 0;
     end
     else
       case(state)
         STATE_WAITING_FOR_FIRST_INPUT: begin
           if(i_tvalid & o_tready) begin
             last_sample <= i_tdata;
             if(len>0) begin
               state <= STATE_DELAY;
	       delay_count <= 1;
             end
             else
               state <= STATE_RUNNING;
           end
         end
         STATE_ADVANCE: begin //advance means we're consuming, but not producing.
           if(delay_count == len)
             state <= STATE_RUNNING;
           else
             if(i_tvalid & o_tready) begin
               delay_count <= delay_count - 1;
/*               last_sample <= i_tdata; */
           end
         end
         STATE_DELAY: begin // delay means we're producing, but not consuming.
           if(delay_count == len)
             state <= STATE_RUNNING;
           else
             if(o_tvalid & o_tready)
               delay_count <= delay_count + 1;
         end
         STATE_RUNNING: begin
           if(delay_count > len)
             state <= STATE_ADVANCE;
           else if(delay_count < len)
             state <= STATE_DELAY;
           if(i_tvalid & o_tready)
             last_sample <= i_tdata;
         end
       endcase
   end

   //i_tready: we're ready to take input:
   //  IF o_tready AND STATE_RUNNING
   //  OR STATE_ADVANCE
   //  OR STATE_WAITING_FOR_FIRST_INPUT

   //o_tvalid: our data is valid on the output:
   //  IF i_tvalid AND STATE_RUNNING
   //  OR STATE_DELAY

   assign o_tdata = (state == STATE_DELAY) ? last_sample : i_tdata;
   assign o_tlast = (state == STATE_DELAY) ? 1'b0 : i_tlast; //FIXME
   assign o_tvalid = (i_tvalid & (state == STATE_RUNNING))
                   | (state == STATE_DELAY)
                   | ((state == STATE_ADVANCE) & delay_count == len)
                   | (i_tvalid & o_tready & (state == STATE_WAITING_FOR_FIRST_INPUT));
   assign i_tready = (o_tready & (state == STATE_RUNNING | state == STATE_WAITING_FOR_FIRST_INPUT))
                   | (state == STATE_ADVANCE);

endmodule // delay_better
