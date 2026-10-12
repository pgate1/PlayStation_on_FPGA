`timescale 1ns/1ps
// Pixel-domain color-bar and button diagnostic for the Pocket APF core.
// Timing and active-window coordinates are pinned in docs/POCKET_DIAGNOSTIC_INPUTS.md.
module diagnostic_core (
    input  wire        clk_pixel,
    input  wire        reset_n,
    input  wire        button_async,
    output wire [23:0] video_rgb,
    output wire        video_de,
    output wire        video_hs,
    output wire        video_vs,
    output wire        video_skip
);

    reg [8:0] x_count;
    reg [8:0] y_count;

    reg button_meta;
    reg button_sync;
    reg frame_button;

    reg [23:0] rgb_reg;
    reg de_reg;
    reg hs_reg;
    reg vs_reg;

    assign video_rgb  = reset_n ? rgb_reg : 24'h000000;
    assign video_de   = reset_n ? de_reg : 1'b0;
    assign video_hs   = reset_n ? hs_reg : 1'b0;
    assign video_vs   = reset_n ? vs_reg : 1'b0;
    assign video_skip = 1'b0;

    always @(posedge clk_pixel or negedge reset_n) begin
        if (!reset_n) begin
            x_count     <= 9'd0;
            y_count     <= 9'd0;
            button_meta <= 1'b0;
            button_sync <= 1'b0;
            frame_button <= 1'b0;
            rgb_reg     <= 24'h000000;
            de_reg      <= 1'b0;
            hs_reg      <= 1'b0;
            vs_reg      <= 1'b0;
        end else begin
            button_meta <= button_async;
            button_sync <= button_meta;

            // Outputs describe the pre-edge counter position. The frame value
            // is held until the next frame boundary, so color cannot tear.
            de_reg <= (x_count >= 9'd10) && (x_count <= 9'd329) &&
                      (y_count >= 9'd10) && (y_count <= 9'd249);
            hs_reg <= (x_count == 9'd3);
            vs_reg <= (x_count == 9'd0) && (y_count == 9'd0);

            if ((x_count >= 9'd10) && (x_count <= 9'd329) &&
                (y_count >= 9'd10) && (y_count <= 9'd249)) begin
                if ((x_count < 9'd50) && (y_count < 9'd50)) begin
                    rgb_reg <= frame_button ? 24'h00FF00 : 24'hFF0000;
                end else begin
                    if      (x_count < 9'd50)  rgb_reg <= 24'hFFFFFF;
                    else if (x_count < 9'd90)  rgb_reg <= 24'hFFFF00;
                    else if (x_count < 9'd130) rgb_reg <= 24'h00FFFF;
                    else if (x_count < 9'd170) rgb_reg <= 24'h00FF00;
                    else if (x_count < 9'd210) rgb_reg <= 24'hFF00FF;
                    else if (x_count < 9'd250) rgb_reg <= 24'hFF0000;
                    else if (x_count < 9'd290) rgb_reg <= 24'h0000FF;
                    else                       rgb_reg <= 24'h000000;
                end
            end else begin
                rgb_reg <= 24'h000000;
            end

            if ((x_count == 9'd0) && (y_count == 9'd0))
                frame_button <= button_sync;

            if (x_count == 9'd399) begin
                x_count <= 9'd0;
                if (y_count == 9'd511)
                    y_count <= 9'd0;
                else
                    y_count <= y_count + 9'd1;
            end else begin
                x_count <= x_count + 9'd1;
            end
        end
    end

endmodule
