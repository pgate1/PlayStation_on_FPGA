// Inserted into the verified APF reference core_top by prepare_diagnostic.py.
// Host commands remain clocked by clk_74a; only reset release crosses here.
wire diagnostic_pixel_reset_n;
diagnostic_reset diagnostic_reset_i (
    .clk_pixel(clk_core_12288),
    .host_reset_n(reset_n),
    .pll_locked(pll_core_locked),
    .pixel_reset_n(diagnostic_pixel_reset_n)
);

assign video_rgb_clock = clk_core_12288;
assign video_rgb_clock_90 = clk_core_12288_90deg;
diagnostic_core diagnostic_core_i (
    .clk_pixel(clk_core_12288),
    .reset_n(diagnostic_pixel_reset_n),
    .button_async(cont1_key[4]),
    .video_rgb(video_rgb),
    .video_de(video_de),
    .video_hs(video_hs),
    .video_vs(video_vs),
    .video_skip(video_skip)
);

// This diagnostic has no saves or target-initiated data transfers.
assign savestate_supported = 1'b0;
assign savestate_addr = 32'd0;
assign savestate_size = 32'd0;
assign savestate_maxloadsize = 32'd0;
assign savestate_start_ack = 1'b0;
assign savestate_start_busy = 1'b0;
assign savestate_start_ok = 1'b0;
assign savestate_start_err = 1'b0;
assign savestate_load_ack = 1'b0;
assign savestate_load_busy = 1'b0;
assign savestate_load_ok = 1'b0;
assign savestate_load_err = 1'b0;
assign target_dataslot_read = 1'b0;
assign target_dataslot_write = 1'b0;
assign target_dataslot_getfile = 1'b0;
assign target_dataslot_openfile = 1'b0;
assign target_dataslot_id = 16'd0;
assign target_dataslot_slotoffset = 32'd0;
assign target_dataslot_bridgeaddr = 32'd0;
assign target_dataslot_length = 32'd0;
assign target_buffer_param_struct = 32'd0;
assign target_buffer_resp_struct = 32'd0;
