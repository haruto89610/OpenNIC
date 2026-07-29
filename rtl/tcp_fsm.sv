// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps

import packages::*;
module tcp_fsm (
    input logic         rx_valid,

    input tcp_state_t   tcp_curr_t,
    output tcp_state_t  tcp_next_t,

    input tcp_csr_t     tcp_csr_rx,
    output tcp_csr_t    tcp_csr_tx,
    output logic        invalidate,
    output logic        established
);

// A received RST never generates a RST response.

assign established = (tcp_curr_t == ESTABLISHED);

always_comb begin
    tcp_csr_tx  = '0;
    invalidate  = 1'b0;

    if (rx_valid) begin
        unique case (tcp_curr_t)
            CLOSED: begin
                if (tcp_csr_rx == CSR_SYN || tcp_csr_rx == CSR_ACK|| tcp_csr_rx == CSR_FIN) begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
            LISTEN: begin
                if (tcp_csr_rx == CSR_SYN) begin
                    tcp_csr_tx = CSR_SYN_ACK;
                end
                else if (tcp_csr_rx == CSR_FIN || tcp_csr_rx == CSR_ACK) begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
                else if (tcp_csr_rx == CSR_RST) begin
                    invalidate = 1'b1;
                end
                else begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
            SYN_RECV: begin
                if (tcp_csr_rx == CSR_SYN) begin
                    tcp_csr_tx = CSR_SYN_ACK;
                end
                else if (tcp_csr_rx == CSR_ACK) begin
                end
                else if (tcp_csr_rx == CSR_RST) begin
                    invalidate = 1'b1;
                end
                else begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
            SYN_SENT: begin
                if (tcp_csr_rx.syn && tcp_csr_rx.ack) begin
                    tcp_csr_tx = CSR_ACK;
                end
                else if (tcp_csr_rx.syn) begin
                    tcp_csr_tx = CSR_SYN_ACK;
                end
                else if (tcp_csr_rx.rst) begin
                    invalidate = 1'b1;
                end
                else begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
        ESTABLISHED: begin
            if (tcp_csr_rx.fin) begin
                tcp_csr_tx = CSR_FIN_ACK;
            end
            else if (tcp_csr_rx.syn) begin
                tcp_csr_tx = CSR_RST;
                invalidate = 1'b1;
            end
                else if (tcp_csr_rx.ack) begin
                end
                else if (tcp_csr_rx.rst) begin
                    invalidate = 1'b1;
                end
                else begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
        FIN_1: begin
            if (tcp_csr_rx.fin) begin
                tcp_csr_tx = CSR_FIN_ACK;
            end
            else if (tcp_csr_rx.ack) begin
            end
            else if (tcp_csr_rx.rst) begin
                    invalidate = 1'b1;
                end
                else begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
        FIN_2: begin
            if (tcp_csr_rx.fin) begin
                tcp_csr_tx = CSR_FIN_ACK;
            end
            else if (tcp_csr_rx.ack) begin
            end
            else if (tcp_csr_rx.rst) begin
                    invalidate = 1'b1;
                end
                else begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
        CLOSING: begin
            if (tcp_csr_rx.fin) begin
                tcp_csr_tx = CSR_FIN_ACK;
            end
            else if (tcp_csr_rx.ack) begin
            end
            else if (tcp_csr_rx.rst) begin
                    invalidate = 1'b1;
                end
                else begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
        CLOSE_WAIT: begin
            if (tcp_csr_rx.fin) begin
                tcp_csr_tx = CSR_FIN_ACK;
            end
            else if (tcp_csr_rx.ack) begin
            end
            else if (tcp_csr_rx.rst) begin
                    invalidate = 1'b1;
                end
                else begin
                    tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
        LAST_ACK: begin
            if (tcp_csr_rx.fin) begin
                tcp_csr_tx = CSR_FIN_ACK;
            end
            else if (tcp_csr_rx.ack) begin
            end
            else if (tcp_csr_rx.rst) begin
                invalidate = 1'b1;
            end
            else begin
                tcp_csr_tx = CSR_RST;
                invalidate = 1'b1;
            end
        end
        TIME_WAIT: begin
            if (tcp_csr_rx.fin) begin
                tcp_csr_tx = CSR_FIN_ACK;
            end
            else if (tcp_csr_rx.ack) begin
            end
            else if (tcp_csr_rx.rst) begin
                invalidate = 1'b1;
            end
            else begin
                tcp_csr_tx = CSR_RST;
                    invalidate = 1'b1;
                end
            end
            default: begin
                tcp_csr_tx = CSR_RST;
                invalidate = 1'b1;
            end
        endcase
    end
end

always_comb begin
    tcp_next_t = tcp_curr_t;

    case (tcp_curr_t)
        CLOSED : begin
            // The receive-driven control path enters passive-open handling.
            tcp_next_t = LISTEN;
        end
        LISTEN : begin
            if (rx_valid && tcp_csr_rx.syn) begin
                tcp_next_t = SYN_RECV;
            end
            else begin
                tcp_next_t = LISTEN;
            end
        end
        SYN_RECV : begin
            if (rx_valid && tcp_csr_rx.ack) begin
                tcp_next_t = ESTABLISHED;
            end
            else if (rx_valid && tcp_csr_rx.rst) begin
                tcp_next_t = CLOSED;
            end
        end
        SYN_SENT : begin
            if (rx_valid && tcp_csr_rx.rst) begin
                tcp_next_t = CLOSED;
            end
            else if (rx_valid && (tcp_csr_rx.syn && tcp_csr_rx.ack)) begin
                tcp_next_t = ESTABLISHED;
            end
            else if (rx_valid && tcp_csr_rx.syn) begin
                tcp_next_t = SYN_RECV;
            end
        end
        ESTABLISHED : begin
            if (rx_valid && tcp_csr_rx.rst) begin
                tcp_next_t = CLOSED;
            end
            else if (rx_valid && tcp_csr_rx.fin) begin
                tcp_next_t = TIME_WAIT;
            end
        end
        FIN_1 : begin
            if (rx_valid && tcp_csr_rx.rst) begin
                tcp_next_t = CLOSED;
            end
            else if (rx_valid && tcp_csr_rx.fin) begin
                tcp_next_t = TIME_WAIT;
            end
            else if (rx_valid && tcp_csr_rx.ack) begin
                tcp_next_t = FIN_2;
            end
        end
        FIN_2 : begin
            if (rx_valid && tcp_csr_rx.rst) begin
                tcp_next_t = CLOSED;
            end
            else if (rx_valid && tcp_csr_rx.fin) begin
                tcp_next_t = TIME_WAIT;
            end
        end
        CLOSING : begin
            if (rx_valid && tcp_csr_rx.rst) begin
                tcp_next_t = CLOSED;
            end
            else if (rx_valid && tcp_csr_rx.ack) begin
                tcp_next_t = TIME_WAIT;
            end
        end
        CLOSE_WAIT : begin
            if (rx_valid && tcp_csr_rx.rst) begin
                tcp_next_t = CLOSED;
            end
        end
        LAST_ACK : begin
            if (rx_valid && tcp_csr_rx.rst) begin
                tcp_next_t = CLOSED;
            end
            else if (rx_valid && tcp_csr_rx.ack) begin
                tcp_next_t = CLOSED;
            end
        end
        TIME_WAIT : begin
            tcp_next_t = CLOSED;
        end
        default : begin
        end
    endcase

    if (invalidate) begin
        tcp_next_t = CLOSED;
    end
end

endmodule
