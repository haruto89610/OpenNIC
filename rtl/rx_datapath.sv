// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps

import packages::*;

module rx_datapath (
    input logic         clk,
    input logic         rst,

    input logic [7:0]   tdata,
    input logic         tvalid,
    output logic        tready,

    output logic        fifo_we,
    output logic        arp_fifo_we,
    output l2_hdr_t     l2_hdr,
    output arp_hdr_t    arp_hdr,
    output ipv4_hdr_t   ipv4_hdr,
    output tcp_hdr_t    tcp_hdr,
    output tcp_csr_t    tcp_csr,
    output udp_hdr_t    udp_hdr,
    output logic        udp_valid,

    output logic        sop_detected
);

localparam int IPV4_HDR_START      = 14;
localparam int IPV4_HDR_LEN        = 20;
localparam int UDP_HDR_LEN         = 8;
localparam int UDP_PAYLOAD_BYTES   = 56;
localparam int UDP_PAYLOAD_START   = IPV4_HDR_START + IPV4_HDR_LEN + UDP_HDR_LEN;

typedef enum logic [0:0] {
    IDLE,
    IN_FRAME
} state_t;

state_t        curr_t, next_t;
logic          sop;
logic          sfd_detect_comb;
logic          sfd_pending;
logic [55:0]   sfd_window;
logic [7:0]    tdata_q;
logic          tvalid_q;
logic          tvalid_d;
logic [15:0]   byte_cnt;
logic [15:0]   ethertype_r;
logic [7:0]    ip_proto_r;
logic          meta_valid;
logic          arp_meta_valid;

assign fifo_we  = meta_valid;
assign arp_fifo_we = arp_meta_valid;
assign tready   = 1'b1;

always_ff @(posedge clk) begin
    if (rst) begin
        tdata_q  <= '0;
        tvalid_q <= 1'b0;
    end else begin
        // Register incoming stream to avoid testbench/scheduler race artifacts.
        tdata_q  <= tdata;
        tvalid_q <= tvalid;
    end
end

// ------------------------------------ SOP LOGIC (fixed 8-bit)
always_comb begin
    sfd_detect_comb = 1'b0;

    if (tvalid_q && tready && curr_t == IDLE) begin
        if (sfd_window == 56'h55_55_55_55_55_55_55 && tdata_q == 8'hD5) begin
            sfd_detect_comb = 1'b1;
        end
    end
end

always_comb begin
    sop = 1'b0;

    // SOP on first payload byte after SFD; robust to bubbles via sfd_pending.
    if (curr_t == IDLE && sfd_pending && tvalid_q && tready) begin
        sop = 1'b1;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        sfd_window     <= '0;
        sfd_pending    <= 1'b0;
        sop_detected   <= 1'b0;
    end else begin
        if (tvalid_q && tready && curr_t == IDLE) begin
            sfd_window <= {sfd_window[47:0], tdata_q};
        end

        // Latch SFD detect until first payload handshake consumes it.
        if (curr_t != IDLE) begin
            sfd_pending <= 1'b0;
        end else if (sfd_pending && tvalid_q && tready) begin
            sfd_pending <= 1'b0;
        end else if (sfd_detect_comb) begin
            sfd_pending <= 1'b1;
        end

        sop_detected <= sop;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        tvalid_d <= 1'b0;
        byte_cnt <= '0;
    end
    else begin
        tvalid_d <= tvalid_q;

        if (tvalid_q && tready) begin
            if (curr_t == IDLE && sfd_pending) begin
                // First payload byte consumed while transitioning into IN_FRAME.
                byte_cnt <= 16'd1;
            end
            else if (curr_t == IN_FRAME) begin
                byte_cnt <= byte_cnt + 1'b1;
            end
        end
    end
end

// ------------------------------------ NEXT STATE LOGIC
always_ff @(posedge clk) begin
    if (rst)    curr_t <= IDLE;
    else        curr_t <= next_t;
end

always_comb begin
    next_t = curr_t;

    case (curr_t)
        IDLE : begin
            if (sfd_pending && tvalid_q && tready) begin
                next_t = IN_FRAME;
            end
        end
        IN_FRAME : begin
            if (~tvalid_q && tvalid_d) begin
                next_t = IDLE;
            end
        end
    endcase
end

