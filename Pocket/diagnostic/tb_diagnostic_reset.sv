`timescale 1ns/1ps

module tb_diagnostic_reset;
    reg clk_pixel = 1'b0;
    reg host_reset_n = 1'b1;
    reg pll_locked = 1'b1;
    wire pixel_reset_n;
    reg previous_reset_n = 1'b0;
    integer release_count = 0;
    integer assertion_count = 0;

    diagnostic_reset dut (
        .clk_pixel(clk_pixel),
        .host_reset_n(host_reset_n),
        .pll_locked(pll_locked),
        .pixel_reset_n(pixel_reset_n)
    );

    initial begin
        #10000;
        $fatal(1, "watchdog timeout");
    end

    // Any transition to X is invalid. A falling reset output is permitted
    // only when one of its asynchronous assertion sources is low.
    always @(pixel_reset_n) begin
        if ((pixel_reset_n !== 1'b0) && (pixel_reset_n !== 1'b1))
            $fatal(1, "pixel_reset_n became unknown at %0t", $time);
        if (previous_reset_n && !pixel_reset_n && host_reset_n && pll_locked)
            $fatal(1, "pixel_reset_n fell while both reset sources were high");
        if (!previous_reset_n && pixel_reset_n)
            release_count = release_count + 1;
        if (previous_reset_n && !pixel_reset_n)
            assertion_count = assertion_count + 1;
        previous_reset_n = pixel_reset_n;
    end

    task pixel_tick;
        begin
            #2;
            clk_pixel = 1'b1;
            #1;
            clk_pixel = 1'b0;
            #1;
        end
    endtask

    task expect_low;
        input [255:0] reason;
        begin
            #1;
            if (pixel_reset_n !== 1'b0)
                $fatal(1, "expected reset asserted: %0s (got %b)", reason, pixel_reset_n);
        end
    endtask

    task expect_high;
        input [255:0] reason;
        begin
            #1;
            if (pixel_reset_n !== 1'b1)
                $fatal(1, "expected reset released: %0s (got %b)", reason, pixel_reset_n);
        end
    endtask

    initial begin
        // Establish asynchronous PLL-loss assertion away from a pixel edge.
        #1;
        pll_locked = 1'b0;
        expect_low("PLL lock-loss assertion");

        // Releasing host reset alone cannot release while PLL is unlocked.
        host_reset_n = 1'b1;
        pixel_tick();
        expect_low("PLL remains unlocked");
        pixel_tick();
        expect_low("PLL remains unlocked after two edges");

        // Lock can arrive independently. Release is exactly two rising edges.
        #1;
        pll_locked = 1'b1;
        expect_low("before first release edge");
        pixel_tick();
        expect_low("after first release edge");
        pixel_tick();
        expect_high("after second release edge");

        // Host reset asserts between edges and stays asserted across clocks.
        #1;
        host_reset_n = 1'b0;
        expect_low("asynchronous host reset while clock is stopped");
        pixel_tick();
        pixel_tick();
        expect_low("held host reset");
        host_reset_n = 1'b1;
        expect_low("host reset release before an edge");
        pixel_tick();
        expect_low("host release edge one");
        pixel_tick();
        expect_high("host release edge two");

        // PLL loss independently asserts reset without waiting for a clock.
        #1;
        pll_locked = 1'b0;
        expect_low("asynchronous PLL loss");
        pixel_tick();
        pixel_tick();
        expect_low("held PLL loss");
        pll_locked = 1'b1;
        expect_low("PLL relock before an edge");
        pixel_tick();
        expect_low("relock edge one");
        pixel_tick();
        expect_high("relock edge two");

        // A second assertion between the two release edges cancels release.
        #1;
        host_reset_n = 1'b0;
        expect_low("start reassert-before-second-edge sequence");
        host_reset_n = 1'b1;
        pixel_tick();
        expect_low("first release attempt edge one");
        #1;
        host_reset_n = 1'b0;
        expect_low("reassertion cancels pending release");
        host_reset_n = 1'b1;
        expect_low("restart release sequence without a clock");
        pixel_tick();
        expect_low("restarted release edge one");
        pixel_tick();
        expect_high("restarted release edge two");

        // Stop the pixel clock, assert and release host reset, then prove the
        // output remains reset until clocks resume.
        #1;
        host_reset_n = 1'b0;
        expect_low("assertion before stopped-clock test");
        host_reset_n = 1'b1;
        #20;
        expect_low("no release with stopped pixel clock");
        pixel_tick();
        expect_low("stopped-clock recovery edge one");
        pixel_tick();
        expect_high("stopped-clock recovery edge two");

        if (release_count != 5)
            $fatal(1, "expected five clean releases, observed %0d", release_count);
        if (assertion_count != 4)
            $fatal(1, "expected four asynchronous assertions, observed %0d", assertion_count);
        $display("PASS diagnostic_reset: releases=%0d async_assertions=%0d",
                 release_count, assertion_count);
        $finish;
    end
endmodule
