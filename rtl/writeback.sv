// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps

import packages::*;
module writeback(
    input logic         clk,
    input logic         rst,

    input logic [63:0]  tcb_alloc,
    input logic         tcb_ready,

    // RX DATAPATH
    input logic         tcb_valid_rx,
    input logic [5:0]   tcb_addr_rx,

    // RTO / TX DATAPATH
    input logic         tcb_valid_tx,
    input logic [5:0]   tcb_addr_tx,

    // APP DATAPATH
    input logic         tcb_valid_app,
    input logic [5:0]   tcb_addr_app,

    // OPEN SEND DATAPATH
    input logic         tcb_valid_pl,
    input logic [5:0]   tcb_addr_pl,

    // TCB PORTS
    // Path to determine whether it was RX or TX
    // Path:
    //      0 - TX
    //      1 - RX
    //      2 - APP
    output logic [1:0]  path,
    output logic        valid,
    output logic [5:0]  addr
);

logic [5:0] tcb_addr_out_rto;
logic [5:0] tcb_addr_out_tx;
logic [5:0] tcb_addr_out_app;
logic [5:0] tcb_addr_out_pl;

logic fifo_advance_tx;
logic fifo_empty_tx;
logic fifo_valid_tx;

logic fifo_advance_app;
logic fifo_empty_app;
logic fifo_valid_app;

logic fifo_advance_pl;
logic fifo_empty_pl;
logic fifo_valid_pl;

fifo #(
    .WIDTH  (8),
    .DEPTH  (64),
    .FWFT   (1)
) tx_wb_i (
    .clk        (clk),
    .srst       (rst),
    .din        (tcb_addr_tx),
    .wr_en      (tcb_valid_tx),
    .rd_en      (fifo_advance_tx),
    .dout       (tcb_addr_out_tx),
    .full       (),
    .empty      (fifo_empty_tx),
    .valid      (fifo_valid_tx),
    .overflow   (),
    .wr_rst_busy(),
    .rd_rst_busy()
);

fifo #(
    .WIDTH  (8),
    .DEPTH  (64),
    .FWFT   (1)
) app_wb_i (
    .clk        (clk),
    .srst       (rst),
    .din        (tcb_addr_app),
    .wr_en      (tcb_valid_app),
    .rd_en      (fifo_advance_app),
    .dout       (tcb_addr_out_app),
    .full       (),
    .empty      (fifo_empty_app),
    .valid      (fifo_valid_app),
    .overflow   (),
    .wr_rst_busy(),
    .rd_rst_busy()
);

fifo #(
    .WIDTH  (8),
    .DEPTH  (64),
    .FWFT   (1)
) pl_wb_i (
    .clk        (clk),
    .srst       (rst),
    .din        (tcb_addr_pl),
    .wr_en      (tcb_valid_pl),
    .rd_en      (fifo_advance_pl),
    .dout       (tcb_addr_out_pl),
    .full       (),
    .empty      (fifo_empty_pl),
    .valid      (fifo_valid_pl),
    .overflow   (),
    .wr_rst_busy(),
    .rd_rst_busy()
);

always_comb begin
    /*
        Prioritize RX
        RX has entire data, TX only needs few snippets which
        can be stored in a FIFO with little cost.
    */
    fifo_advance_tx     = 1'b0;
    fifo_advance_app    = 1'b0;
    fifo_advance_pl     = 1'b0;

    addr            = 'X;
    valid           = '0;
    path            = '0;

    if (tcb_valid_rx) begin
        fifo_advance_tx = 1'b0;
        addr    = tcb_addr_rx;
        valid   = 1'b1;
        path    = 2'd1;
    end
    else if (fifo_valid_app || ~fifo_empty_app) begin
        fifo_advance_app = 1'b1;

        if (tcb_alloc[tcb_addr_out_app]) begin
            addr            = tcb_addr_out_app;
            valid           = fifo_valid_app;
            path            = 2'd2;
        end
        else if (!tcb_alloc[tcb_addr_out_app]) begin
            // Advance if TCB alloc is invalid but do not write
            valid           = 1'b0;
            path            = 2'd2;
        end
    end
    else if (fifo_valid_tx || ~fifo_empty_tx) begin
        fifo_advance_tx = 1'b1;

        if (tcb_alloc[tcb_addr_out_tx]) begin
            addr            = tcb_addr_out_tx;
            valid           = fifo_valid_tx;
            path            = 2'd0;
        end
        else if (!tcb_alloc[tcb_addr_out_tx]) begin
            // Advance if TCB alloc is invalid but do not write
            valid           = 1'b0;
            path            = 2'd0;
        end
    end
    else if (fifo_valid_pl || ~fifo_empty_pl) begin
        fifo_advance_pl = 1'b1;

        if (tcb_alloc[tcb_addr_out_pl]) begin
            addr            = tcb_addr_out_pl;
            valid           = fifo_valid_pl;
            path            = 2'd3;
        end
        else if (!tcb_alloc[tcb_addr_out_pl]) begin
            // Advance if TCB alloc is invalid but do not write
            valid           = 1'b0;
            path            = 2'd3;
        end
    end
end

endmodule