always_ff @(posedge clk) begin
    if (rst) begin
        l2_hdr      <= '0;
        arp_hdr     <= '0;
        ipv4_hdr    <= '0;
        tcp_hdr     <= '0;
        tcp_csr     <= '0;
        udp_hdr     <= '0;
        ethertype_r <= '0;
        ip_proto_r  <= '0;
        meta_valid  <= 1'b0;
        arp_meta_valid <= 1'b0;
        udp_valid      <= 1'b0;
    end else if (tvalid_q && tready && (curr_t == IN_FRAME || (curr_t == IDLE && sfd_pending))) begin
        automatic logic [15:0]  ethertype_temp  = ethertype_r;
        automatic logic [7:0]   ip_proto_temp   = ip_proto_r;
        automatic int           pos;

        meta_valid      <= 1'b0;
        arp_meta_valid  <= 1'b0;
        udp_valid       <= 1'b0;
        pos = (curr_t == IDLE) ? 0 : int'(byte_cnt);

        if (pos >= 0) begin
            case (pos)
                0 : l2_hdr.dest_mac[47:40] <= tdata_q;
                1 : l2_hdr.dest_mac[39:32] <= tdata_q;
                2 : l2_hdr.dest_mac[31:24] <= tdata_q;
                3 : l2_hdr.dest_mac[23:16] <= tdata_q;
                4 : l2_hdr.dest_mac[15:8]  <= tdata_q;
                5 : l2_hdr.dest_mac[7:0]   <= tdata_q;

                6 :  l2_hdr.src_mac[47:40] <= tdata_q;
                7 :  l2_hdr.src_mac[39:32] <= tdata_q;
                8 :  l2_hdr.src_mac[31:24] <= tdata_q;
                9 :  l2_hdr.src_mac[23:16] <= tdata_q;
                10 : l2_hdr.src_mac[15:8]  <= tdata_q;
                11 : l2_hdr.src_mac[7:0]   <= tdata_q;

                12 : begin
                    l2_hdr.ethertype[15:8]  <= tdata_q;
                    ethertype_r[15:8]       <= tdata_q;
                    ethertype_temp[15:8]    = tdata_q;
                end
                13 : begin
                    l2_hdr.ethertype[7:0]   <= tdata_q;
                    ethertype_r[7:0]        <= tdata_q;
                    ethertype_temp[7:0]     = tdata_q;
                end
                23 : begin
                    ip_proto_temp           = tdata_q;
                end
            endcase

            if (ethertype_temp == ETH_TYPE_ARP) begin
                case (pos)
                    14 : arp_hdr.htype[15:8] <= tdata_q;
                    15 : arp_hdr.htype[7:0]  <= tdata_q;

                    16 : arp_hdr.ptype[15:8] <= tdata_q;
                    17 : arp_hdr.ptype[7:0]  <= tdata_q;

                    18 : arp_hdr.hlen        <= tdata_q;
                    19 : arp_hdr.plen        <= tdata_q;

                    20 : arp_hdr.oper[15:8]  <= tdata_q;
                    21 : arp_hdr.oper[7:0]   <= tdata_q;

                    22 : arp_hdr.sha[47:40]  <= tdata_q;
                    23 : arp_hdr.sha[39:32]  <= tdata_q;
                    24 : arp_hdr.sha[31:24]  <= tdata_q;
                    25 : arp_hdr.sha[23:16]  <= tdata_q;
                    26 : arp_hdr.sha[15:8]   <= tdata_q;
                    27 : arp_hdr.sha[7:0]    <= tdata_q;

                    28 : arp_hdr.spa[31:24]  <= tdata_q;
                    29 : arp_hdr.spa[23:16]  <= tdata_q;
                    30 : arp_hdr.spa[15:8]   <= tdata_q;
                    31 : arp_hdr.spa[7:0]    <= tdata_q;

                    32 : arp_hdr.tha[47:40]  <= tdata_q;
                    33 : arp_hdr.tha[39:32]  <= tdata_q;
                    34 : arp_hdr.tha[31:24]  <= tdata_q;
                    35 : arp_hdr.tha[23:16]  <= tdata_q;
                    36 : arp_hdr.tha[15:8]   <= tdata_q;
                    37 : arp_hdr.tha[7:0]    <= tdata_q;

                    38 : arp_hdr.tpa[31:24]  <= tdata_q;
                    39 : arp_hdr.tpa[23:16]  <= tdata_q;
                    40 : arp_hdr.tpa[15:8]   <= tdata_q;
                    41 : begin
                        arp_hdr.tpa[7:0] <= tdata_q;
                        arp_meta_valid   <= 1'b1;
                    end
                endcase
            end

            if (ethertype_temp == ETH_TYPE_IPV4) begin
                case (pos)
                    14 : begin
                        ipv4_hdr.version <= tdata_q[7:4];
                        ipv4_hdr.ihl     <= tdata_q[3:0];
                    end
                    15 : begin
                        ipv4_hdr.dscp <= tdata_q[7:2];
                        ipv4_hdr.ecn  <= tdata_q[1:0];
                    end
                    16 : ipv4_hdr.total_len[15:8] <= tdata_q;
                    17 : ipv4_hdr.total_len[7:0]  <= tdata_q;

                    18 : ipv4_hdr.id[15:8] <= tdata_q;
                    19 : ipv4_hdr.id[7:0]  <= tdata_q;

                    20 : begin
                        ipv4_hdr.flags          <= tdata_q[7:5];
                        ipv4_hdr.frag_off[12:8] <= tdata_q[4:0];
                    end

                    21 : ipv4_hdr.frag_off[7:0]   <= tdata_q;
                    22 : ipv4_hdr.ttl             <= tdata_q;

                    23 : begin
                        ipv4_hdr.protocol   <= tdata_q;
                        ip_proto_r          <= tdata_q;
                    end

                    24 : ipv4_hdr.hdr_checksum[15:8] <= tdata_q;
                    25 : ipv4_hdr.hdr_checksum[7:0]  <= tdata_q;

                    26 : ipv4_hdr.src_ip[31:24]   <= tdata_q;
                    27 : ipv4_hdr.src_ip[23:16]   <= tdata_q;
                    28 : ipv4_hdr.src_ip[15:8]    <= tdata_q;
                    29 : ipv4_hdr.src_ip[7:0]     <= tdata_q;

                    30 : ipv4_hdr.dest_ip[31:24]  <= tdata_q;
                    31 : ipv4_hdr.dest_ip[23:16]  <= tdata_q;
                    32 : ipv4_hdr.dest_ip[15:8]   <= tdata_q;
                    33 : ipv4_hdr.dest_ip[7:0]    <= tdata_q;
                endcase
            end

            if (ip_proto_temp == IP_PROTO_TCP) begin
                case (pos)
                    34 : tcp_hdr.src_port[15:8]   <= tdata_q;
                    35 : tcp_hdr.src_port[7:0]    <= tdata_q;
                    36 : tcp_hdr.dest_port[15:8]  <= tdata_q;
                    37 : tcp_hdr.dest_port[7:0]   <= tdata_q;
                    38 : tcp_hdr.seq_num[31:24]   <= tdata_q;
                    39 : tcp_hdr.seq_num[23:16]   <= tdata_q;
                    40 : tcp_hdr.seq_num[15:8]    <= tdata_q;
                    41 : tcp_hdr.seq_num[7:0]     <= tdata_q;
                    42 : tcp_hdr.ack_num[31:24]   <= tdata_q;
                    43 : tcp_hdr.ack_num[23:16]   <= tdata_q;
                    44 : tcp_hdr.ack_num[15:8]    <= tdata_q;
                    45 : tcp_hdr.ack_num[7:0]     <= tdata_q;

                    46 : begin
                        tcp_hdr.data_off <= tdata_q[7:4];
                        tcp_hdr.resv     <= tdata_q[3:0];
                    end
                    47 : begin
                        tcp_hdr.csr <= tdata_q;
                        tcp_csr.fin <= tdata_q[0];
                        tcp_csr.syn <= tdata_q[1];
                        tcp_csr.rst <= tdata_q[2];
                        tcp_csr.psh <= tdata_q[3];
                        tcp_csr.ack <= tdata_q[4];
                    end

                    48 : tcp_hdr.window[15:8]     <= tdata_q;
                    49 : tcp_hdr.window[7:0]      <= tdata_q;
                    50 : tcp_hdr.checksum[15:8]   <= tdata_q;
                    51 : tcp_hdr.checksum[7:0]    <= tdata_q;
                    52 : tcp_hdr.urgent[15:8]     <= tdata_q;
                    53 : begin
                        tcp_hdr.urgent[7:0] <= tdata_q;
                        meta_valid          <= 1'b1;
                    end
                endcase
            end

            if (ip_proto_temp == IP_PROTO_UDP) begin
                case (pos)
                    34 : udp_hdr.src_port[15:8]     <= tdata_q;
                    35 : udp_hdr.src_port[7:0]      <= tdata_q;
                    36 : udp_hdr.dest_port[15:8]    <= tdata_q;
                    37 : udp_hdr.dest_port[7:0]     <= tdata_q;
                    38 : udp_hdr.length[15:8]       <= tdata_q;
                    39 : udp_hdr.length[7:0]        <= tdata_q;
                    40 : udp_hdr.checksum[15:8]     <= tdata_q;
                    41 : udp_hdr.checksum[7:0]      <= tdata_q;
                endcase

                if (pos >= UDP_PAYLOAD_START && pos < UDP_PAYLOAD_START + UDP_PAYLOAD_BYTES) begin
                    automatic int payload_pos;
                    payload_pos = pos - UDP_PAYLOAD_START;
                    udp_hdr.payload[((UDP_PAYLOAD_BYTES - payload_pos) * 8) - 1 -: 8] <= tdata_q;

                    if (payload_pos == UDP_PAYLOAD_BYTES - 1) begin
                        udp_valid <= 1'b1;
                    end
                end
            end
        end
    end else begin
        meta_valid      <= 1'b0;
        arp_meta_valid  <= 1'b0;
        udp_valid       <= 1'b0;
    end
end

endmodule
