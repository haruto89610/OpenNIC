// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps

import packages::*;
module tx_datapath(
    input logic             clk,
    input logic             rst,

    output logic [575:0]    s_axis_c2h_tdata,
    output logic            s_axis_c2h_tvalid,
    output logic            s_axis_c2h_tlast,
    output logic [7:0]      s_axis_c2h_frame_bytes,

    input logic             s_axis_c2h_tready,

    input logic             tcp_valid,
    input tcp_tx_desc_t     tcp_desc,
    input logic             tcp_payload_valid,
    input logic [15:0]      tcp_payload_len,
    input logic [127:0]     tcp_payload_data,

    input logic             arp_valid,
    input arp_tx_desc_t     arp_desc
);

logic [19:0]    ip_sum;
logic [19:0]    tcp_sum;
logic [19:0]    payload_sum;
logic [15:0]    ip_checksum;
logic [15:0]    tcp_checksum;
logic [15:0]    tcp_flags_word;
logic [15:0]    ip_total_len;
logic [15:0]    tcp_total_len;
logic [7:0]     payload_len_bytes;

logic           tcp_valid_s0;
tcp_tx_desc_t   tcp_desc_s0;
logic           tcp_payload_valid_s0;
logic [15:0]    tcp_payload_len_s0;
logic [127:0]   tcp_payload_data_s0;

logic           tcp_valid_s1;
tcp_tx_desc_t   tcp_desc_s1;
logic [127:0]   tcp_payload_data_s1;
logic [7:0]     payload_len_bytes_s1;
logic [15:0]    ip_total_len_s1;
logic [15:0]    tcp_total_len_s1;
logic [15:0]    ip_checksum_s1;
logic [15:0]    tcp_checksum_s1;

assign s_axis_c2h_tvalid    = |s_axis_c2h_tdata;
assign s_axis_c2h_tlast     = s_axis_c2h_tvalid;

always_comb begin
    payload_len_bytes = (tcp_payload_valid_s0 && tcp_valid_s0) ? tcp_payload_len_s0[7:0] : 8'd0;
    ip_total_len      = 16'd40 + payload_len_bytes;
    tcp_total_len     = 16'd20 + payload_len_bytes;
end

// -------------------------------------------------------------------------- IP CHECKSUM
always_comb begin
    ip_sum = 20'h4500
           + ip_total_len
           + 20'h0000 + 20'h4000 + 20'h4006
           + tcp_desc_s0.src_ip[31:16] + tcp_desc_s0.src_ip[15:0]
           + tcp_desc_s0.dest_ip[31:16] + tcp_desc_s0.dest_ip[15:0];
    ip_sum = ip_sum[15:0] + ip_sum[19:16];
    ip_sum = ip_sum[15:0] + ip_sum[19:16];

    ip_checksum = ~ip_sum[15:0];
end

