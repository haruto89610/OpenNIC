// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps

module fifo #(
    parameter int WIDTH = 16,
    parameter int DEPTH = 16,
    parameter int FWFT  = 0
) (
    input  logic                 clk,
    input  logic                 srst,
    input  logic [WIDTH-1:0]     din,
    input  logic                 wr_en,
    input  logic                 rd_en,
    output logic [WIDTH-1:0]     dout,
    output logic                 full,
    output logic                 empty,
    output logic                 valid,
    output logic                 overflow,
    output logic                 wr_rst_busy,
    output logic                 rd_rst_busy
);

localparam string READ_MODE   = (FWFT != 0) ? "fwft" : "std";
localparam int    READ_LATENCY = (FWFT != 0) ? 0 : 1;

logic [READ_LATENCY:0] rd_shift;

xpm_fifo_sync #(
    .FIFO_WRITE_DEPTH   (DEPTH),
    .READ_DATA_WIDTH    (WIDTH),
    .WRITE_DATA_WIDTH   (WIDTH),
    .READ_MODE          (READ_MODE),
    .FIFO_READ_LATENCY  (READ_LATENCY)
) xpm_fifo_sync_i (
    .almost_empty   (),
    .almost_full    (),
    .data_valid     (),
    .dbiterr        (),
    .din            (din),
    .dout           (dout),
    .empty          (empty),
    .full           (full),
    .injectdbiterr  (1'b0),
    .injectsbiterr  (1'b0),
    .overflow       (overflow),
    .prog_empty     (),
    .prog_full      (),
    .rd_data_count  (),
    .rd_en          (rd_en),
    .rd_rst_busy    (rd_rst_busy),
    .rst            (srst),
    .sbiterr        (),
    .sleep          (1'b0),
    .underflow      (),
    .wr_ack         (),
    .wr_clk         (clk),
    .wr_data_count  (),
    .wr_en          (wr_en),
    .wr_rst_busy    (wr_rst_busy)
);

// Build a valid pulse aligned with dout: FWFT => ~empty, otherwise delay rd_en by read latency
generate
if (READ_LATENCY == 0) begin : g_fwft_valid
    assign valid = ~empty;
end else begin : g_std_valid
    always_ff @(posedge clk) begin
        if (srst) begin
            rd_shift <= '0;
        end else begin
            rd_shift <= {rd_shift[READ_LATENCY-1:0], (rd_en && !empty)};
        end
    end
    assign valid = rd_shift[READ_LATENCY];
end
endgenerate

endmodule
