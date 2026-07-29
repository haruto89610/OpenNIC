// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps

import packages::*;
module rto #(
    parameter int       RTO_SZ = 64
) (
    input logic         clk,
    input logic         rst,

    input logic         cancel_rto,
    input logic         write,
    input logic [5:0]   tcb_addr_in,
    input tcb_t         tcb_data_in,

    input logic         tx_datapath_ready,
    output logic        tcb_addr_out_valid,
    output logic [5:0]  tcb_addr_out
);

localparam int MAP_W    = $clog2(RTO_SZ);

logic [23:0]    us_tick;

logic           tick;
logic [6:0]     timer_wheel [RTO_SZ];
logic [6:0]     timer_wheel_val;
logic           timer_wheel_valid;
logic [6:0]     timer_wheel_entry;
logic [$clog2(RTO_SZ)-1:0]    slot_idx;
logic [$clog2(RTO_SZ)-1:0]    rd_ptr;

logic [5:0]     hp_din;
logic [5:0]     hp_dout;
logic           hp_wr_en;
logic           hp_valid;
logic           hp_empty;
logic           hp_advance;

// VALID | SLOT INDEX
// Indexed by TCB ADDRESS
logic [MAP_W:0]    mapping [64];

assign timer_wheel_val    = timer_wheel[rd_ptr];
assign timer_wheel_valid  = timer_wheel_val[6];
assign timer_wheel_entry  = timer_wheel_val[5:0];

fifo #(
    .WIDTH  (8),
    .DEPTH  (32),
    .FWFT   (1)
) priority_queue (
    .clk        (clk),
    .srst       (rst),
    .din        (hp_din),
    .wr_en      (hp_wr_en),
    .rd_en      (hp_advance && tx_datapath_ready),
    .dout       (hp_dout),
    .full       (),
    .empty      (hp_empty),
    .valid      (hp_valid),
    .overflow   (),
    .wr_rst_busy(),
    .rd_rst_busy()
);

tx_arbiter tx_arbiter_i (
    .clk            (clk),
    .rst            (rst),

    .hp_valid       (hp_valid),
    .hp_empty       (hp_empty),
    .hp_advance     (hp_advance),
    .hp_tcb_addr    (hp_dout),

    .tick           (tick),
    .lp_valid       (timer_wheel_valid),
    .lp_tcb_addr    (timer_wheel_entry),

    .tx_datapath_ready  (tx_datapath_ready),
    .tcb_addr_out_valid (tcb_addr_out_valid),
    .tcb_addr_out       (tcb_addr_out)
);

always_comb begin
    hp_din      = '0;
    hp_wr_en    = '0;

    slot_idx = rd_ptr + 1'b1;

    if (cancel_rto) begin
        if (mapping[tcb_addr_in][MAP_W]) begin
            slot_idx = mapping[tcb_addr_in][MAP_W-1:0];
        end
    end
    else if (write) begin
        // WRITE TO HIGH PRIORITY FIFO
        if (tcb_data_in.next_send_time == '0 || tcb_data_in.csr_curr.rst) begin
            hp_din      = tcb_addr_in;
            hp_wr_en    = 1'b1;
        end
        // WRITE TO TIMER WHEEL
        if (tcb_data_in.next_send_time != '0 && !tcb_data_in.csr_curr.rst) begin
            slot_idx = rd_ptr + (tcb_data_in.next_send_time << (tcb_data_in.backoff_exp + 1'b1));
        end
    end
end

always_ff @(posedge clk) begin
    tick    <= &us_tick;

    if (rst) begin
        us_tick <= '0;
    end
    else begin
        us_tick <= us_tick + 1'b1;
    end
end

// -------------------------------------------------------------- READ LOGIC
always_ff @(posedge clk) begin
    if (rst) begin
        rd_ptr  <= '0;
    end
    else if (tick) begin
        rd_ptr  <= rd_ptr + 1'b1;
    end
end

// -------------------------------------------------------------- WRITE LOGIC
// -------------------------------------------------------------- CANCEL LOGIC
always_ff @(posedge clk) begin
    if (rst) begin
        mapping     <= '{default : 0};
        timer_wheel <= '{default : 0};
    end
    else if (cancel_rto && mapping[tcb_addr_in][MAP_W]) begin
        mapping[tcb_addr_in][MAP_W] <= 1'b0;
        timer_wheel[slot_idx]   <= '0;
    end
    else if (write) begin
        if (tcb_data_in.next_send_time != '0 && !tcb_data_in.csr_curr.rst) begin
            // If timer wheel is already allocated
            if (timer_wheel[slot_idx][6]) begin
                mapping[tcb_addr_in] <= {1'b1, slot_idx + 1'b1};

                timer_wheel[slot_idx + 1'b1][6]     <= 1'b1;
                timer_wheel[slot_idx + 1'b1][5:0]   <= tcb_addr_in;
            end
            else begin
                mapping[tcb_addr_in] <= {1'b1, slot_idx};

                timer_wheel[slot_idx][6]    <= 1'b1;
                timer_wheel[slot_idx][5:0]  <= tcb_addr_in;
            end
        end
    end

    if (tick) begin
        // Invalidate Previous Index
        if (timer_wheel[rd_ptr][6] && mapping[timer_wheel[rd_ptr][5:0]] == rd_ptr) begin
            mapping[timer_wheel[rd_ptr][5:0]] <= '0;
        end

        timer_wheel[rd_ptr] <= '0;
    end
end

endmodule
