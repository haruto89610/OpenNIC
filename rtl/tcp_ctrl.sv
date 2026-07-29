// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps


module tcp_ctrl(
    input logic         clk,
    input logic         rst,

    // ---------------------------------- WB INPUTS
    input logic         path,
    input logic         valid_in,
    input logic [5:0]   addr_in,
    input tcb_t         tcb_in,

    // ---------------------------------- RX INPUTS
    input logic         new_packet_d,
    input tcp_csr_t     rx_csr,
    input header_t      header_data,

    // ---------------------------------- TCB OUTPUTS
    output logic        cancel_rto_temp,
    output logic        invalidate_temp,
    output logic        valid_out_temp,
    output logic [5:0]  addr_out_temp,
    output tcb_t        tcb_out_temp
);

tcp_state_t tcp_curr_t;
tcp_state_t tcp_next_t;
tcp_csr_t   tx_csr;

logic   invalidate_fsm;
logic   invalidate_rto;

logic   ingress;
logic   egress;

logic [31:0]    rx_ip_hdr_bytes;
logic [31:0]    rx_tcp_hdr_bytes;
logic [31:0]    rx_payload_len;
logic [31:0]    tx_seq_end;

// Registered output stage for control-path timing closure.
logic        cancel_rto;
logic        invalidate;
logic        valid_out;
logic [5:0]  addr_out;
tcb_t        tcb_out;

always_ff @(posedge clk) begin
    cancel_rto_temp <= cancel_rto;
    invalidate_temp <= invalidate;
    valid_out_temp  <= valid_out;

    if (rst) begin
        addr_out_temp   <= '0;
        tcb_out_temp    <= '0;
    end
    else if (valid_out) begin
        addr_out_temp   <= addr_out;
        tcb_out_temp    <= tcb_out;
    end
end


// Only ingress packets advance the TCP state machine.
tcp_fsm tcp_fsm_i (
    .rx_valid       (ingress),
    .tcp_curr_t     (tcp_curr_t),
    .tcp_next_t     (tcp_next_t),
    .tcp_csr_rx     (rx_csr),
    .tcp_csr_tx     (tx_csr),
    .invalidate     (invalidate_fsm),
    .established    ()
);

assign invalidate   = invalidate_fsm || invalidate_rto || (valid_out && tcb_out.tcp_curr_t == CLOSED);

assign ingress      = path && valid_in;
assign egress       = ~path && valid_in;

assign valid_out    = valid_in;
assign addr_out     = addr_in;

assign rx_ip_hdr_bytes  = {26'd0, header_data.ipv4_hdr.ihl, 2'b00};
assign rx_tcp_hdr_bytes = {26'd0, header_data.tcp_hdr.data_off, 2'b00};
assign rx_payload_len   = (header_data.ipv4_hdr.total_len > (rx_ip_hdr_bytes + rx_tcp_hdr_bytes))
                        ? (header_data.ipv4_hdr.total_len - rx_ip_hdr_bytes - rx_tcp_hdr_bytes)
                        : '0;
assign tx_seq_end       = tcb_in.seq_num + tcb_in.len_num + tcb_in.csr_curr.syn + tcb_in.csr_curr.fin;

// -------------------------------------------------------- STATE TRANSITION AND RTO UPDATE
// -------------------------------------------------------- SEQ/ACK UPDATE
/*
    SEQ/ACK UPDATE PSEUDOCODE:

    if (ingress):
        if (csr.ack):   // includes ACK, SYNACK, FINACK
            if (tcb.snd_una < packet.ack && packet.ack <= tcb.snd_nxt):
                tcb.snd_una = packet.ack;
            else:
                RST or DROP+ACK

        if (packet.seq == tcb.rcv_nxt):
            tcb.rcv_nxt += len + (SYN ? 1 : 0) + (FIN ? 1 : 0);

    if (egress):
        packet.seq  = tcb.snd_nxt;
        packet.ack  = tcb.rcv_nxt;

        if (new_packet && sent): // FPGA opens
            snd_nxt += len + (SYN ? 1 : 0) + (FIN ? 1 : 0);
*/

always_comb begin
    tcb_out         = tcb_in;
    invalidate_rto  = '0;
    cancel_rto      = '0;

    if (ingress) begin
        tcp_curr_t  = new_packet_d ? LISTEN : tcb_in.tcp_curr_t;

        tcb_out.tcp_curr_t  = tcp_next_t; // commit next state on ingress
        tcb_out.tcp_next_t  = tcp_next_t;
        tcb_out.csr_curr    = tx_csr;

        if (tx_csr.syn || tx_csr.fin) begin
            tcb_out.next_send_time = 1;
            tcb_out.backoff_exp    = 0;
        end

        if (rx_csr.ack) begin
            if (header_data.tcp_hdr.ack_num >= tx_seq_end) begin
                cancel_rto = '1;
                tcb_out.len_num = '0;
            end

            if (tcp_curr_t == SYN_RECV && header_data.tcp_hdr.ack_num > tcb_in.snd_nxt) begin
                // The current policy resets and invalidates SYN_RECV when an
                // ACK exceeds snd_nxt; retry-oriented handling is not implemented.
                tcb_out.csr_curr    = CSR_RST;
                invalidate_rto      = '1;
            end
            else if (header_data.tcp_hdr.ack_num > tcb_in.snd_una) begin
                tcb_out.snd_una = header_data.tcp_hdr.ack_num;
            end
        end

        if (new_packet_d) begin
            tcb_out.rcv_nxt = tcb_in.seq_num + 1;
        end
        else if (tcp_curr_t == SYN_SENT && rx_csr.syn && rx_csr.ack) begin
            tcb_out.rcv_nxt = header_data.tcp_hdr.seq_num + 32'd1;
        end
        else if (header_data.tcp_hdr.seq_num == tcb_in.rcv_nxt) begin
            tcb_out.rcv_nxt = header_data.tcp_hdr.seq_num + rx_payload_len + (rx_csr.syn ? 1 : 0) + (rx_csr.fin ? 1 : 0);
        end

        // Build the outgoing control segment from the current packet image,
        // not directly from state fields that may be advanced elsewhere.
        tcb_out.seq_num = tcb_in.snd_nxt;
        tcb_out.ack_num = tcb_out.rcv_nxt;

        if (tx_csr.syn || tx_csr.fin) begin
            tcb_out.snd_nxt = tcb_in.snd_nxt + 1;
        end
        else begin
            tcb_out.snd_nxt = tcb_in.snd_nxt;
        end
    end
    else if (egress) begin
        tcb_out.tcp_curr_t = tcb_in.tcp_next_t;
        tcb_out.tcp_next_t = tcb_in.tcp_next_t;

        // Retransmit existing segment image.
        tcb_out.seq_num  = tcb_in.seq_num;
        tcb_out.ack_num  = tcb_in.rcv_nxt;
        tcb_out.csr_curr = tcb_in.csr_curr;
        tcb_out.len_num  = tcb_in.len_num;

        // Do not consume sequence space on retransmit.
        tcb_out.snd_nxt = tcb_in.snd_nxt;

        if (tcb_in.backoff_exp == 'd4) begin
            tcb_out.csr_curr = CSR_RST;
            invalidate_rto   = 1'b1;
        end else begin
            tcb_out.next_send_time = 1;
            tcb_out.backoff_exp    = tcb_in.backoff_exp + 1'b1;
        end
    end
end

endmodule
