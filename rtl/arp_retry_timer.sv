// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps


module arp_retry_timer #(
    parameter int TIMER_SZ = 16
) (
    input logic         clk,
    input logic         rst,

    input logic         arm_valid,
    input logic         arm_cancel,
    input logic [1:0]   arm_way,
    input logic [3:0]   arm_idx,
    input logic [9:0]   arm_deadline,

    output logic        timeout_valid,
    output logic [1:0]  timeout_way,
    output logic [3:0]  timeout_idx
);

localparam int PTR_W = (TIMER_SZ <= 2) ? 1 : $clog2(TIMER_SZ);

logic [22:0] us_tick;
logic [PTR_W-1:0] count;

// VALID | WAY | INDEX
logic [6:0] timer_wheel [0:TIMER_SZ-1];

logic [PTR_W-1:0] next_free;

always_comb begin
    automatic logic found = '0;
    automatic logic [PTR_W-1:0] search_start;
    next_free = '0;
    search_start = count + arm_deadline[PTR_W-1:0];

    // Fixed-bound scan so synthesis can statically unroll the loop.
    for (int ofs = 0; ofs < TIMER_SZ; ofs++) begin
        automatic logic [PTR_W-1:0] slot = search_start + ofs[PTR_W-1:0];
        if (!found && !timer_wheel[slot][6]) begin
            found       = 1'b1;
            next_free   = slot;
        end
    end
end

always_comb begin
    timeout_valid   = timer_wheel[count][6] && (&us_tick);
    timeout_way     = timer_wheel[count][5:4];
    timeout_idx     = timer_wheel[count][3:0];
end

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

always_ff @(posedge clk) begin
    if (rst) begin
        timer_wheel <= '{default : '0};
    end
    else begin
        timer_wheel[count - 1'b1][6] <= '0;

        if (arm_valid && arm_cancel) begin
            for (int i = 0; i < TIMER_SZ; i++) begin
                if (timer_wheel[i] == {1'b1, arm_way, arm_idx}) begin
                    timer_wheel[i] <= '0;
                end
            end
        end
        else if (arm_valid && !arm_cancel) begin
            automatic logic [PTR_W-1:0] target = count + arm_deadline[PTR_W-1:0];

            if (timer_wheel[target][6]) begin
                timer_wheel[next_free] <= {1'b1, arm_way, arm_idx};
            end
            else begin
                timer_wheel[target] <= {1'b1, arm_way, arm_idx};
            end
        end
    end
end

endmodule
