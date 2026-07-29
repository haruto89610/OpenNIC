// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps


import packages::*;
module tcp_top_level(
    input logic             clk,
    input logic             rst,

    input logic             header_valid,
    input l2_hdr_t          rx_l2_hdr,
    input ipv4_hdr_t        rx_ipv4_hdr,
    input tcp_hdr_t         rx_tcp_hdr,
    input tcp_csr_t         rx_tcp_csr,

    input req_t             app_req_in,
    input logic [127:0]     payload_data,

    output logic            arp_req_valid,
    output logic [31:0]     arp_req_dest_ip,
    input logic             arp_rep_valid,
    input logic [31:0]      arp_rep_dest_ip,
    input logic [47:0]      arp_rep_dest_mac,

    input logic             tx_datapath_ready,
    output logic            tx_desc_valid,

    input logic             req_fifo_valid,
    output logic            grant_payload,

    output logic            has_payload,
    output logic [15:0]     payload_len_out,
    output logic [127:0]    payload_data_out,

    output tcp_tx_desc_t    tx_desc
);

localparam int HEADER_WIDTH = $bits(header_t);
localparam int HEADER_PAD   = 512 - HEADER_WIDTH;

logic           tcb_valid;
logic [5:0]     tcb_addr;

logic           tcb_addr_is_rx;

logic           tcb_valid_rx;
logic [5:0]     tcb_addr_rx;

logic           tcb_valid_app;
logic [5:0]     tcb_addr_app;

logic           cache_full;

logic [63:0]    pending_payload_tx;

logic           mem_tcb_valid;
logic [5:0]     mem_tcb_addr;

header_t        header_din;
logic           header_fifo_empty;
header_t        header_dout;

logic           payload_req;

logic           grant_rx;

logic [127:0]   cache_input_tuple;
logic           read_miss;
logic           read_miss_d;

logic           invalidate;
logic           tcb_b_valid_o;
tcb_t           tcb_b_out;

logic           tcp_ctrl_valid;
logic [5:0]     tcp_ctrl_addr;

logic           cancel_rto;

logic           tcb_rto_addr_out_valid;
logic [5:0]     tcb_rto_addr_out;

logic           ack_valid;
logic [5:0]     ack_addr;
logic [31:0]    ack_snd_una;

// SUBSECTION: RX FIFO
fifo #(
    .WIDTH  ($bits(header_t)),
    .DEPTH  (64),
    .FWFT   (1)
) header_queue_i (
    .clk        (clk),
    .srst       (rst),
    .din        (header_din),
    .wr_en      (header_valid),
    .rd_en      (grant_rx),
    .dout       (header_dout),
    .full       (),
    .empty      (header_fifo_empty),
    .valid      (),
    .overflow   (),
    .wr_rst_busy(),
    .rd_rst_busy()
);

cache_arbiter cache_arbiter_i (
    .clk            (clk),
    .rst            (rst),

    .tcb_valid      (tcb_valid),
    .cache_full     (cache_full),

    .rx_empty       (header_fifo_empty),
    .payload_empty  (!req_fifo_valid || !memory_payload_ready),

    .grant_rx       (grant_rx),
    .grant_payload  (grant_payload)
);

cache cache_i (
    .clk            (clk),
    .rst            (rst),

    .read           (grant_rx || grant_payload),
    .alloc_ena      ((grant_rx && header_dout.tcp_csr.syn) || (grant_payload && app_req_in.req_type == TCP_REQ_CONNECT_SEND)),

    .input_tuple    (cache_input_tuple),

    .read_miss      (read_miss),
    .tcb_full       (cache_full),
    .input_addr     (),
    .tcb_addr_valid (tcb_valid),
    .tcb_addr       (tcb_addr),

    .invalidate     (invalidate),
    .invalidate_addr(tcp_ctrl_addr)
);

logic memory_payload_ready;

always_comb begin
    mem_tcb_valid = tcb_valid_app;
    mem_tcb_addr  = tcb_addr_app;

    if (invalidate) begin
        mem_tcb_valid = 1'b1;
        mem_tcb_addr  = tcp_ctrl_addr;
    end
end

