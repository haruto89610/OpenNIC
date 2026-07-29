// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps

package packages;

// SECTION: NETWORK

    //SUBSECTION: ETHERNET
    localparam logic [15:0] ETH_TYPE_IPV4 = 16'h0800;
    localparam logic [15:0] ETH_TYPE_ARP  = 16'h0806;

    typedef struct packed {
        logic [47:0] dest_mac;
        logic [47:0] src_mac;
        logic [15:0] ethertype;
    } l2_hdr_t;

    //SUBSECTION: IPV4
    localparam logic [7:0] IP_PROTO_TCP = 8'h06;
    localparam logic [7:0] IP_PROTO_UDP = 8'h11;

    typedef struct packed {
        logic [3:0]  version;
        logic [3:0]  ihl;
        logic [5:0]  dscp;
        logic [1:0]  ecn;
        logic [15:0] total_len;
        logic [15:0] id;
        logic [2:0]  flags;
        logic [14:0] frag_off;
        logic [7:0]  ttl;
        logic [7:0]  protocol;
        logic [15:0] hdr_checksum;
        logic [31:0] src_ip;
        logic [31:0] dest_ip;
    } ipv4_hdr_t;

    //SUBSECTION: UDP
    typedef struct packed {
        logic [15:0] src_port;
        logic [15:0] dest_port;
        logic [15:0] length;
        logic [15:0] checksum;
        logic [447:0] payload;
    } udp_hdr_t;

// SECTION: ARP

    //SUBSECTION: STATE
    typedef enum logic [2:0] {
        INCOMPLETE,
        REACHABLE,
        STALE,
        DELAY,
        PROBE,
        FAILED
    } arp_state_t;

    //SUBSECTION: HEADERS
    typedef struct packed {
        logic [15:0] htype;
        logic [15:0] ptype;
        logic [7:0]  hlen;
        logic [7:0]  plen;
        logic [15:0] oper;
        logic [47:0] sha;
        logic [31:0] spa;
        logic [47:0] tha;
        logic [31:0] tpa;
    } arp_hdr_t;

    //SUBSECTION: TRANSMIT
    typedef struct packed {
        logic [47:0] dest_mac;
        logic [47:0] src_mac;
        logic [15:0] oper;
        logic [47:0] sha;
        logic [31:0] spa;
        logic [47:0] tha;
        logic [31:0] tpa;
    } arp_tx_desc_t;

    //SUBSECTION: CACHE
    typedef struct packed {
        logic        valid;
        logic [27:0] tag;
        logic [31:0] ip_addr;
        logic [47:0] mac_addr;
        arp_state_t  state;
        logic [31:0] age;
        logic [1:0]  retry_timeout;
    } arp_cache_t;

