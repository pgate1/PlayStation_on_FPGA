`timescale 1ns/1ps

module tb_diagnostic_core;
    reg clk_pixel = 1'b0;
    reg reset_n = 1'b0;
    reg button_async = 1'b0;
    wire [23:0] video_rgb;
    wire video_de, video_hs, video_vs, video_skip;

    diagnostic_core dut (
        .clk_pixel(clk_pixel), .reset_n(reset_n),
        .button_async(button_async), .video_rgb(video_rgb),
        .video_de(video_de), .video_hs(video_hs), .video_vs(video_vs),
        .video_skip(video_skip)
    );

    always #5 clk_pixel = ~clk_pixel;

    integer ex = 0, ey = 0;
    reg model_meta = 1'b0, model_sync = 1'b0, model_frame_button = 1'b0;
    reg [23:0] want_rgb;
    reg want_de, want_hs, want_vs;
    integer frame_hs = 0, frame_vs = 0, frame_de = 0;
    integer completed_frames = 0;
    integer checked_pixels = 0;
    integer errors = 0;
    integer bar_index;

    initial begin
        #10000000;
        $fatal(1, "watchdog timeout");
    end

    // Independent cycle scoreboard: expected outputs use the model's own
    // coordinates and button pipeline, never DUT internals.
    always @(posedge clk_pixel or negedge reset_n) begin
        if (!reset_n) begin
            ex = 0;
            ey = 0;
            model_meta = 1'b0;
            model_sync = 1'b0;
            model_frame_button = 1'b0;
            frame_hs = 0;
            frame_vs = 0;
            frame_de = 0;
            completed_frames = 0;
        end else begin
            want_de = (ex >= 10 && ex <= 329 && ey >= 10 && ey <= 249);
            want_hs = (ex == 3);
            want_vs = (ex == 0 && ey == 0);
            want_rgb = 24'h000000;
            if (want_de) begin
                if (ex < 50 && ey < 50)
                    want_rgb = model_frame_button ? 24'h00FF00 : 24'hFF0000;
                else begin
                    bar_index = (ex - 10) / 40;
                    case (bar_index)
                        0: want_rgb = 24'hFFFFFF;
                        1: want_rgb = 24'hFFFF00;
                        2: want_rgb = 24'h00FFFF;
                        3: want_rgb = 24'h00FF00;
                        4: want_rgb = 24'hFF00FF;
                        5: want_rgb = 24'hFF0000;
                        6: want_rgb = 24'h0000FF;
                        default: want_rgb = 24'h000000;
                    endcase
                end
            end

            // Registered outputs are checked after DUT nonblocking updates.
            #1;
            if (video_rgb !== want_rgb || video_de !== want_de ||
                video_hs !== want_hs || video_vs !== want_vs || video_skip !== 1'b0) begin
                $display("FAIL pixel=%0d,%0d got rgb=%h de=%b hs=%b vs=%b skip=%b expected rgb=%h de=%b hs=%b vs=%b",
                         ex, ey, video_rgb, video_de, video_hs, video_vs,
                         video_skip, want_rgb, want_de, want_hs, want_vs);
                errors = errors + 1;
                if (errors >= 10) $fatal(1, "too many scoreboard mismatches");
            end
            checked_pixels = checked_pixels + 1;

            // Use sampled DUT outputs for frame totals. A VS begins a new
            // frame; validate the prior frame before including this pulse.
            if (video_vs === 1'b1) begin
                if (completed_frames > 0) begin
                    if (frame_hs != 512 || frame_vs != 1 || frame_de != 76800) begin
                        $display("FAIL frame %0d totals: HS=%0d VS=%0d DE=%0d",
                                 completed_frames, frame_hs, frame_vs, frame_de);
                        errors = errors + 1;
                    end
                end
                completed_frames = completed_frames + 1;
                frame_hs = 0;
                frame_vs = 0;
                frame_de = 0;
            end
            if (video_hs === 1'b1) frame_hs = frame_hs + 1;
            if (video_vs === 1'b1) frame_vs = frame_vs + 1;
            if (video_de === 1'b1) frame_de = frame_de + 1;

            // Model nonblocking synchronizer/frame-latch semantics using old
            // pipeline values at the edge.
            if (ex == 0 && ey == 0)
                model_frame_button = model_sync;
            model_sync = model_meta;
            model_meta = button_async;

            if (ex == 399) begin
                ex = 0;
                if (ey == 511) ey = 0;
                else ey = ey + 1;
            end else ex = ex + 1;
        end
    end

    task clocks(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(negedge clk_pixel);
        end
    endtask

    initial begin
        clocks(3);
        reset_n = 1'b1;

        // Start an intentionally partial frame, then interrupt it with reset.
        clocks(1200);
        reset_n = 1'b0;
        #1;
        if (video_rgb !== 24'h000000 || video_de !== 1'b0 ||
            video_hs !== 1'b0 || video_vs !== 1'b0 || video_skip !== 1'b0)
            $fatal(1, "outputs were not forced low during reset");
        clocks(2);
        reset_n = 1'b1;

        // Change the button mid-frame. It must affect the patch only after
        // synchronization and the next frame boundary; then change it back
        // mid-frame to exercise the opposite transition.
        clocks(1000);
        button_async = 1'b1;
        clocks(204800 + 1000);
        button_async = 1'b0;
        clocks(204800 * 2 + 1000);

        if (completed_frames < 3)
            $fatal(1, "only %0d frame starts were observed; need 3 for 2 full frames",
                   completed_frames);
        if (errors != 0)
            $fatal(1, "%0d errors", errors);
        $display("PASS diagnostic_core: frames=%0d checked_pixels=%0d (204800 clocks/frame)",
                 completed_frames - 1, checked_pixels);
        $finish;
    end
endmodule
