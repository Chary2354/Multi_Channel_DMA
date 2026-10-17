// File: rtl/dma_controller.v
// 4-channel, 32-bit DMA controller
// Fixed priority: channel 0 > channel 1 > channel 2 > channel 3

`timescale 1ns/1ps
module dma_controller (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [3:0]   ch_req,
    input  wire [127:0] ch_src_addr,
    input  wire [127:0] ch_dst_addr,
    input  wire [127:0]  ch_length,   // Number of 32-bit words per channel

    output reg  [3:0]   ch_done,
    output reg  [3:0]   ch_error,
    output reg  [3:0]   ch_busy,

    output wire         mem_rd_req,
    output wire [31:0]  mem_rd_addr,
    input  wire         mem_rd_valid,
    input  wire [31:0]  mem_rd_data,

    output wire         mem_wr_req,
    output wire [31:0]  mem_wr_addr,
    output wire [31:0]  mem_wr_data,
    input  wire         mem_wr_ready
);

    localparam IDLE     = 3'd0;
    localparam READ_REQ = 3'd1;
    localparam READ_WAIT= 3'd2;
    localparam WRITE_REQ= 3'd3;

    reg [2:0] state;
    reg [1:0] active_ch;

    reg [31:0] src_reg;
    reg [31:0] dst_reg;
    reg [31:0] data_reg;
    reg [31:0] remaining;

    assign mem_rd_req  = (state == READ_REQ);
    assign mem_rd_addr = src_reg;

    assign mem_wr_req  = (state == WRITE_REQ);
    assign mem_wr_addr = dst_reg;
    assign mem_wr_data = data_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            active_ch <= 2'd0;
            src_reg   <= 32'd0;
            dst_reg   <= 32'd0;
            data_reg  <= 32'd0;
            remaining <= 32'd0;
            ch_done   <= 4'b0000;
            ch_error  <= 4'b0000;
            ch_busy   <= 4'b0000;
        end else begin
            // Completion and error outputs are one-clock pulses.
            ch_done  <= 4'b0000;
            ch_error <= 4'b0000;

            case (state)
                IDLE: begin
                    // Channel 0 has the highest priority.
                    if (ch_req[0]) begin
                        if (ch_length[31:0] == 0)
                            ch_error[0] <= 1'b1;
                        else begin
                            active_ch <= 2'd0;
                            src_reg <= ch_src_addr[31:0];
                            dst_reg <= ch_dst_addr[31:0];
                            remaining <= ch_length[31:0];
                            ch_busy[0] <= 1'b1;
                            state <= READ_REQ;
                        end
                    end else if (ch_req[1]) begin
                        if (ch_length[63:32] == 0)
                            ch_error[1] <= 1'b1;
                        else begin
                            active_ch <= 2'd1;
                            src_reg <= ch_src_addr[63:32];
                            dst_reg <= ch_dst_addr[63:32];
                            remaining <= ch_length[63:32];
                            ch_busy[1] <= 1'b1;
                            state <= READ_REQ;
                        end
                    end else if (ch_req[2]) begin
                        if (ch_length[95:64] == 0)
                            ch_error[2] <= 1'b1;
                        else begin
                            active_ch <= 2'd2;
                            src_reg <= ch_src_addr[95:64];
                            dst_reg <= ch_dst_addr[95:64];
                            remaining <= ch_length[95:64];
                            ch_busy[2] <= 1'b1;
                            state <= READ_REQ;
                        end
                    end else if (ch_req[3]) begin
                        if (ch_length[127:96] == 0)
                            ch_error[3] <= 1'b1;
                        else begin
                            active_ch <= 2'd3;
                            src_reg <= ch_src_addr[127:96];
                            dst_reg <= ch_dst_addr[127:96];
                            remaining <= ch_length[127:96];
                            ch_busy[3] <= 1'b1;
                            state <= READ_REQ;
                        end
                    end
                end

                READ_REQ: begin
                    // Read request is asserted for this state.
                    state <= READ_WAIT;
                end

                READ_WAIT: begin
                    if (mem_rd_valid) begin
                        data_reg <= mem_rd_data;
                        state <= WRITE_REQ;
                    end
                end

                WRITE_REQ: begin
                    // Keep write request asserted until accepted.
                    if (mem_wr_ready) begin
                        if (remaining == 1) begin
                            ch_done[active_ch] <= 1'b1;
                            ch_busy[active_ch] <= 1'b0;
                            remaining <= 0;
                            state <= IDLE;
                        end else begin
                            src_reg <= src_reg + 4;
                            dst_reg <= dst_reg + 4;
                            remaining <= remaining - 1;
                            state <= READ_REQ;
                        end
                    end
                end

                default: begin
                    state <= IDLE;
                    ch_busy <= 4'b0000;
                end
            endcase
        end
    end

endmodule