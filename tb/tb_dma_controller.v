// File: tb/tb_dma_controller.v
`timescale 1ns/1ps

module tb_dma_controller;

    reg clk;
    reg rst_n;

    reg [3:0] ch_req;
    reg [127:0] ch_src_addr;
    reg [127:0] ch_dst_addr;
    reg [127:0] ch_length;

    wire [3:0] ch_done;
    wire [3:0] ch_error;
    wire [3:0] ch_busy;

    wire mem_rd_req;
    wire [31:0] mem_rd_addr;
    reg mem_rd_valid;
    reg [31:0] mem_rd_data;

    wire mem_wr_req;
    wire [31:0] mem_wr_addr;
    wire [31:0] mem_wr_data;
    reg mem_wr_ready;

    reg [31:0] memory [0:255];
    integer i;

    dma_controller dut (
        .clk(clk),
        .rst_n(rst_n),
        .ch_req(ch_req),
        .ch_src_addr(ch_src_addr),
        .ch_dst_addr(ch_dst_addr),
        .ch_length(ch_length),
        .ch_done(ch_done),
        .ch_error(ch_error),
        .ch_busy(ch_busy),
        .mem_rd_req(mem_rd_req),
        .mem_rd_addr(mem_rd_addr),
        .mem_rd_valid(mem_rd_valid),
        .mem_rd_data(mem_rd_data),
        .mem_wr_req(mem_wr_req),
        .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data),
        .mem_wr_ready(mem_wr_ready)
    );

    // 10 ns clock period.
    initial clk = 0;
    always #5 clk = ~clk;

    // Simple memory model.
    // Addresses are byte addresses; each word is 4 bytes.
    always @(posedge clk) begin
        mem_rd_valid <= 1'b0;

        if (rst_n && mem_rd_req) begin
            mem_rd_data <= memory[mem_rd_addr >> 2];
            mem_rd_valid <= 1'b1;
        end

        if (rst_n && mem_wr_req && mem_wr_ready) begin
            memory[mem_wr_addr >> 2] <= mem_wr_data;
            $display("[%0t ns] WRITE addr=%h data=%h",
                     $time, mem_wr_addr, mem_wr_data);
        end
    end

    // Create waveform file for GTKWave.
    initial begin
        $dumpfile("sim/dma.vcd");
        $dumpvars(0, tb_dma_controller);
    end

    initial begin
        rst_n = 0;
        ch_req = 0;
        ch_src_addr = 0;
        ch_dst_addr = 0;
        ch_length = 0;
        mem_rd_valid = 0;
        mem_rd_data = 0;
        mem_wr_ready = 1;

        for (i = 0; i < 256; i = i + 1)
            memory[i] = 0;

        // Source data at byte addresses 0x00, 0x04, 0x08, 0x0C.
        memory[0] = 32'h11111111;
        memory[1] = 32'h22222222;
        memory[2] = 32'h33333333;
        memory[3] = 32'h44444444;

        // Release reset.
        repeat (3) @(negedge clk);
        rst_n = 1;

        // Test 1: Channel 0 copies four words from 0x00 to 0x40.
        @(negedge clk);
        ch_src_addr[31:0] = 32'h00000000;
        ch_dst_addr[31:0] = 32'h00000040;
        ch_length[31:0] = 4;
        ch_req[0] = 1'b1;

        @(negedge clk);
        ch_req[0] = 1'b0;

        wait (ch_done[0] == 1'b1);
        @(negedge clk);

        if (memory[16] !== 32'h11111111 ||
            memory[17] !== 32'h22222222 ||
            memory[18] !== 32'h33333333 ||
            memory[19] !== 32'h44444444) begin
            $display("TEST 1 FAILED: copied data mismatch");
            $fatal(1);
        end else begin
            $display("TEST 1 PASSED: channel 0 copied four words");
        end

        // Test 2: A zero-length transfer must raise an error.
        @(negedge clk);
        ch_length[63:32] = 0;
        ch_req[1] = 1'b1;

        @(negedge clk);
        ch_req[1] = 1'b0;

        wait (ch_error[1] == 1'b1);
        $display("TEST 2 PASSED: zero-length transfer reported an error");

        // Test 3: Simultaneous requests and fixed priority.

        @(negedge clk);

        // Initialize source data.
        memory[4] = 32'hAAAA1234;
        memory[5] = 32'hBBBB5678;

        // Channel 0: one word from 0x10 to 0x50.
        ch_src_addr[31:0] = 32'h00000010;
        ch_dst_addr[31:0] = 32'h00000050;
        ch_length[31:0] = 1;

        // Channel 1: one word from 0x14 to 0x60.
        ch_src_addr[63:32] = 32'h00000014;
        ch_dst_addr[63:32] = 32'h00000060;
        ch_length[63:32] = 1;

        // Assert both requests together.
        ch_req[0] = 1'b1;
        ch_req[1] = 1'b1;

        // Confirm channel 0 starts first.
        wait (ch_busy[0] == 1'b1);
        $display("TEST 3: Channel 0 selected first");

        // Keep channel 1 pending while channel 0 runs.
        @(negedge clk);
        ch_req[0] = 1'b0;

        wait (ch_done[0] == 1'b1);
        $display("TEST 3: Channel 0 transfer completed");

        // Channel 1 should run next.
        wait (ch_busy[1] == 1'b1);
        wait (ch_done[1] == 1'b1);

        @(negedge clk);
        ch_req[1] = 1'b0;

        // Verify both destination values.
        if (memory[20] !== 32'hAAAA1234 ||
            memory[24] !== 32'hBBBB5678) begin
            $display("TEST 3 FAILED: data mismatch");
            $fatal(1);
        end else begin
            $display("TEST 3 PASSED: simultaneous requests handled");
        end

        // Test 4: Memory backpressure.
        // Hold mem_wr_ready low and verify the write stays stable.

        @(negedge clk);

        // Configure channel 0 for a one-word transfer.
        memory[8] = 32'hCAFE1234;  // Source address 0x20

        ch_src_addr[31:0] = 32'h00000020;
        ch_dst_addr[31:0] = 32'h00000070;
        ch_length[31:0] = 1;

        // Delay write acceptance.
        mem_wr_ready = 1'b0;
        ch_req[0] = 1'b1;

        @(negedge clk);
        ch_req[0] = 1'b0;

        // Wait until the write request appears.
        wait (mem_wr_req == 1'b1);

        // Capture the transaction while memory is not ready.
        begin : backpressure_check
            reg [31:0] held_addr;
            reg [31:0] held_data;
            integer stall_cycle;

            held_addr = mem_wr_addr;
            held_data = mem_wr_data;

            for (stall_cycle = 0; stall_cycle < 3;
                 stall_cycle = stall_cycle + 1) begin
                @(negedge clk);

                if (mem_wr_req !== 1'b1 ||
                    mem_wr_addr !== held_addr ||
                    mem_wr_data !== held_data) begin
                    $display("TEST 4 FAILED: write changed during stall");
                    $fatal(1);
                end
            end

            $display("TEST 4: write stayed stable during backpressure");
        end

        // Allow memory to accept the pending write.
        @(negedge clk);
        mem_wr_ready = 1'b1;

        wait (ch_done[0] == 1'b1);
        @(negedge clk);

        if (memory[28] !== 32'hCAFE1234) begin
            $display("TEST 4 FAILED: destination data mismatch");
            $fatal(1);
        end else begin
            $display("TEST 4 PASSED: memory backpressure handled");
        end
        
        repeat (3) @(negedge clk);
        $display("ALL BASIC TESTS PASSED");
        $finish;
    end

    // Prevent a broken simulation from waiting forever.
    initial begin
        #10000;
        $display("TIMEOUT: simulation did not finish");
        $fatal(1);
    end

endmodule