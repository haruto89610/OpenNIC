// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps


import packages::*;
module arp_top_level(
    input logic             clk,
    input logic             rst,

    // APP ARP REQUEST
    input logic             arp_req_valid,
    input logic [31:0]      arp_req_dest_ip,
    output logic            arp_rep_valid,
    output logic [31:0]     arp_rep_dest_ip,
    output logic [47:0]     arp_rep_dest_mac,

    // ARP RX HEADER PATH
    input logic             arp_header_valid,
    input arp_hdr_t         arp_header_in,

    // PASSIVE LEARN PATH
    input logic             learn_ipv4_valid,
    input l2_hdr_t          learn_l2_hdr,
    input ipv4_hdr_t        learn_ipv4_hdr,

    // ARP TX DESCRIPTOR OUTPUT
    output logic            arp_tx_desc_valid,
    output arp_tx_desc_t    arp_tx_desc
);

localparam int ARP_HDR_WIDTH = $bits(arp_hdr_t);
localparam int ARP_Q_DEPTH   = 16;

arp_hdr_t       arp_header_out;
logic           arp_queue_pop;
logic           arp_queue_empty;

logic           path;
logic           valid_in;
arp_hdr_t       arp_hdr;
logic [31:0]    ip_addr_in;

fifo #(
    .WIDTH  (ARP_HDR_WIDTH),
    .DEPTH  (ARP_Q_DEPTH),
    .FWFT   (1)
) arp_queue_i (
    .clk        (clk),
    .srst       (rst),
    .din        (arp_header_in),
    .wr_en      (arp_header_valid),
    .rd_en      (arp_queue_pop),
    .dout       (arp_header_out),
    .full       (),
    .empty      (arp_queue_empty),
    .valid      (),
    .overflow   (),
    .wr_rst_busy(),
    .rd_rst_busy()
);

arp_ctrl arp_ctrl_i (
    .clk            (clk),
    .rst            (rst),
    .path           (path),
    .valid_in       (valid_in),
    .ip_addr_in     (ip_addr_in),
    .arp_hdr        (arp_hdr),

    .pkt_valid      (learn_ipv4_valid),
    .l2_hdr         (learn_l2_hdr),
    .ipv4_hdr       (learn_ipv4_hdr),

    .arp_valid      (arp_tx_desc_valid),
    .arp_desc       (arp_tx_desc),

    .mac_valid      (arp_rep_valid),
    .resolved_ip    (arp_rep_dest_ip),
    .resolved_mac   (arp_rep_dest_mac)
);

always_comb begin
    path            = '0;
    valid_in        = '0;
    arp_hdr         = '0;
    ip_addr_in      = '0;
    arp_queue_pop   = '0;

    if (!arp_queue_empty) begin
        path            = 1'b1;
        valid_in        = 1'b1;
        arp_hdr         = arp_header_out;
        ip_addr_in      = '0;
        arp_queue_pop   = 1'b1;
    end
    else if (arp_req_valid) begin
        path            = 1'b0;
        valid_in        = 1'b1;
        arp_hdr         = '0;
        ip_addr_in      = arp_req_dest_ip;
    end
end


endmodule
