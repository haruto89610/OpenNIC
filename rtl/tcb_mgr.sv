// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps

import packages::*;
module tcb_mgr(
    input logic         clk,
    input logic         rst,

    input logic         read_miss,
    input header_t      header_out,

    // RX DATAPATH
    input logic         tcb_valid_rx,
    input logic [5:0]   tcb_addr_rx,

    // RTO / TX READ PATH
    input logic         tcb_valid_tx,
    input logic [5:0]   tcb_addr_tx,

    // APP / PAYLOAD LOOKUP PATH
    input logic         tcb_valid_app,
    input logic [5:0]   tcb_addr_app,
    input logic [15:0]  payload_len,
    input logic [63:0]  pending_payload_tx,

    input tcp_arp_t     tcb_meta_app,

    output logic        cancel_rto,
    output logic        invalidate,
    output logic        tcp_ctrl_valid,

    output logic [5:0]  tcp_ctrl_addr,
    output logic        tcb_valid_tx_out,
    output tcb_t        tcb_out_tx,

    output logic        payload_req,

    output logic        tx_desc_valid_out,
    output tcp_tx_desc_t    tx_desc_out,

    // ACK UPDATE
    output logic        ack_valid,
    output logic [5:0]  ack_addr,
    output logic [31:0] ack_snd_una
);

logic [63:0]    tcb_alloc;
logic [63:0]    lock;

header_t        header_out_d;

logic           new_packet;
logic           new_packet_d;
logic           new_packet_d2;
tcb_t           new_packet_tcb;

// Router split
logic           route_tcp_valid;
logic           route_app_valid;
logic           route_establish_valid;

// tcp_ctrl writeback
logic           ctrl_valid;
logic [5:0]     ctrl_addr;
tcb_t           ctrl_tcb;

// establish_ctrl writeback (aligned to match ctrl output timing)
logic           establish_valid_d;
logic           establish_valid_q;
logic [5:0]     establish_addr_q;
tcb_t           establish_tcb_d;
tcb_t           establish_tcb_q;

// app_ctrl writeback
logic           app_valid;
logic [5:0]     app_addr;
tcb_t           app_tcb;

// Merged writeback path
logic           wb_commit_valid;
logic [5:0]     wb_commit_addr;
tcb_t           wb_commit_tcb;

// --------------------------------------------- WRITEBACK ports
// Path:
//      0 - TX
//      1 - RX
//      2 - APP
logic [1:0]     path;
logic [1:0]     wb_path_d;
logic           wb_valid;
logic           wb_valid_d;
logic [5:0]     wb_addr;
logic [5:0]     wb_addr_d;

// --------------------------------------------- DESCRIPTORS
logic           tx_desc_valid_in;
tcp_tx_desc_t   tx_desc_in;

tcb_t           tcb_b_out;

