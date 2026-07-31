// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps

import packages::*;

module tx_desc_issue(
    input logic     clk,
    input logic     rst,

    input logic     invalidate,
    input logic     tx_desc_valid_in,
    input tcp_tx_desc_t tx_desc_in,

    output logic        tx_desc_valid_out,
    output tcp_tx_desc_t    tx_desc_out
);

always_ff @(posedge clk) begin
    if (rst) begin
        tx_desc_out         <= '0;
        tx_desc_valid_out   <= '0;
    end
    else begin
        tx_desc_valid_out <= tx_desc_valid_in && !invalidate;

        if (tx_desc_valid_in && !invalidate) begin
            tx_desc_out <= tx_desc_in;
        end
    end
end

endmodule
