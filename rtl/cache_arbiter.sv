// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps


module cache_arbiter(
    input logic     clk,
    input logic     rst,

    input logic     tcb_valid,
    input logic     cache_full,

    input logic     rx_empty,
    input logic     payload_empty,

    output logic    grant_rx,
    output logic    grant_payload
);

logic busy;

always_ff @(posedge clk) begin
    if (rst) begin
        busy <= '0;
    end
    else if (grant_rx || grant_payload) begin
        busy <= '1;
    end
    else if (tcb_valid || cache_full) begin
        busy <= '0;
    end
end

always_comb begin
    grant_rx        = '0;
    grant_payload   = '0;

    if (!payload_empty) begin
        grant_payload   = !busy && !payload_empty;
    end
    else if (!rx_empty) begin
        grant_rx        = !busy && !rx_empty;
    end
end

endmodule
