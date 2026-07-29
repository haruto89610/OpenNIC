// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps

import packages::*;
module top_level #(
    parameter logic [47:0] FPGA_MAC = 48'h00_12_34_56_78_90,
    parameter logic [31:0] FPGA_IP  = {8'd192, 8'd168, 8'd0, 8'd10}
) (
    input logic         clk_p,
    input logic         clk_n,
    input logic         rst_n,

    input logic         gtrefclk_p,
    input logic         gtrefclk_n,

    input logic         rxn,
    input logic         rxp,
    output logic        txn,
    output logic        txp,

    // LEDS
    output logic        resetdone,
    output logic        mmcm_locked_out,
    output logic        gtpowergood
);

// Differential system clock -> 200 MHz fabric + /4 = 50 MHz independent clock
logic clk_ibufds;
logic clk_200;
logic clk_50;
logic clk_125;

IBUFDS sys_clk_ibufds (
    .I  (clk_p),
    .IB (clk_n),
    .O  (clk_ibufds)
);

BUFG sys_clk_bufg (
    .I (clk_ibufds),
    .O (clk_200)
);

BUFGCE_DIV #(
    .BUFGCE_DIVIDE(4)
) sys_clk_div (
    .I   (clk_200),
    .CE  (1'b1),
    .CLR (1'b0),
    .O   (clk_50)
);

BUFG eth_clk_bufg (
    .I (userclk2_out),
    .O (clk_125)
);

l2_hdr_t    rx_l2_hdr;
ipv4_hdr_t  rx_ipv4_hdr;
tcp_hdr_t   rx_tcp_hdr;
tcp_csr_t   rx_tcp_csr;

arp_hdr_t   rx_arp_hdr;
udp_hdr_t   rx_udp_hdr;

(* ASYNC_REG = "TRUE" *) logic [1:0] rst_50_sync;
(* ASYNC_REG = "TRUE" *) logic [1:0] rst_125_sync;
logic rst_50;
logic rst_125;

// Assert immediately from the active-low button and release synchronously
// within each clock domain.
always_ff @(posedge clk_50 or negedge rst_n) begin
    if (!rst_n) begin
        rst_50_sync <= '0;
    end
    else begin
        rst_50_sync <= {rst_50_sync[0], 1'b1};
    end
end

always_ff @(posedge clk_125 or negedge rst_n) begin
    if (!rst_n) begin
        rst_125_sync <= '0;
    end
    else begin
        rst_125_sync <= {rst_125_sync[0], 1'b1};
    end
end

assign rst_50  = !rst_50_sync[1];
assign rst_125 = !rst_125_sync[1];

logic           tcp_fifo_we;
logic           arp_fifo_we;

logic           gtrefclk_out;
logic           userclk_out;
logic           userclk2_out;
logic           rxuserclk_out;
logic           rxuserclk2_out;
logic           pma_reset_out;
logic           an_interrupt;
logic [15:0]    status_vector;

logic [7:0]     gmii_txd;
logic           gmii_tx_en;
logic           gmii_tx_er;
logic [7:0]     gmii_rxd;
logic           gmii_rx_dv;
logic           gmii_rx_er;
logic           gmii_isolate;

logic           gmii_rx_ready;

logic [575:0]   tx_axis_tdata;
logic [7:0]     tx_axis_frame_bytes;
logic           tx_axis_tvalid;
logic           tx_axis_tready;
logic [583:0]   tx_send_q_dout;
logic           tx_send_q_full;
logic           tx_send_q_empty;
logic           tx_send_q_rd_en;
logic           tx_send_q_wr_en;

logic           tcp_tx_desc_valid;
tcp_tx_desc_t   tcp_tx_desc;
logic           arp_tx_desc_valid;
arp_tx_desc_t   arp_tx_desc;
logic           arp_req_valid;
logic [31:0]    arp_req_dest_ip;
logic           arp_rep_valid;
logic [31:0]    arp_rep_dest_ip;
logic [47:0]    arp_rep_dest_mac;
logic           tcp_tx_payload_valid;
logic [15:0]    tcp_tx_payload_len;
logic [127:0]   tcp_tx_payload_data;

logic           gmii_rx_active;
logic           gmii_strip_preamble;
logic [2:0]     gmii_preamble_cnt;
logic [6:0]     gmii_rx_byte_cnt;
logic [511:0]   gmii_rx_shift;

typedef enum logic [2:0] {
    TX_IDLE,
    TX_PREAMBLE,
    TX_PAYLOAD,
    TX_FCS,
    TX_IFG
} tx_state_t;

tx_state_t      tx_state;
logic [7:0]     tx_count;
logic [575:0]   tx_shift;
logic [7:0]     tx_frame_bytes;
logic [7:0]     tx_wire_frame_bytes;

localparam int unsigned TX_MIN_FRAME_BYTES = 60;
localparam int unsigned TX_FCS_BYTES       = 4;
// Emits 20 byte periods; Ethernet requires at least 12 (96 bit-times) on GMII.
localparam int unsigned TX_IFG_BYTES       = 20;

logic [31:0]    crc_reg;
logic [7:0]     tx_payload_byte;
logic [31:0]    fcs_value;

logic           calc_valid;

assign tx_wire_frame_bytes = (tx_frame_bytes < TX_MIN_FRAME_BYTES) ? 8'(TX_MIN_FRAME_BYTES) : tx_frame_bytes;
assign tx_payload_byte = (tx_count < tx_frame_bytes)
                       ? tx_shift[575 - (tx_count * 8) -: 8]
                       : 8'h00;
assign fcs_value = ~crc_reg;

function automatic logic [31:0] crc32_next(input logic [31:0] crc_in, input logic [7:0] data);
    logic [31:0] crc;
    crc = crc_in;
    for (int i = 0; i < 8; i++) begin
        if (crc[0] ^ data[i]) begin
            crc = (crc >> 1) ^ 32'hEDB88320;
        end else begin
            crc = (crc >> 1);
        end
    end
    return crc;
endfunction

// Queue outbound packets so TX byte serializer can drain at wire speed
// without dropping new descriptors generated while TX is busy.
assign tx_send_q_wr_en = tx_axis_tvalid && !tx_send_q_full;
assign tx_send_q_rd_en = (tx_state == TX_IDLE) && !tx_send_q_empty;

fifo #(
    .WIDTH  (584),
    .DEPTH  (64),
    .FWFT   (1)
) tx_send_queue_i (
    .clk        (clk_125),
    .srst       (rst_125),
    .din        ({tx_axis_frame_bytes, tx_axis_tdata}),
    .wr_en      (tx_send_q_wr_en),
    .rd_en      (tx_send_q_rd_en),
    .dout       (tx_send_q_dout),
    .full       (tx_send_q_full),
    .empty      (tx_send_q_empty),
    .valid      (),
    .overflow   (),
    .wr_rst_busy(),
    .rd_rst_busy()
);

gig_ethernet_pcs_pma_0 sfp_i (
    .gtrefclk_p             (gtrefclk_p),
    .gtrefclk_n             (gtrefclk_n),
    .gtrefclk_out           (gtrefclk_out),
    .txn                    (txn),
    .txp                    (txp),
    .rxn                    (rxn),
    .rxp                    (rxp),
    .independent_clock_bufg (clk_50),
    .userclk_out            (userclk_out),
    .userclk2_out           (userclk2_out),
    .rxuserclk_out          (rxuserclk_out),
    .rxuserclk2_out         (rxuserclk2_out),
    .gtpowergood            (gtpowergood),
    .resetdone              (resetdone),
    .pma_reset_out          (pma_reset_out),
    .mmcm_locked_out        (mmcm_locked_out),
    .gmii_txd               (gmii_txd),
    .gmii_tx_en             (gmii_tx_en),
    .gmii_tx_er             (gmii_tx_er),
    .gmii_rxd               (gmii_rxd),
    .gmii_rx_dv             (gmii_rx_dv),
    .gmii_rx_er             (gmii_rx_er),
    .gmii_isolate           (gmii_isolate),
    .configuration_vector   ('0),
    .an_interrupt           (an_interrupt),
    .an_adv_config_vector   (16'h0020),
    .an_restart_config      ('0),
    .status_vector          (status_vector),
    .reset                  (rst_50),
    .signal_detect          ('1)
);

// SECTION: DESCRIPTOR ENTRY
localparam logic [31:0] HIBANA_DESC_MAGIC = 32'h48_54_44_30; // "HTD0"
localparam logic [7:0]  HIBANA_VERSION    = 8'd1;
localparam logic [7:0]  HIBANA_TCP_SEND   = 8'd1;
localparam logic [15:0] HIBANA_PAYLOAD_LEN= 16'd16;

logic        hibana_desc_valid;
logic [31:0] hibana_magic;
logic [7:0]  hibana_version;
logic [7:0]  hibana_kind;
logic [31:0] hibana_tcp_src_ip;
logic [31:0] hibana_tcp_dst_ip;
logic [15:0] hibana_tcp_src_port;
logic [15:0] hibana_tcp_dst_port;
logic [15:0] hibana_payload_len;
logic [127:0] hibana_payload;

assign hibana_magic        = rx_udp_hdr.payload[447:416];
assign hibana_version      = rx_udp_hdr.payload[415:408];
assign hibana_kind         = rx_udp_hdr.payload[407:400];
assign hibana_tcp_src_ip   = rx_udp_hdr.payload[255:224];
assign hibana_tcp_dst_ip   = rx_udp_hdr.payload[223:192];
assign hibana_tcp_src_port = rx_udp_hdr.payload[191:176];
assign hibana_tcp_dst_port = rx_udp_hdr.payload[175:160];
assign hibana_payload_len  = rx_udp_hdr.payload[159:144];
assign hibana_payload      = rx_udp_hdr.payload[127:0];

assign hibana_desc_valid   = calc_valid &&
                             (rx_l2_hdr.dest_mac == FPGA_MAC) &&
                             (rx_ipv4_hdr.dest_ip == FPGA_IP) &&
                             (hibana_magic == HIBANA_DESC_MAGIC) &&
                             (hibana_version == HIBANA_VERSION) &&
                             (hibana_kind == HIBANA_TCP_SEND) &&
                             (hibana_payload_len == HIBANA_PAYLOAD_LEN);

always_comb begin
    app_valid   = hibana_desc_valid;
    app_req     = '0;
    app_payload = '0;

    if (app_valid) begin
        app_req.req_type    = TCP_REQ_CONNECT_SEND;
        app_req.dest_ip     = hibana_tcp_dst_ip;
        app_req.src_ip      = hibana_tcp_src_ip;
        app_req.dest_port   = hibana_tcp_dst_port;
        app_req.src_port    = hibana_tcp_src_port;
        app_req.payload_len = HIBANA_PAYLOAD_LEN;
        app_payload         = hibana_payload;
    end
end


logic           app_queue_full;
logic           app_queue_empty;
logic           app_queue_valid;
logic           grant_payload;

logic           app_valid;      // Valid fixed-format Hibana descriptor
logic [127:0]   app_payload;
req_t           app_req;
req_entry_t     app_req_din;
req_entry_t     app_req_dout;

always_comb begin
    app_req_din = '0;

    if (app_valid) begin
        app_req_din.req       = app_req;
        app_req_din.payload   = app_payload;
    end
end

fifo #(
    .WIDTH  ($bits(req_entry_t)),
    .DEPTH  (16),
    .FWFT   (1)
) app_queue (
    .clk        (clk_125),
    .srst       (rst_125),
    .din        (app_req_din),
    .wr_en      (app_valid && !app_queue_full),
    .rd_en      (grant_payload && !app_queue_empty),
    .dout       (app_req_dout),
    .full       (app_queue_full),
    .empty      (app_queue_empty),
    .valid      (app_queue_valid),
    .overflow   (),
    .wr_rst_busy(),
    .rd_rst_busy()
);

rx_datapath rx_datapath_i (
    .clk                    (clk_125),
    .rst                    (rst_125),

    .tdata                  (gmii_rxd),
    .tvalid                 (gmii_rx_dv),
    .tready                 (gmii_rx_ready),

    .fifo_we                (tcp_fifo_we),
    .arp_fifo_we            (arp_fifo_we),
    .l2_hdr                 (rx_l2_hdr),
    .arp_hdr                (rx_arp_hdr),
    .ipv4_hdr               (rx_ipv4_hdr),
    .tcp_hdr                (rx_tcp_hdr),
    .tcp_csr                (rx_tcp_csr),
    .udp_hdr                (rx_udp_hdr),
    .udp_valid              (calc_valid),
    .sop_detected           ()
);

tx_datapath tx_datapath_i (
    .clk                        (clk_125),
    .rst                        (rst_125),

    .s_axis_c2h_tready          (tx_axis_tready),
    .s_axis_c2h_tdata           (tx_axis_tdata),
    .s_axis_c2h_tvalid          (tx_axis_tvalid),
    .s_axis_c2h_tlast           (),
    .s_axis_c2h_frame_bytes     (tx_axis_frame_bytes),

    .tcp_valid                  (tcp_tx_desc_valid),
    .tcp_desc                   (tcp_tx_desc),
    .tcp_payload_valid          (tcp_tx_payload_valid),
    .tcp_payload_len            (tcp_tx_payload_len),
    .tcp_payload_data           (tcp_tx_payload_data),

    .arp_valid                  (arp_tx_desc_valid),
    .arp_desc                   (arp_tx_desc)
);

tcp_top_level tcp_top_level_i (
    .clk                (clk_125),
    .rst                (rst_125),

    .header_valid       (tcp_fifo_we && rx_l2_hdr.dest_mac == FPGA_MAC && rx_ipv4_hdr.dest_ip == FPGA_IP),
    .rx_l2_hdr          (rx_l2_hdr),
    .rx_ipv4_hdr        (rx_ipv4_hdr),
    .rx_tcp_hdr         (rx_tcp_hdr),
    .rx_tcp_csr         (rx_tcp_csr),

    .app_req_in         (app_req_dout.req),
    .payload_data       (app_req_dout.payload),

    .arp_req_valid      (arp_req_valid),
    .arp_req_dest_ip    (arp_req_dest_ip),
    .arp_rep_valid      (arp_rep_valid),
    .arp_rep_dest_ip    (arp_rep_dest_ip),
    .arp_rep_dest_mac   (arp_rep_dest_mac),

    .tx_datapath_ready  (1'b1),
    .tx_desc_valid      (tcp_tx_desc_valid),

    .req_fifo_valid     (app_queue_valid),
    .grant_payload      (grant_payload),

    .has_payload        (tcp_tx_payload_valid),
    .payload_len_out    (tcp_tx_payload_len),
    .payload_data_out   (tcp_tx_payload_data),
    .tx_desc            (tcp_tx_desc)
);

arp_top_level arp_top_level_i (
    .clk                (clk_125),
    .rst                (rst_125),

    .arp_req_valid      (arp_req_valid),
    .arp_req_dest_ip    (arp_req_dest_ip),
    .arp_rep_valid      (arp_rep_valid),
    .arp_rep_dest_ip    (arp_rep_dest_ip),
    .arp_rep_dest_mac   (arp_rep_dest_mac),

    .arp_header_valid   (arp_fifo_we),
    .arp_header_in      (rx_arp_hdr),
    .learn_ipv4_valid   (tcp_fifo_we),
    .learn_l2_hdr       (rx_l2_hdr),
    .learn_ipv4_hdr     (rx_ipv4_hdr),
    .arp_tx_desc_valid  (arp_tx_desc_valid),
    .arp_tx_desc        (arp_tx_desc)
);

assign tx_axis_tready       = !tx_send_q_full;

always_ff @(posedge clk_125) begin
    if (rst_125) begin
        tx_state            <= TX_IDLE;
        tx_count            <= '0;
        tx_shift            <= '0;
        tx_frame_bytes      <= '0;
        gmii_txd            <= 8'h00;
        gmii_tx_en          <= 1'b0;
        gmii_tx_er          <= 1'b0;
        crc_reg             <= 32'hFFFF_FFFF;
    end else begin
        case (tx_state)
            TX_IDLE : begin
                gmii_tx_en  <= 1'b0;
                gmii_tx_er  <= 1'b0;
                gmii_txd    <= 8'h00;

                if (!tx_send_q_empty) begin
                    tx_frame_bytes <= tx_send_q_dout[583:576];
                    tx_shift       <= tx_send_q_dout[575:0];
                    tx_state    <= TX_PREAMBLE;
                    tx_count    <= '0;
                    crc_reg     <= 32'hFFFF_FFFF;
                end
            end
            TX_PREAMBLE : begin
                gmii_tx_en  <= 1'b1;
                gmii_tx_er  <= 1'b0;
                gmii_txd    <= (tx_count == 6'd7) ? 8'hD5 : 8'h55;

                if (tx_count == 6'd7) begin
                    tx_state    <= TX_PAYLOAD;
                    tx_count    <= '0;
                end else begin
                    tx_count    <= tx_count + 1'b1;
                end
            end
            TX_PAYLOAD : begin
                gmii_tx_en  <= 1'b1;
                gmii_tx_er  <= 1'b0;
                gmii_txd    <= tx_payload_byte;
                crc_reg     <= crc32_next(crc_reg, tx_payload_byte);

                if (tx_count == tx_wire_frame_bytes - 1) begin
                    tx_state    <= TX_FCS;
                    tx_count    <= '0;
                end else begin
                    tx_count    <= tx_count + 1'b1;
                end
            end
            TX_FCS : begin
                gmii_tx_en  <= 1'b1;
                gmii_tx_er  <= 1'b0;
                gmii_txd    <= fcs_value[8*tx_count +: 8];

                if (tx_count == TX_FCS_BYTES - 1) begin
                    tx_state    <= TX_IFG;
                    tx_count    <= '0;
                end else begin
                    tx_count    <= tx_count + 1'b1;
                end
            end
            TX_IFG : begin
                gmii_tx_en  <= 1'b0;
                gmii_tx_er  <= 1'b0;
                gmii_txd    <= 8'h00;

                if (tx_count == TX_IFG_BYTES - 1) begin
                    tx_state    <= TX_IDLE;
                    tx_count    <= '0;
                end else begin
                    tx_count    <= tx_count + 1'b1;
                end
            end
            default : begin
                tx_state    <= TX_IDLE;
            end
        endcase
    end
end

endmodule