// SECTION: TCP

    //SUBSECTION: STATE
    typedef enum logic [3:0] {
        CLOSED,
        LISTEN,
        SYN_RECV,
        SYN_SENT,
        ESTABLISHED,
        FIN_1,
        FIN_2,
        CLOSING,
        CLOSE_WAIT,
        LAST_ACK,
        TIME_WAIT
    } tcp_state_t;

    typedef struct packed {
        logic syn;
        logic ack;
        logic rst;
        logic fin;
        logic psh;
    } tcp_csr_t;

    localparam tcp_csr_t CSR_SYN     = '{syn:1'b1, ack:1'b0, rst:1'b0, fin:1'b0, psh:1'b0};
    localparam tcp_csr_t CSR_ACK     = '{syn:1'b0, ack:1'b1, rst:1'b0, fin:1'b0, psh:1'b0};
    localparam tcp_csr_t CSR_SYN_ACK = '{syn:1'b1, ack:1'b1, rst:1'b0, fin:1'b0, psh:1'b0};
    localparam tcp_csr_t CSR_FIN     = '{syn:1'b0, ack:1'b0, rst:1'b0, fin:1'b1, psh:1'b0};
    localparam tcp_csr_t CSR_FIN_ACK = '{syn:1'b0, ack:1'b1, rst:1'b0, fin:1'b1, psh:1'b0};
    localparam tcp_csr_t CSR_RST     = '{syn:1'b0, ack:1'b0, rst:1'b1, fin:1'b0, psh:1'b0};
    localparam tcp_csr_t CSR_PSH_ACK = '{syn:1'b0, ack:1'b1, rst:1'b0, fin:1'b0, psh:1'b1};

    //SUBSECTION: HEADERS
    typedef struct packed {
        logic [15:0] src_port;
        logic [15:0] dest_port;
        logic [31:0] seq_num;
        logic [31:0] ack_num;
        logic [3:0]  data_off;
        logic [3:0]  resv;
        logic [7:0]  csr;
        logic [15:0] window;
        logic [15:0] checksum;
        logic [15:0] urgent;
    } tcp_hdr_t;

    typedef struct packed {
        l2_hdr_t    l2_hdr;
        ipv4_hdr_t  ipv4_hdr;
        tcp_hdr_t   tcp_hdr;
        tcp_csr_t   tcp_csr;
    } header_t;

    //SUBSECTION: CONNECTION CACHE
    typedef struct packed {
        logic       valid;
        logic       side;
        logic [1:0] way;
        logic [3:0] set;
    } cache_rmap_t;

    //SUBSECTION: TCB
    typedef struct packed {
        logic [47:0] dest_mac;
        logic [47:0] src_mac;
        logic [31:0] dest_ip;
        logic [31:0] src_ip;
        logic [15:0] dest_port;
        logic [15:0] src_port;
        tcp_state_t  tcp_curr_t;
        tcp_state_t  tcp_next_t;
        logic [31:0] seq_num;
        logic [31:0] ack_num;
        logic [15:0] len_num;
        logic [31:0] snd_una;
        logic [31:0] snd_nxt;
        logic [31:0] rcv_nxt;
        logic [5:0]  next_send_time;
        logic [4:0]  backoff_exp;
        tcp_csr_t    csr_curr;
    } tcb_t;

    //SUBSECTION: TRANSMIT
    typedef struct packed {
        logic [47:0] dest_mac;
        logic [47:0] src_mac;
        logic [31:0] dest_ip;
        logic [31:0] src_ip;
        logic [15:0] dest_port;
        logic [15:0] src_port;
        logic [31:0] seq_num;
        logic [31:0] ack_num;
        tcp_csr_t    csr_curr;
    } tcp_tx_desc_t;

    //SUBSECTION: APPLICATION REQUEST
    typedef struct packed {
        logic        valid;
        logic [1:0]  req_type;
        logic        use_dest_mac;
        logic [47:0] dest_mac;
        logic [31:0] src_ip;
        logic [31:0] dest_ip;
        logic [15:0] src_port;
        logic [15:0] dest_port;
        logic [15:0] payload_len;
        logic        psh;
        logic        fin;
    } tcp_desc_in_t;

    typedef enum logic [1:0] {
        TCP_REQ_CONNECT_SEND = 2'b00,
        TCP_REQ_FAST_SEND    = 2'b01,
        TCP_REQ_CLOSE        = 2'd2
    } tcp_req_type_t;

    typedef struct packed {
        tcp_req_type_t  req_type;
        logic [31:0]    dest_ip;
        logic [31:0]    src_ip;
        logic [15:0]    src_port;
        logic [15:0]    dest_port;
        logic [15:0]    payload_len;
    } req_t;

    typedef struct packed {
        req_t           req;
        logic [127:0]   payload;
    } req_entry_t;

    typedef struct packed {
        tcp_req_type_t  req_type;
        logic [5:0]     tcb_addr;
        logic [47:0]    dest_mac;
        logic [31:0]    dest_ip;
        logic [31:0]    src_ip;
        logic [15:0]    src_port;
        logic [15:0]    dest_port;
        logic [15:0]    payload_len;
    } tcp_arp_t;

// SECTION: MARKET DATA

    //SUBSECTION: RECEIVE
    typedef struct packed {
        logic        valid;
        logic        supported_msg;
        logic [1:0]  message_kind;
        logic [7:0]  itch_msg_type;
        logic [15:0] stock_locate;
        logic [15:0] tracking_number;
        logic [47:0] timestamp;
        logic [63:0] order_ref;
        logic        buy_sell;
        logic [31:0] shares;
        logic [63:0] stock;
        logic [31:0] price;
    } market_rx_t;

    //SUBSECTION: ORDER BOOK
    typedef struct packed {
        logic        valid;
        logic [31:0] price;
        logic [31:0] qty;
    } orderbook_t;

endpackage : packages
