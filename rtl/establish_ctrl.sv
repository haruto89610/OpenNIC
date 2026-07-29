// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps

import packages::*;
module establish_ctrl(
    input logic         clk,
    input logic         rst,

    input logic         path,
    input logic         valid_in,
    input logic [5:0]   addr_in,

    input tcb_t         tcb_in,
    input header_t      header_data,

    output logic        valid_out,
    output tcb_t        tcb_out,

    output logic        ack_valid,
    output logic [5:0]  ack_addr,
    output logic [31:0] ack_snd_una
);

logic   ingress;
logic   egress;
logic [31:0]    payload_len;
logic [17:0]    ihl;
logic [17:0]    data_off;

assign ingress      = path && valid_in;
assign egress       = ~path && valid_in;

assign ihl      = header_data.ipv4_hdr.ihl << 2;
assign data_off = header_data.tcp_hdr.data_off << 2;

assign payload_len  = header_data.ipv4_hdr.total_len - ihl - data_off;

always_comb begin
    tcb_out     = tcb_in;
    valid_out   = valid_in;

    ack_valid   = '0;
    ack_addr    = '0;
    ack_snd_una = '0;

    if (ingress) begin
        tcb_out.csr_curr = (payload_len > 0) ? CSR_ACK : '0;

        if (header_data.tcp_csr.ack) begin
            if (tcb_in.snd_una < header_data.tcp_hdr.ack_num &&
                header_data.tcp_hdr.ack_num <= tcb_in.snd_nxt) begin

                tcb_out.snd_una = header_data.tcp_hdr.ack_num;

                ack_valid   = 1'b1;
                ack_addr    = addr_in;
                ack_snd_una = header_data.tcp_hdr.ack_num;
            end

            if (header_data.tcp_hdr.ack_num >= tcb_in.seq_num + tcb_in.len_num) begin
                tcb_out.snd_una = header_data.tcp_hdr.ack_num;

                ack_valid   = 1'b1;
                ack_addr    = addr_in;
                ack_snd_una = header_data.tcp_hdr.ack_num;

                tcb_out.csr_curr        = '0;
                tcb_out.len_num         = '0;
                tcb_out.next_send_time  = '0;
                tcb_out.backoff_exp     = '0;
            end
        end

        if (header_data.tcp_hdr.seq_num == tcb_in.rcv_nxt) begin
            tcb_out.rcv_nxt = header_data.tcp_hdr.seq_num + payload_len;
        end
        else if (payload_len > 0 && (header_data.tcp_hdr.seq_num != tcb_in.rcv_nxt)) begin
            // A duplicate ACK requests retransmission of the expected sequence.
            tcb_out.csr_curr = CSR_ACK;
        end

        // Keep the transmit descriptor sourced from an explicit packet image.
        tcb_out.seq_num = tcb_in.snd_nxt;
        tcb_out.ack_num = tcb_out.rcv_nxt;
    end
    else if (egress) begin
        tcb_out.seq_num = tcb_in.seq_num;
        tcb_out.ack_num = tcb_in.rcv_nxt;

        tcb_out.csr_curr= tcb_in.csr_curr;
        tcb_out.len_num = tcb_in.len_num;

        tcb_out.snd_nxt = tcb_in.snd_nxt;

        // Retry state advances when this egress request is processed; this
        // control path has no downstream acceptance handshake.
        tcb_out.next_send_time = 1;
        tcb_out.backoff_exp    = tcb_in.backoff_exp + 1;
    end
end

endmodule
