//
// Copyright 2016 Ettus Research
//

//! RFNoC specific digital down-conversion chain

module ddc #(
  parameter BASE = 0,
  parameter PRELOAD_HBS = 1 // Preload half band filter state with 0s
)(
  input clk, input reset, input clear,
  input set_stb, input [7:0] set_addr, input [31:0] set_data,
  input sample_in_stb,
  input sample_in_last,
  output sample_in_rdy,
  input [31:0] sample_in,
  output sample_out_stb,
  output reg sample_out_last,
  output [31:0] sample_out
);

  localparam  WIDTH = 24;
  localparam  cwidth = 25;
  localparam  zwidth = 24;

  wire [31:0] phase_inc;
  reg [31:0]  phase;

  wire [17:0] scale_factor;
  wire last_cordic, last_cic;
  reg last_cordic_clip;
  wire strobe_cordic;
  wire [cwidth-1:0] i_cordic, q_cordic;
  wire strobe_cordic_clip;
  wire [WIDTH-1:0] i_cordic_clip, q_cordic_clip;
  wire [WIDTH-1:0] i_cic, q_cic;
  wire [46:0] i_hb1, q_hb1;
  wire [46:0] i_hb2, q_hb2;
  wire [47:0] i_hb3, q_hb3;

  wire strobe_cic, strobe_hb1, strobe_hb2, strobe_hb3;

  reg [7:0] cic_decim_rate;
  wire [7:0] cic_decim_rate_int;
  wire rate_changed;

  wire [WIDTH-1:0] sample_in_i = {sample_in[31:16], 8'd0};
  wire [WIDTH-1:0] sample_in_q = {sample_in[15:0], 8'd0};

  reg sample_mux_stb;
  reg sample_mux_last;
  reg [WIDTH-1:0] sample_mux_i, sample_mux_q;
  wire realmode;
  wire swap_iq;

  reg [1:0] hb_rate;
  wire [1:0] hb_rate_int;
  wire [2:0] enable_hb = { hb_rate == 2'b11, hb_rate[1] == 1'b1, hb_rate != 2'b00 };

  wire reload_go, reload_we1, reload_we2, reload_we3, reload_ld1, reload_ld2, reload_ld3;
  wire [17:0] coef_din;

  setting_reg #(.my_addr(BASE+0)) sr_0 (
    .clk(clk),.rst(reset),.strobe(set_stb),.addr(set_addr),
    .in(set_data),.out(phase_inc),.changed());

  setting_reg #(.my_addr(BASE+1), .width(18)) sr_1 (
    .clk(clk),.rst(reset),.strobe(set_stb),.addr(set_addr),
    .in(set_data),.out(scale_factor),.changed());

  setting_reg #(.my_addr(BASE+2), .width(10), .at_reset(1 /* No decimation */)) sr_2 (
    .clk(clk),.rst(reset),.strobe(set_stb),.addr(set_addr),
    .in(set_data),.out({hb_rate_int, cic_decim_rate_int}),.changed(rate_changed));

  setting_reg #(.my_addr(BASE+3), .width(2)) sr_3 (
    .clk(clk),.rst(reset),.strobe(set_stb),.addr(set_addr),
    .in(set_data),.out({realmode,swap_iq}),.changed());

  setting_reg #(.my_addr(BASE+4), .width(24)) sr_4 (
    .clk(clk),.rst(reset),.strobe(set_stb),.addr(set_addr),
    .in(set_data),.out({reload_ld3,reload_we3,reload_ld2,reload_we2,reload_ld1,reload_we1,coef_din}),.changed(reload_go));

  // Prevent changing rate while processing samples as this
  // will corrupt the output
  reg active, rate_changed_hold, rate_changed_stb;
  always @(posedge clk) begin
    if (reset) begin
      active            <= 1'b0;
      rate_changed_hold <= 1'b0;
      rate_changed_stb  <= 1'b0;
      cic_decim_rate    <= 'd0;
      hb_rate           <= 'd0;
    end else begin
      if (clear) begin
        active <= 1'b0;
      end else if (sample_in_stb & sample_in_rdy) begin
        active <= 1'b1;
      end
      if (rate_changed & active) begin
        rate_changed_hold <= 1'b1;
      end
      if (~active & (rate_changed | rate_changed_hold)) begin
        rate_changed_hold <= 1'b0;
        rate_changed_stb  <= 1'b1;
        cic_decim_rate    <= cic_decim_rate_int;
        hb_rate           <= hb_rate_int;
      end else begin
        rate_changed_stb  <= 1'b0;
      end
    end
  end

  // MUX so we can do realmode signals on either input
  always @(posedge clk) begin
    if (reset | clear) begin
      sample_mux_i    <= 'd0;
      sample_mux_q    <= 'd0;
      sample_mux_stb  <= 1'b0;
      sample_mux_last <= 1'b0;
    end else begin
      sample_mux_stb  <= sample_in_stb;
      sample_mux_last <= sample_in_last;
      if (swap_iq) begin
        sample_mux_i <= sample_in_q;
        sample_mux_q <= realmode ? 'd0 : sample_in_i;
      end else begin
        sample_mux_i <= sample_in_i;
        sample_mux_q <= realmode ? 'd0 : sample_in_q;
      end
    end
  end

  // NCO
  always @(posedge clk) begin
    if (reset | clear) begin
      phase <= 0;
    end else if (sample_mux_stb) begin
      phase <= phase + phase_inc;
    end
  end

  //sign extension of cordic input
  wire [cwidth-1:0] to_cordic_i, to_cordic_q;
  sign_extend #(.bits_in(WIDTH), .bits_out(cwidth)) sign_extend_cordic_i (.in(sample_mux_i), .out(to_cordic_i));
  sign_extend #(.bits_in(WIDTH), .bits_out(cwidth)) sign_extend_cordic_q (.in(sample_mux_q), .out(to_cordic_q));

  // CORDIC  24-bit I/O
  cordic #(.bitwidth(cwidth)) cordic (
    .clk(clk), .reset(reset | clear), .enable(1'b1),
    .strobe_in(sample_mux_stb), .strobe_out(strobe_cordic),
    .last_in(sample_mux_last), .last_out(last_cordic),
    .xi(to_cordic_i),. yi(to_cordic_q), .zi(phase[31:32-zwidth]),
    .xo(i_cordic),.yo(q_cordic),.zo() );

  clip_reg #(.bits_in(cwidth), .bits_out(WIDTH)) clip_cordic_i (
    .clk(clk), .reset(reset | clear), .in(i_cordic), .strobe_in(strobe_cordic), .out(i_cordic_clip), .strobe_out(strobe_cordic_clip));
  clip_reg #(.bits_in(cwidth), .bits_out(WIDTH)) clip_cordic_q (
    .clk(clk), .reset(reset | clear), .in(q_cordic), .strobe_in(strobe_cordic), .out(q_cordic_clip), .strobe_out());
  always @(posedge clk) last_cordic_clip <= (reset | clear) ? 1'b0 : last_cordic;

  cic_decimate #(.WIDTH(WIDTH), .N(4), .MAX_RATE(255)) cic_decimate_i (
    .clk(clk), .reset(reset | clear),
    .rate_stb(rate_changed_stb), .rate(cic_decim_rate), .strobe_in(strobe_cordic_clip), .strobe_out(strobe_cic),
    .last_in(last_cordic_clip), .last_out(last_cic), .signal_in(i_cordic_clip), .signal_out(i_cic));

  cic_decimate #(.WIDTH(WIDTH), .N(4), .MAX_RATE(255)) cic_decimate_q (
    .clk(clk), .reset(reset | clear),
    .rate_stb(rate_changed_stb), .rate(cic_decim_rate), .strobe_in(strobe_cordic_clip), .strobe_out(),
    .last_in(1'b0), .last_out(), .signal_in(q_cordic_clip), .signal_out(q_cic));

  // Halfbands
  wire nd1, nd2, nd3;
  wire rfd1, rfd2, rfd3;
  wire rdy1, rdy2, rdy3;
  wire data_valid1, data_valid2, data_valid3;

  localparam HB1_SCALE = 18;
  localparam HB2_SCALE = 18;
  localparam HB3_SCALE = 18;

  // Track last sample as it propagates through the half band filters
  // Note: Delays calibrated for specific pipeline delay in each hb filter
  reg [5:0] hb1_in_cnt, hb2_in_cnt, hb3_in_cnt;
  reg [4:0] hb1_out_cnt, hb2_out_cnt, hb3_out_cnt;
  reg [4:0] hb1_last_cnt, hb2_last_cnt, hb3_last_cnt;
  reg hb1_last_set, hb2_last_set, hb3_last_set;
  reg last_hb1, last_hb2, last_hb3;
  always @(posedge clk) begin
    if (reset | clear) begin
      hb1_in_cnt   <= 'd0;
      hb2_in_cnt   <= 'd0;
      hb3_in_cnt   <= 'd0;
      hb1_out_cnt  <= 'd0;
      hb2_out_cnt  <= 'd0;
      hb3_out_cnt  <= 'd0;
      hb1_last_cnt <= 'd0;
      hb2_last_cnt <= 'd0;
      hb3_last_cnt <= 'd0;
      hb1_last_set <= 1'b0;
      hb2_last_set <= 1'b0;
      hb3_last_set <= 1'b0;
      last_hb1     <= 1'b0;
      last_hb2     <= 1'b0;
      last_hb3     <= 1'b0;
    end else begin
      // HB1
      if (strobe_cic & rfd1) begin
        hb1_in_cnt     <= hb1_in_cnt + 1'b1;
        if (last_cic) begin
          hb1_last_set <= 1'b1;
          hb1_last_cnt <= hb1_in_cnt[5:1];
        end
      end
      if (strobe_hb1) begin
        hb1_out_cnt    <= hb1_out_cnt + 1'b1;
      end
      // Avoid subtracting 1 from hb1_last_cnt by initializing hb1_out_cnt = 1
      if (hb1_last_set & (hb1_out_cnt == hb1_last_cnt)) begin
        last_hb1       <= 1'b1;
        hb1_last_set   <= 1'b0;
        hb1_last_cnt   <= 'd0;
      end else if (last_hb1 & strobe_hb1 & rfd2) begin
        last_hb1       <= 1'b0;
      end
      // HB2
      if (strobe_hb1 & rfd2) begin
        hb2_in_cnt   <= hb2_in_cnt + 1'b1;
        if (last_hb1) begin
          hb2_last_set <= 1'b1;
          hb2_last_cnt <= hb2_in_cnt[5:1];
        end
      end
      if (strobe_hb2) begin
        hb2_out_cnt    <= hb2_out_cnt + 1'b1;
      end
      if (hb2_last_set & (hb2_out_cnt == hb2_last_cnt)) begin
        last_hb2       <= 1'b1;
        hb2_last_set   <= 1'b0;
        hb2_last_cnt   <= 'd0;
      end else if (last_hb2 & strobe_hb2 & rfd3) begin
        last_hb2       <= 1'b0;
      end
      // HB3
      if (strobe_hb2 & rfd3) begin
        hb3_in_cnt     <= hb3_in_cnt + 1'b1;
        if (last_hb2) begin
          hb3_last_set <= 1'b1;
          hb3_last_cnt <= hb3_in_cnt[5:1];
        end
      end
      if (strobe_hb3) begin
        hb3_out_cnt    <= hb3_out_cnt + 1'b1;
      end
      if (hb3_last_set & (hb3_out_cnt == hb3_last_cnt)) begin
        last_hb3       <= 1'b1;
        hb3_last_set   <= 1'b0;
        hb3_last_cnt   <= 'd0;
      end else if (last_hb3 & strobe_hb3) begin
        last_hb3       <= 1'b0;
      end
    end
  end

  // Each filter will accept N-1 samples before outputting
  // a sample. This logic "preloads" the pipeline with 0s
  // so the first sample in is the first sample out.
  integer hb1_cnt, hb2_cnt, hb3_cnt;
  reg hb1_en, hb2_en, hb3_en, hb1_rdy, hb2_rdy, hb3_rdy;
  generate
    if (PRELOAD_HBS) begin
      always @(posedge clk) begin
        if (reset | clear) begin
          hb1_cnt <= 0;
          hb2_cnt <= 0;
          hb3_cnt <= 0;
          hb1_en  <= 1'b1;
          hb2_en  <= 1'b1;
          hb3_en  <= 1'b1;
          hb1_rdy <= 1'b0;
          hb2_rdy <= 1'b0;
          hb3_rdy <= 1'b0;
        end else begin
          if (hb1_en & rfd1) begin
            if (hb1_cnt < 46) begin
              hb1_cnt <= hb1_cnt + 1;
            end else begin
              hb1_rdy <= 1'b1;
              hb1_en  <= 1'b0;
            end
          end
          if (hb2_en & rfd2) begin
            if (hb2_cnt < 46) begin
              hb2_cnt <= hb2_cnt + 1;
            end else begin
              hb2_rdy <= 1'b1;
              hb2_en  <= 1'b0;
            end
          end
          if (hb3_en & rfd3) begin
            if (hb3_cnt < 62) begin
              hb3_cnt <= hb3_cnt + 1;
            end else begin
              hb3_rdy <= 1'b1;
              hb3_en  <= 1'b0;
            end
          end
        end
      end
    end else begin
      always @(*) begin
        hb1_en  <= 1'b0;
        hb2_en  <= 1'b0;
        hb3_en  <= 1'b0;
        hb1_rdy <= 1'b1;
        hb2_rdy <= 1'b1;
        hb3_rdy <= 1'b1;
      end
    end
  endgenerate

  assign sample_in_rdy = hb1_rdy & hb2_rdy & hb3_rdy;

  assign strobe_hb1 = data_valid1 & ~hb1_en;
  assign strobe_hb2 = data_valid2 & ~hb2_en;
  assign strobe_hb3 = data_valid3 & ~hb3_en;
  assign nd1 = strobe_cic | hb1_en;
  assign nd2 = strobe_hb1 | hb2_en;
  assign nd3 = strobe_hb2 | hb3_en;

  hbdec1 hbdec1 (
    .clk(clk), // input clk
    .sclr(reset | clear), // input sclr
    .ce(1'b1), // input ce
    .coef_ld(reload_go & reload_ld1), // input coef_ld
    .coef_we(reload_go & reload_we1), // input coef_we
    .coef_din(coef_din), // input [17 : 0] coef_din
    .rfd(rfd1), // output rfd
    .nd(nd1), // input nd
    .din_1(i_cic), // input [23 : 0] din_1
    .din_2(q_cic), // input [23 : 0] din_2
    .rdy(rdy1), // output rdy
    .data_valid(data_valid1), // output data_valid
    .dout_1(i_hb1), // output [46 : 0] dout_1
    .dout_2(q_hb1)); // output [46 : 0] dout_2

  hbdec2 hbdec2 (
    .clk(clk), // input clk
    .sclr(reset | clear), // input sclr
    .ce(1'b1), // input ce
    .coef_ld(reload_go & reload_ld2), // input coef_ld
    .coef_we(reload_go & reload_we2), // input coef_we
    .coef_din(coef_din), // input [17 : 0] coef_din
    .rfd(rfd2), // output rfd
    .nd(nd2), // input nd
    .din_1(i_hb1[23+HB1_SCALE:HB1_SCALE]), // input [23 : 0] din_1
    .din_2(q_hb1[23+HB1_SCALE:HB1_SCALE]), // input [23 : 0] din_2
    .rdy(rdy2), // output rdy
    .data_valid(data_valid2), // output data_valid
    .dout_1(i_hb2), // output [46 : 0] dout_1
    .dout_2(q_hb2)); // output [46 : 0] dout_2

  hbdec3 hbdec3 (
    .clk(clk), // input clk
    .sclr(reset | clear), // input sclr
    .ce(1'b1), // input ce
    .coef_ld(reload_go & reload_ld3), // input coef_ld
    .coef_we(reload_go & reload_we3), // input coef_we
    .coef_din(coef_din), // input [17 : 0] coef_din
    .rfd(rfd3), // output rfd
    .nd(nd3), // input nd
    .din_1(i_hb2[23+HB2_SCALE:HB2_SCALE]), // input [23 : 0] din_1
    .din_2(q_hb2[23+HB2_SCALE:HB2_SCALE]), // input [23 : 0] din_2
    .rdy(rdy3), // output rdy
    .data_valid(data_valid3), // output data_valid
    .dout_1(i_hb3), // output [47 : 0] dout_1
    .dout_2(q_hb3)); // output [47 : 0] dout_2

  reg [23:0] i_unscaled, q_unscaled;
  reg strobe_unscaled;
  reg last_unscaled;

  always @(posedge clk) begin
    if (reset | clear) begin
      i_unscaled <= 'd0;
      q_unscaled <= 'd0;
      last_unscaled <= 1'b0;
      strobe_unscaled <= 1'b0;
    end else begin
      case(hb_rate)
        2'd0 : begin
          last_unscaled <= last_cic;
          strobe_unscaled <= strobe_cic;
          i_unscaled <= i_cic[23:0];
          q_unscaled <= q_cic[23:0];
        end
        2'd1 : begin
          last_unscaled <= last_hb1;
          strobe_unscaled <= strobe_hb1;
          i_unscaled <= i_hb1[23+HB1_SCALE:HB1_SCALE];
          q_unscaled <= q_hb1[23+HB1_SCALE:HB1_SCALE];
        end
        2'd2 : begin
          last_unscaled <= last_hb2;
          strobe_unscaled <= strobe_hb2;
          i_unscaled <= i_hb2[23+HB2_SCALE:HB2_SCALE];
          q_unscaled <= q_hb2[23+HB2_SCALE:HB2_SCALE];
        end
        2'd3 : begin
          last_unscaled <= last_hb3;
          strobe_unscaled <= strobe_hb3;
          i_unscaled <= i_hb3[23+HB3_SCALE:HB3_SCALE];
          q_unscaled <= q_hb3[23+HB3_SCALE:HB3_SCALE];
        end
      endcase // case (hb_rate)
    end
  end

  wire [42:0] i_scaled, q_scaled;
  wire [23:0] i_clip, q_clip;
  reg         strobe_scaled;
  reg         last_scaled;
  wire        strobe_clip;
  reg [1:0]   last_clip;

  MULT_MACRO #(
    .DEVICE("7SERIES"),     // Target Device: "VIRTEX5", "VIRTEX6", "SPARTAN6","7SERIES" 
    .LATENCY(1),            // Desired clock cycle latency, 0-4
    .WIDTH_A(25),           // Multiplier A-input bus width, 1-25
    .WIDTH_B(18))           // Multiplier B-input bus width, 1-18
  SCALE_I (.P(i_scaled),    // Multiplier output bus, width determined by WIDTH_P parameter 
    .A({i_unscaled[23],i_unscaled}),     // Multiplier input A bus, width determined by WIDTH_A parameter 
    .B(scale_factor),                    // Multiplier input B bus, width determined by WIDTH_B parameter 
    .CE(strobe_unscaled),   // 1-bit active high input clock enable
    .CLK(clk),              // 1-bit positive edge clock input
    .RST(reset | clear));   // 1-bit input active high reset

  MULT_MACRO #(
    .DEVICE("7SERIES"),     // Target Device: "VIRTEX5", "VIRTEX6", "SPARTAN6","7SERIES" 
    .LATENCY(1),            // Desired clock cycle latency, 0-4
    .WIDTH_A(25),           // Multiplier A-input bus width, 1-25
    .WIDTH_B(18))           // Multiplier B-input bus width, 1-18
   SCALE_Q (.P(q_scaled),   // Multiplier output bus, width determined by WIDTH_P parameter 
    .A({q_unscaled[23],q_unscaled}),     // Multiplier input A bus, width determined by WIDTH_A parameter 
    .B(scale_factor),                    // Multiplier input B bus, width determined by WIDTH_B parameter 
    .CE(strobe_unscaled),   // 1-bit active high input clock enable
    .CLK(clk),              // 1-bit positive edge clock input
    .RST(reset | clear));   // 1-bit input active high reset

  always @(posedge clk) begin
    if (reset | clear) begin
      strobe_scaled   <= 1'b0;
      last_scaled     <= 1'b0;
      last_clip       <= 'd0;
      sample_out_last <= 1'b0;
    end else begin
      strobe_scaled   <= strobe_unscaled;
      last_scaled     <= last_unscaled;
      last_clip[1:0]  <= {last_clip[0], last_scaled};
      sample_out_last <= last_clip[1];
    end
  end

  clip_reg #(.bits_in(29), .bits_out(24), .STROBED(1)) clip_i (
    .clk(clk), .reset(reset | clear), .in(i_scaled[42:14]), .strobe_in(strobe_scaled), .out(i_clip), .strobe_out(strobe_clip));
  clip_reg #(.bits_in(29), .bits_out(24), .STROBED(1)) clip_q (
    .clk(clk), .reset(reset | clear), .in(q_scaled[42:14]), .strobe_in(strobe_scaled), .out(q_clip), .strobe_out());

  round_sd #(.WIDTH_IN(24), .WIDTH_OUT(16), .DISABLE_SD(1)) round_i (
    .clk(clk), .reset(reset | clear), .in(i_clip), .strobe_in(strobe_clip), .out(sample_out[31:16]), .strobe_out(sample_out_stb));
  round_sd #(.WIDTH_IN(24), .WIDTH_OUT(16), .DISABLE_SD(1)) round_q (
    .clk(clk), .reset(reset | clear), .in(q_clip), .strobe_in(strobe_clip), .out(sample_out[15:0]), .strobe_out());

endmodule // ddc_chain