tcp_memory_controller u_tcp_memory_controller (
    .clk                    (clk),
    .rst                    (rst),
    // ------------------------------------- CACHE OUTPUT
    .invalidate             (invalidate),
    .tcb_valid              (mem_tcb_valid),
    .tcb_addr               (mem_tcb_addr),

    .pending_payload_tx     (pending_payload_tx),
    // ------------------------------------- ACK ADVANCE
    .ack_valid              (ack_valid),
    .ack_ready              (),
    .ack_addr               (ack_addr),
    .ack_snd_una            (ack_snd_una),
    // Dual purpose port for init and ack

    // ------------------------------------- PAYLOAD WRITE / READ
    .payload_valid          (grant_payload),
    .payload_ready          (memory_payload_ready),
    .payload_len            (app_req_in.payload_len),
    .payload                (payload_data),
    .payload_req_valid_i    (payload_req),
    .payload_req_addr       (tcp_ctrl_addr),
    .retx                   (1'b0),
    .payload_req_valid_o    (has_payload),
    .payload_req_len        (payload_len_out),
    .payload_req_out        (payload_data_out)
);

tcb_mgr tcb_mgr_i (
    .clk                (clk),
    .rst                (rst),

    .read_miss          (read_miss),
    .header_out         (header_dout),

    .tcb_valid_rx       (tcb_valid_rx),
    .tcb_addr_rx        (tcb_addr_rx),

    .tcb_valid_tx       (tcb_rto_addr_out_valid),
    .tcb_addr_tx        (tcb_rto_addr_out),

    .tcb_valid_app      (forward_valid),
    .tcb_addr_app       (forward_meta.tcb_addr),
    .payload_len        (forward_meta.payload_len),
    .pending_payload_tx (pending_payload_tx),

    .tcb_meta_app       (forward_meta),

    .cancel_rto         (cancel_rto),
    .invalidate         (invalidate),
    .tcp_ctrl_valid     (tcp_ctrl_valid),

    .tcp_ctrl_addr      (tcp_ctrl_addr),
    .tcb_valid_tx_out   (tcb_b_valid_o),
    .tcb_out_tx         (tcb_b_out),

    .payload_req        (payload_req),

    .tx_desc_valid_out  (tx_desc_valid),
    .tx_desc_out        (tx_desc),

    .ack_valid          (ack_valid),
    .ack_addr           (ack_addr),
    .ack_snd_una        (ack_snd_una)
);

rto rto_i (
    .clk    (clk),
    .rst    (rst),

    .write              (tcb_b_valid_o && (|tcb_b_out.csr_curr)),
    .cancel_rto         (cancel_rto),

    .tcb_addr_in        (tcp_ctrl_addr),
    .tcb_data_in        (tcb_b_out),

    .tx_datapath_ready  (tx_datapath_ready),
    .tcb_addr_out_valid (tcb_rto_addr_out_valid),
    .tcb_addr_out       (tcb_rto_addr_out)
);


assign tcb_valid_rx   = tcb_valid && tcb_addr_is_rx;
assign tcb_addr_rx    = tcb_addr;

assign tcb_valid_app  = tcb_valid && !tcb_addr_is_rx;
assign tcb_addr_app   = tcb_addr;

assign arp_req_valid   = tcb_valid_app && read_miss_d;
assign arp_req_dest_ip = app_req_q.dest_ip;

always_ff @(posedge clk) begin
    if (rst) begin
        read_miss_d <= '0;
    end
    else begin
        if (read_miss) begin
            read_miss_d <= '1;
        end
        else if (tcb_valid) begin
            read_miss_d <= '0;
        end
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        tcb_addr_is_rx <= '0;
    end
    else begin
        if (grant_payload) begin
            tcb_addr_is_rx <= '0;
        end
        else if (grant_rx) begin
            tcb_addr_is_rx <= '1;
        end
    end
end

always_comb begin
    cache_input_tuple = 'x;

    if (grant_payload) begin
        cache_input_tuple = {app_req_in.dest_ip,
                            app_req_in.src_ip,
                            app_req_in.dest_port,
                            app_req_in.src_port};
    end
    else if (grant_rx) begin
        cache_input_tuple = {header_dout.ipv4_hdr.src_ip,
                            header_dout.ipv4_hdr.dest_ip,
                            header_dout.tcp_hdr.src_port,
                            header_dout.tcp_hdr.dest_port};
    end
end

always_comb begin
    header_din = '0;

    if (header_valid) begin
        header_din.l2_hdr    = rx_l2_hdr;
        header_din.ipv4_hdr  = rx_ipv4_hdr;
        header_din.tcp_hdr   = rx_tcp_hdr;
        header_din.tcp_csr   = rx_tcp_csr;
    end
end

// SECTION: APP REQUEST
typedef struct packed {
    logic           valid;
    logic [5:0]     tcb_addr;
    req_t           req;
    logic [31:0]    next_hop_ip;
} pending_arp_t;

localparam req_t REQ_DEFAULT = '{
    req_type    : TCP_REQ_CONNECT_SEND,
    dest_ip     : '0,
    src_ip      : '0,
    src_port    : '0,
    dest_port   : '0,
    payload_len : '0
};