// -------------------------------------------------------------------------- TCP_CHECKSUM
always_comb begin
    tcp_flags_word = {4'd5, 4'd0, 3'b0, tcp_desc_s0.csr_curr.ack, tcp_desc_s0.csr_curr.psh,
                      tcp_desc_s0.csr_curr.rst, tcp_desc_s0.csr_curr.syn, tcp_desc_s0.csr_curr.fin};

    payload_sum = '0;
    for (int i = 0; i < 8; i++) begin
        if ((2*i + 1) < payload_len_bytes) begin
            payload_sum += tcp_payload_data_s0[127-(i*16) -: 16];
        end
        else if ((2*i) < payload_len_bytes) begin
            payload_sum += {tcp_payload_data_s0[127-(i*16) -: 8], 8'h00};
        end
    end

    tcp_sum = 20'h0006 + tcp_total_len +
              tcp_desc_s0.src_ip[31:16] + tcp_desc_s0.src_ip[15:0] +
              tcp_desc_s0.dest_ip[31:16] + tcp_desc_s0.dest_ip[15:0] +
              tcp_desc_s0.src_port + tcp_desc_s0.dest_port +
              tcp_desc_s0.seq_num[31:16] + tcp_desc_s0.seq_num[15:0] +
              tcp_desc_s0.ack_num[31:16] + tcp_desc_s0.ack_num[15:0] +
              tcp_flags_word + 16'hFFFF +
              payload_sum;
    tcp_sum = tcp_sum[15:0] + tcp_sum[19:16];
    tcp_sum = tcp_sum[15:0] + tcp_sum[19:16];

    tcp_checksum = ~tcp_sum[15:0];
end

always_ff @(posedge clk) begin
    if (rst) begin
        s_axis_c2h_tdata       <= '0;
        s_axis_c2h_frame_bytes <= '0;

        tcp_valid_s0           <= 1'b0;
        tcp_desc_s0            <= '0;
        tcp_payload_valid_s0   <= 1'b0;
        tcp_payload_len_s0     <= '0;
        tcp_payload_data_s0    <= '0;

        tcp_valid_s1           <= 1'b0;
        tcp_desc_s1            <= '0;
        tcp_payload_data_s1    <= '0;
        payload_len_bytes_s1   <= '0;
        ip_total_len_s1        <= '0;
        tcp_total_len_s1       <= '0;
        ip_checksum_s1         <= '0;
        tcp_checksum_s1        <= '0;
    end
    else begin
        tcp_valid_s0         <= tcp_valid && (|tcp_desc.csr_curr);
        if (tcp_valid && (|tcp_desc.csr_curr)) begin
            tcp_desc_s0          <= tcp_desc;
            tcp_payload_valid_s0 <= tcp_payload_valid;
            tcp_payload_len_s0   <= tcp_payload_len;
            tcp_payload_data_s0  <= tcp_payload_data;
        end

        tcp_valid_s1           <= tcp_valid_s0;
        tcp_desc_s1            <= tcp_desc_s0;
        tcp_payload_data_s1    <= tcp_payload_data_s0;
        payload_len_bytes_s1   <= payload_len_bytes;
        ip_total_len_s1        <= ip_total_len;
        tcp_total_len_s1       <= tcp_total_len;
        ip_checksum_s1         <= ip_checksum;
        tcp_checksum_s1        <= tcp_checksum;

        if (tcp_valid_s1) begin
            s_axis_c2h_frame_bytes      <= 8'd54 + payload_len_bytes_s1;
            s_axis_c2h_tdata[575:464]   <= {tcp_desc_s1.dest_mac, tcp_desc_s1.src_mac, ETH_TYPE_IPV4};

            // ------------------------------------------------------------------ IP HEADER
            s_axis_c2h_tdata[463:460]   <= 'd4;     // ipv4_hdr.version;
            s_axis_c2h_tdata[459:456]   <= 'd5;     // IHL - Standard Length (5, 20B IP Header)
            s_axis_c2h_tdata[455:450]   <= '0;      // DSCP - Standard (0, No Priority)
            s_axis_c2h_tdata[449:448]   <= '0;      // ECN - Standard (Best Effort)
            s_axis_c2h_tdata[447:432]   <= ip_total_len_s1;
            s_axis_c2h_tdata[431:416]   <= '0;      // ID - 0, No Fragment for Control Packet
            s_axis_c2h_tdata[415:413]   <= 3'b010;  // -> Don't Fragment
            s_axis_c2h_tdata[412:400]   <= '0;      // -> 0 Fragment Offset
            s_axis_c2h_tdata[399:392]   <= 'd64;    // TTL
            s_axis_c2h_tdata[391:384]   <= 'h06;    // Protocol - TCP
            s_axis_c2h_tdata[383:368]   <= ip_checksum_s1;
            s_axis_c2h_tdata[367:336]   <= tcp_desc_s1.src_ip;
            s_axis_c2h_tdata[335:304]   <= tcp_desc_s1.dest_ip;

            // ------------------------------------------------------------------ TCP HEADER
            s_axis_c2h_tdata[303:288]   <= tcp_desc_s1.src_port;
            s_axis_c2h_tdata[287:272]   <= tcp_desc_s1.dest_port;
            s_axis_c2h_tdata[271:240]   <= tcp_desc_s1.seq_num;
            s_axis_c2h_tdata[239:208]   <= tcp_desc_s1.ack_num;
            s_axis_c2h_tdata[207:204]   <= 'd5;             // Data Offset
            s_axis_c2h_tdata[203:200]   <= '0;              // RESV
            s_axis_c2h_tdata[199:192]   <= {3'b0, tcp_desc_s1.csr_curr.ack, tcp_desc_s1.csr_curr.psh, tcp_desc_s1.csr_curr.rst, tcp_desc_s1.csr_curr.syn, tcp_desc_s1.csr_curr.fin};
            s_axis_c2h_tdata[191:176]   <= 16'hFFFF;        // Window
            s_axis_c2h_tdata[175:160]   <= tcp_checksum_s1;
            s_axis_c2h_tdata[159:144]   <= '0;              // Urgent
            s_axis_c2h_tdata[143:16]    <= tcp_payload_data_s1;
            s_axis_c2h_tdata[15:0]      <= '0;
        end
        else if (arp_valid) begin
            s_axis_c2h_frame_bytes <= 8'd42;
            s_axis_c2h_tdata[575:464] <= {arp_desc.dest_mac, arp_desc.src_mac, ETH_TYPE_ARP};

            s_axis_c2h_tdata[463:448] <= 16'h0001;
            s_axis_c2h_tdata[447:432] <= 16'h0800;

            s_axis_c2h_tdata[431:424] <= 8'd6;
            s_axis_c2h_tdata[423:416] <= 8'd4;

            s_axis_c2h_tdata[415:400] <= arp_desc.oper;

            s_axis_c2h_tdata[399:352] <= arp_desc.sha;
            s_axis_c2h_tdata[351:320] <= arp_desc.spa;

            s_axis_c2h_tdata[319:272] <= arp_desc.tha;
            s_axis_c2h_tdata[271:240] <= arp_desc.tpa;
            s_axis_c2h_tdata[239:0]   <= '0;
        end
        else begin
            s_axis_c2h_tdata       <= '0;
            s_axis_c2h_frame_bytes <= '0;

        end
    end
end

endmodule