writeback wb_i (
    .clk            (clk),
    .rst            (rst),

    .tcb_alloc      (tcb_alloc),
    .tcb_ready      (1'b1),

    .tcb_valid_rx   (tcb_valid_rx),
    .tcb_addr_rx    (tcb_addr_rx),

    .tcb_valid_tx   (tcb_valid_tx),
    .tcb_addr_tx    (tcb_addr_tx),

    .tcb_valid_app  (tcb_valid_app),
    .tcb_addr_app   (tcb_addr_app),

    .tcb_valid_pl   (tcb_valid_pl),
    .tcb_addr_pl    (tcb_addr_pl),

    .path           (path),
    .valid          (wb_valid),
    .addr           (wb_addr)
);

router router_i (
    .valid_in               (wb_valid_d),
    .tcb_in                 (tcb_b_out),
    .header_in              (header_out_d),
    .path                   (wb_path_d),

    .tcp_ctrl_valid         (route_tcp_valid),
    .app_ctrl_valid         (route_app_valid),
    .establish_ctrl_valid   (route_establish_valid)
);

tcp_ctrl tcp_ctrl_i (
    .clk                (clk),
    .rst                (rst),
    .path               (wb_path_d[0]),
    .valid_in           ((route_tcp_valid) || new_packet_d2),
    .addr_in            (wb_addr_d),
    .tcb_in             (new_packet_d2 ? new_packet_tcb : tcb_b_out),
    .new_packet_d       (new_packet_d2),
    .rx_csr             (header_out_d.tcp_csr),
    .header_data        (header_out_d),
    .cancel_rto_temp    (cancel_rto),
    .invalidate_temp    (invalidate),
    .valid_out_temp     (ctrl_valid),
    .addr_out_temp      (ctrl_addr),
    .tcb_out_temp       (ctrl_tcb)
);

establish_ctrl establish_ctrl_i (
    .clk        (clk),
    .rst        (rst),
    .path       (wb_path_d[0]),
    .valid_in   (route_establish_valid),
    .addr_in    (wb_addr_d),

    .tcb_in     (tcb_b_out),
    .header_data(header_out_d),
    .valid_out  (establish_valid_d),
    .tcb_out    (establish_tcb_d),

    .ack_valid  (ack_valid),
    .ack_addr   (ack_addr),
    .ack_snd_una(ack_snd_una)
);

app_ctrl app_ctrl_i (
    .clk            (clk),
    .rst            (rst),
    .valid_in       (route_app_valid),
    .path           (wb_path_d),
    .tcb_addr_in    (wb_addr_d),

    .payload_len    (wb_path_d == 2'd2 ? payload_len : 16'd16),

    .tcb_in         (tcb_b_out),
    .tcb_valid_app  (tcb_valid_app),
    .tcb_meta_app   (tcb_meta_app),

    .valid_out      (app_valid),
    .tcb_addr_out   (app_addr),
    .tcb_out        (app_tcb)
);

tx_desc_issue tx_desc_issue_i (
    .clk                (clk),
    .rst                (rst),
    .invalidate         (invalidate),
    .tx_desc_valid_in   (tx_desc_valid_in),
    .tx_desc_in         (tx_desc_in),
    .tx_desc_valid_out  (tx_desc_valid_out),
    .tx_desc_out        (tx_desc_out)
);

tcb tcb_i (
    .clk        (clk),
    .rst        (rst),
    .addra      (wb_commit_addr),
    .wea        (wb_commit_valid),
    .dina       (invalidate ? '0 : wb_commit_tcb),
    .douta      (),
    .addrb      (wb_addr),
    .doutb      (tcb_b_out)
);

// New-flow classification occurs before tcp_ctrl processing; post-control
// classification requires additional regression coverage.
assign new_packet = read_miss && (header_out.tcp_csr == CSR_SYN);

// --------------------------------- DELAYS / ALIGNMENT
always_ff @(posedge clk) begin
    wb_path_d   <= path;

    wb_valid_d  <= wb_valid;

    wb_addr_d   <= wb_addr;

    new_packet_d    <= new_packet;
    new_packet_d2   <= new_packet_d;

    header_out_d    <= header_out;
end

always_ff @(posedge clk) begin
    establish_valid_q <= establish_valid_d;

    if (rst) begin
        establish_addr_q <= '0;
        establish_tcb_q  <= '0;
    end
    else if (establish_valid_d) begin
        establish_addr_q <= wb_addr_d;
        establish_tcb_q  <= establish_tcb_d;
    end
end

// SECTION: PAYLOAD RR ARBITER
logic           tcb_valid_pl;
logic [5:0]     tcb_addr_pl;
logic [5:0]     tcb_addr_pl_last;
logic [63:0]    pl_inflight;
logic [63:0]    pending_payload_candidates;

assign pending_payload_candidates = pending_payload_tx & ~pl_inflight;

always_comb begin
    tcb_valid_pl = 1'b0;
    tcb_addr_pl  = '0;

    for (int i = 0; i < 64; i++) begin
        automatic logic [5:0] idx;
        idx = tcb_addr_pl_last + i[5:0];

        if (!tcb_valid_pl && pending_payload_candidates[idx]) begin
            tcb_valid_pl    = 1'b1;
            tcb_addr_pl     = idx[5:0];
        end
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        tcb_addr_pl_last    <= '0;
        pl_inflight         <= '0;
    end
    else begin
        if (tcb_valid_pl) begin
            tcb_addr_pl_last            <= tcb_addr_pl + 1'b1;
            pl_inflight[tcb_addr_pl]    <= 1'b1;
        end

        if (payload_req && wb_path_d == 2'd3) begin
            pl_inflight[wb_addr_d]  <= 1'b0;
        end
        else if (wb_valid_d && wb_path_d == 2'd3 && !route_app_valid) begin
            pl_inflight[wb_addr_d]  <= 1'b0;
        end
    end
end

// --------------------------------- OUTPUT / MERGE LOGIC
always_comb begin
    wb_commit_valid = '0;
    wb_commit_addr  = '0;
    wb_commit_tcb   = '0;

    payload_req     = '0;

    // tcp_ctrl gets priority if both are ever asserted together
    if (ctrl_valid) begin
        wb_commit_valid = 1'b1;
        wb_commit_addr  = ctrl_addr;
        wb_commit_tcb   = ctrl_tcb;
    end
    else if (establish_valid_q) begin
        wb_commit_valid = 1'b1;
        wb_commit_addr  = establish_addr_q;
        wb_commit_tcb   = establish_tcb_q;
    end
    else if (app_valid) begin
        payload_req     = app_tcb.csr_curr.psh && (app_tcb.len_num != '0);

        wb_commit_valid = 1'b1;
        wb_commit_addr  = app_addr;
        wb_commit_tcb   = app_tcb;
    end

    tcp_ctrl_valid  = wb_commit_valid;
    tcp_ctrl_addr   = wb_commit_addr;
    tcb_out_tx      = wb_commit_tcb;
    tcb_valid_tx_out= wb_commit_valid &&
                      ~cancel_rto &&
                      ~invalidate &&
                      (|wb_commit_tcb.csr_curr) &&
                      (wb_commit_tcb.csr_curr.syn || wb_commit_tcb.csr_curr.fin || (wb_commit_tcb.csr_curr.psh && wb_commit_tcb.len_num != '0));

    tx_desc_valid_in    = wb_commit_valid && (|wb_commit_tcb.csr_curr);
    tx_desc_in.dest_mac = wb_commit_tcb.dest_mac;
    tx_desc_in.src_mac  = wb_commit_tcb.src_mac;
    tx_desc_in.dest_ip  = wb_commit_tcb.dest_ip;
    tx_desc_in.src_ip   = wb_commit_tcb.src_ip;
    tx_desc_in.dest_port= wb_commit_tcb.dest_port;
    tx_desc_in.src_port = wb_commit_tcb.src_port;
    tx_desc_in.csr_curr = wb_commit_tcb.csr_curr;

    tx_desc_in.seq_num  = wb_commit_tcb.seq_num;
    tx_desc_in.ack_num  = wb_commit_tcb.ack_num;
end

// --------------------------------- NEW PACKET TCB LOGIC
always_ff @(posedge clk) begin
    if (rst) begin
        new_packet_tcb <= '0;
    end
    else if (new_packet_d && tcb_valid_rx) begin
        new_packet_tcb.dest_mac       <= header_out_d.l2_hdr.dest_mac;
        new_packet_tcb.src_mac        <= header_out_d.l2_hdr.src_mac;
        new_packet_tcb.dest_ip        <= header_out_d.ipv4_hdr.dest_ip;
        new_packet_tcb.src_ip         <= header_out_d.ipv4_hdr.src_ip;
        new_packet_tcb.dest_port      <= header_out_d.tcp_hdr.dest_port;
        new_packet_tcb.src_port       <= header_out_d.tcp_hdr.src_port;

        new_packet_tcb.seq_num        <= header_out_d.tcp_hdr.seq_num;
        new_packet_tcb.ack_num        <= header_out_d.tcp_hdr.ack_num;
        // Initial send sequence numbers are fixed; randomized or hashed ISS
        // generation is not implemented.
        new_packet_tcb.snd_una        <= 'd0;
        new_packet_tcb.snd_nxt        <= 'd1;
        new_packet_tcb.rcv_nxt        <= 'd0;

        new_packet_tcb.next_send_time <= '0;
        new_packet_tcb.backoff_exp    <= '0;
        new_packet_tcb.csr_curr       <= '0;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        tcb_alloc <= '0;
    end
    else begin
        if (invalidate) begin
            tcb_alloc[wb_commit_addr]   <= 1'b0;
        end
        else if (tcb_valid_rx) begin
            tcb_alloc[tcb_addr_rx]      <= 1'b1;
        end
        else if (tcb_valid_app) begin
            tcb_alloc[tcb_addr_app]     <= 1'b1;
        end
    end
end

// --------------------------------- LOCK LOGIC
always_ff @(posedge clk) begin
    if (rst) begin
        lock <= '0;
    end
    else begin
        // OBTAIN LOCK FOR READ
        if (wb_valid) begin
            lock[wb_addr] <= 1'b1;
        end

        // RELEASE LOCK FOR WRITE
        if (wb_commit_valid) begin
            lock[wb_commit_addr] <= 1'b0;
        end
    end
end

endmodule