localparam pending_arp_t PENDING_ARP_DEFAULT = '{
    valid       : 1'b0,
    tcb_addr    : '0,
    req         : REQ_DEFAULT,
    next_hop_ip : '0
};

localparam tcp_arp_t TCP_ARP_DEFAULT = '{
    req_type    : TCP_REQ_CONNECT_SEND,
    tcb_addr    : '0,
    dest_mac    : '0,
    dest_ip     : '0,
    src_ip      : '0,
    src_port    : '0,
    dest_port   : '0,
    payload_len : '0
};

logic           forward_valid;
tcp_arp_t       forward_meta;

logic [2:0]     next_free;
pending_arp_t   pending_arp [8];
logic           pending_arp_hit;

// SUBSECTION: FORWARD
req_t app_req_q;

always_ff @(posedge clk) begin
    if (rst) begin
        app_req_q <= REQ_DEFAULT;
    end
    else if (grant_payload) begin
        app_req_q <= app_req_in;
    end
end

always_comb begin
    forward_valid   = '0;
    forward_meta    = TCP_ARP_DEFAULT;

    if (tcb_valid_app && !read_miss_d && app_req_q.req_type == TCP_REQ_FAST_SEND && !pending_arp_hit) begin
        forward_valid               = 1'b1;
        forward_meta                = TCP_ARP_DEFAULT;
        forward_meta.req_type       = app_req_q.req_type;
        forward_meta.tcb_addr       = tcb_addr_app;
        forward_meta.payload_len    = app_req_q.payload_len;
    end
    else if (arp_rep_valid) begin
        for (int i = 0; i < 8; i++) begin
            if (pending_arp[i].valid && pending_arp[i].next_hop_ip == arp_rep_dest_ip) begin
                forward_valid               = 1'b1;
                forward_meta.req_type       = pending_arp[i].req.req_type;
                forward_meta.tcb_addr       = pending_arp[i].tcb_addr;
                forward_meta.dest_mac       = arp_rep_dest_mac;
                forward_meta.dest_ip        = pending_arp[i].req.dest_ip;
                forward_meta.src_ip         = pending_arp[i].req.src_ip;
                forward_meta.src_port       = pending_arp[i].req.src_port;
                forward_meta.dest_port      = pending_arp[i].req.dest_port;
                forward_meta.payload_len    = pending_arp[i].req.payload_len;
            end
        end
    end
end

// SUBSECTION: ARP PENDING TABLE
// Capacity exhaustion has no backpressure signal; if all entries are valid,
// next_free remains zero and the next request overwrites entry zero.
always_comb begin
    next_free = '0;

    for (int i = 0; i < 8; i++) begin
        if (!pending_arp[i].valid) begin
            next_free = i[2:0];
        end
    end
end

always_comb begin
    pending_arp_hit = 1'b0;

    for (int i = 0; i < 8; i++) begin
        if (pending_arp[i].valid && pending_arp[i].next_hop_ip == app_req_q.dest_ip) begin
            pending_arp_hit = 1'b1;
        end
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        pending_arp <= '{default : PENDING_ARP_DEFAULT};
    end
    else begin
        // SUBSECTION: ARP REQUEST
        if (tcb_valid_app && read_miss_d && app_req_q.req_type == TCP_REQ_CONNECT_SEND) begin
            pending_arp[next_free].valid        <= 1'b1;
            pending_arp[next_free].tcb_addr     <= tcb_addr_app;
            pending_arp[next_free].req          <= app_req_q;
            pending_arp[next_free].next_hop_ip  <= app_req_q.dest_ip;
        end

        // SUBSECTION: ARP REPLY
        if (arp_rep_valid) begin
            for (int i = 0; i < 8; i++) begin
                if (pending_arp[i].next_hop_ip == arp_rep_dest_ip) begin
                    pending_arp[i].valid    <= 1'b0;
                end
            end
        end
    end
end
endmodule
