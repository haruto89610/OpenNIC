// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps


import packages::*;
module tx_arbiter(
    input logic         clk,
    input logic         rst,

    input logic         hp_valid,
    input logic         hp_empty,
    output logic        hp_advance,
    input logic [5:0]   hp_tcb_addr,

    input logic         tick,
    input logic         lp_valid,
    input logic [5:0]   lp_tcb_addr,

    input logic         tx_datapath_ready,
    output logic        tcb_addr_out_valid,
    output logic [5:0]  tcb_addr_out
);

logic [2:0] quota;
logic       grant_hp;
logic       grant_lp;

always_comb begin
    grant_hp = '0;
    grant_lp = '0;
    hp_advance        = 1'b0;
    tcb_addr_out_valid = 1'b0;
    tcb_addr_out       = '0;

    if (tx_datapath_ready) begin
        if (quota > 3'd4) begin
            if (tick && lp_valid) begin
                grant_lp = 1'b1;
            end
            else if (hp_valid && !hp_empty) begin
                grant_hp = 1'b1;
            end
        end
        else begin
            if (hp_valid && !hp_empty) begin
                grant_hp = 1'b1;
            end
            else if (tick && lp_valid) begin
                grant_lp = 1'b1;
            end
        end
    end

    if (grant_hp) begin
        hp_advance        = 1'b1;
        tcb_addr_out_valid = 1'b1;
        tcb_addr_out       = hp_tcb_addr;
    end
    else if (grant_lp) begin
        tcb_addr_out_valid = 1'b1;
        tcb_addr_out       = lp_tcb_addr;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        quota <= '0;
    end
    else begin
        if (quota > 3'd4) begin
            if (grant_lp) begin
                quota <= '0;
            end
        end
        else begin
            if (grant_hp) begin
                quota <= quota + 1'b1;
            end
            else if (grant_lp) begin
                quota <= '0;
            end
        end
    end
end

endmodule
