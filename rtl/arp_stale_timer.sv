// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps


module arp_stale_timer #(
    parameter int N_COMPARE     = 16,
    parameter int EXPIRATION    = 10
) (
    input logic         clk,
    input logic         rst,

    input logic         arm_valid,
    input logic         arm_cancel,
    input logic [1:0]   arm_way,
    input logic [3:0]   arm_idx,

    output logic        timeout_valid,
    output logic [1:0]  timeout_way,
    output logic [3:0]  timeout_idx
);

// VALID | AGE
logic [9:0]     valid_bitmap [64];
logic [63:0]    pending_bitmap;
logic [5:0]     parse_base;
logic [22:0] us_tick;
logic [8:0]     count;

// ----------------------------------------------------- TICK LOGIC
always_ff @(posedge clk) begin
    if (rst) begin
        us_tick <= '0;
        count   <= '0;
    end
    else begin
        us_tick <= us_tick + 1'b1;
        count   <= (&us_tick) ? count + 1'b1 : count;
    end
end

// ----------------------------------------------------- STALE LOGIC
// Queue expired entries in pending_bitmap.
always_ff @(posedge clk) begin
    if (rst) begin
        pending_bitmap  <= '0;
        parse_base      <= '0;
    end
    else begin
        parse_base <= parse_base + N_COMPARE;

        for (int i = 0; i < N_COMPARE; i++) begin
            automatic logic [5:0] entry = parse_base + i;
            automatic logic       valid = valid_bitmap[entry][9];
            automatic logic [8:0] age   = valid_bitmap[entry][8:0];

            if (valid && (count - age >= EXPIRATION)) begin
                pending_bitmap[entry] <= 1'b1;
            end
        end

        if (timeout_valid) begin
            pending_bitmap[(timeout_way << 4) + timeout_idx] <= 1'b0;
        end
    end
end

// ----------------------------------------------------- FIFO LOGIC
// Select one pending way/index for output.
always_comb begin
    automatic logic pushed = '0;

    timeout_valid   = '0;
    timeout_way     = '0;
    timeout_idx     = '0;

    for (int i = 0; i < 64; i++) begin
        if (!pushed && pending_bitmap[i]) begin
            pushed  = 1'b1;

            timeout_valid   = 1'b1;
            timeout_way     = {i[5:4]};
            timeout_idx     = {i[3:0]};
        end
    end
end

// ----------------------------------------------------- ARM LOGIC
// Update the validity and age map from arm requests.
always_ff @(posedge clk) begin
    if (rst) begin
        valid_bitmap <= '{default : '0};
    end
    else begin
        if (arm_valid && !arm_cancel) begin
            valid_bitmap[(arm_way << 4) + arm_idx] <= {1'b1, count};
        end

        if (arm_cancel) begin
            valid_bitmap[(arm_way << 4) + arm_idx][9] <= 1'b0;
        end

        if (timeout_valid) begin
            valid_bitmap[(timeout_way << 4) + timeout_idx][9] <= 1'b0;
        end
    end
end

endmodule
