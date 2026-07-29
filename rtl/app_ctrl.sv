// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps

import packages::*;
module app_ctrl #(
    parameter logic [47:0]  FPGA_MAC    = 48'h00_12_34_56_78_90,
    parameter logic [31:0]  FPGA_IP     = {8'd192, 8'd168, 8'd0, 8'd10}
) (
    input logic                 clk,
    input logic                 rst,

    input logic                 valid_in,
    input logic [1:0]           path,
    input logic [5:0]           tcb_addr_in,

    input logic [15:0]          payload_len,

    input tcb_t                 tcb_in,

    input logic                 tcb_valid_app,
    input tcp_arp_t             tcb_meta_app,

    output logic                valid_out,
    output logic [5:0]          tcb_addr_out,
    output tcb_t                tcb_out
);

localparam logic [31:0] TCP_INITIAL_SEQ = 32'd0;

tcp_arp_t       pending_routing;
tcp_arp_t       routing_meta;
logic           pending_routing_valid;
logic           routing_meta_valid;
logic [15:0]    payload_len_q;

always_comb begin
    routing_meta        = tcb_valid_app ? tcb_meta_app : pending_routing;
    routing_meta_valid  = tcb_valid_app || pending_routing_valid;
    payload_len_q       = (path == 2'd3) ? 16'd16 : (routing_meta_valid ? routing_meta.payload_len : payload_len);

    tcb_out             = tcb_in;
    valid_out           = '0;
    tcb_addr_out        = tcb_addr_in;

    if (valid_in && tcb_in.tcp_curr_t == ESTABLISHED && payload_len_q != '0) begin
        valid_out               = 1'b1;

        tcb_out.csr_curr        = CSR_PSH_ACK;
        tcb_out.seq_num         = tcb_in.snd_nxt;
        tcb_out.ack_num         = tcb_in.rcv_nxt;
        tcb_out.len_num         = payload_len_q;
        tcb_out.snd_nxt         = tcb_in.snd_nxt + {16'd0, payload_len_q};

        tcb_out.next_send_time  = 'd1;
        tcb_out.backoff_exp     = '0;
    end
    else if (valid_in && routing_meta_valid && routing_meta.req_type == TCP_REQ_CONNECT_SEND) begin
        valid_out               = 1'b1;

        tcb_out.dest_mac        = routing_meta.dest_mac;
        tcb_out.src_mac         = FPGA_MAC;
        tcb_out.dest_ip         = routing_meta.dest_ip;
        tcb_out.src_ip          = routing_meta.src_ip;
        tcb_out.dest_port       = routing_meta.dest_port;
        tcb_out.src_port        = routing_meta.src_port;

        tcb_out.tcp_curr_t      = SYN_SENT;
        tcb_out.tcp_next_t      = SYN_SENT;
        tcb_out.seq_num         = TCP_INITIAL_SEQ;
        tcb_out.ack_num         = '0;
        tcb_out.len_num         = '0;
        tcb_out.snd_una         = TCP_INITIAL_SEQ;
        tcb_out.snd_nxt         = TCP_INITIAL_SEQ + 32'd1;
        tcb_out.rcv_nxt         = '0;

        tcb_out.next_send_time  = 'd1;
        tcb_out.backoff_exp     = '0;
        tcb_out.csr_curr        = CSR_SYN;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        pending_routing       <= '0;
        pending_routing_valid <= 1'b0;
    end
    else begin
        if (tcb_valid_app) begin
            pending_routing       <= tcb_meta_app;
            pending_routing_valid <= 1'b1;
        end
        else if (valid_in) begin
            pending_routing       <= '0;
            pending_routing_valid <= 1'b0;
        end
    end
end

endmodule
