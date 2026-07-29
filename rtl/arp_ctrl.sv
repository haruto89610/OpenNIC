// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps

import packages::*;
module arp_ctrl #(
    parameter logic [47:0] FPGA_MAC = 48'h00_12_34_56_78_90,
    parameter logic [31:0] FPGA_IP  = {8'd192, 8'd168, 8'd0, 8'd10}
) (
    input logic             clk,
    input logic             rst,

    // ARP PORTS
    // Path:
    //      0 - TX
    //      1 - RX
    input logic             path,
    input logic             valid_in,
    input logic [31:0]      ip_addr_in,
    input arp_hdr_t         arp_hdr,

    // LEARN PORTS
    input logic             pkt_valid,
    input l2_hdr_t          l2_hdr,
    input ipv4_hdr_t        ipv4_hdr,

    // ARP REPLY
    output logic            arp_valid,
    output arp_tx_desc_t    arp_desc,

    // EGRESS PATH
    output logic            mac_valid,
    output logic [31:0]     resolved_ip,
    output logic [47:0]     resolved_mac
);

/*
3 ARP Cases:
    - Egress lookup
        - Other protocol wants to send packet to IP but MAC unknown
        - Send ARP request on cache miss
        - Send ARP request on unusable entry
            - INCOMPLETE / FAILED / STALE -> Probe
    - Ingress Learn
        - Other protocol sends packet to FPGA with IP and MAC
        - Update if different
    - Ingress Reply
        - If ARP request is received, reply immediately with ARP reply
*/

arp_cache_t cache [3:0] [15:0];

localparam arp_cache_t ARP_CACHE_DEFAULT = '{
    valid         : 1'b0,
    tag           : '0,
    ip_addr       : '0,
    mac_addr      : '0,
    state         : INCOMPLETE,
    age           : '0,
    retry_timeout : '0
};

logic       hit;
logic [1:0] hit_way;
logic [2:0] free_way;

logic [1:0] sel_way;
logic [3:0] sel_idx;

logic       arm_stale_valid;
logic       arm_stale_cancel;
logic [1:0] arm_stale_way;
logic [3:0] arm_stale_idx;

logic       timeout_stale_valid;
logic [1:0] timeout_stale_way;
logic [3:0] timeout_stale_idx;

logic       arm_retry_valid;
logic       arm_retry_cancel;
logic [1:0] arm_retry_way;
logic [3:0] arm_retry_idx;
logic [9:0] arm_retry_deadline;

logic       timeout_retry_valid;
logic [1:0] timeout_retry_way;
logic [3:0] timeout_retry_idx;

logic       egress;
logic       ingress;

logic [27:0]    tag;
logic [3:0]     idx;

assign egress   = !path && valid_in;
assign ingress  = path && valid_in;

arp_retry_timer arp_timer_i (
    .clk            (clk),
    .rst            (rst),

    .arm_valid      (arm_retry_valid),
    .arm_cancel     (arm_retry_cancel),
    .arm_way        (arm_retry_way),
    .arm_idx        (arm_retry_idx),
    .arm_deadline   (arm_retry_deadline),

    .timeout_valid  (timeout_retry_valid),
    .timeout_way    (timeout_retry_way),
    .timeout_idx    (timeout_retry_idx)
);

arp_stale_timer arp_stale_timer_i (
    .clk            (clk),
    .rst            (rst),

    .arm_valid      (arm_stale_valid),
    .arm_cancel     (arm_stale_cancel),
    .arm_way        (arm_stale_way),
    .arm_idx        (arm_stale_idx),

    .timeout_valid  (timeout_stale_valid),
    .timeout_way    (timeout_stale_way),
    .timeout_idx    (timeout_stale_idx)
);

always_comb begin
    tag = 'x;
    idx = 'x;

// SUBSECTION: REQUEST PATH
    if (ingress) begin
        tag = arp_hdr.spa[31:4];
        idx = arp_hdr.spa[3:0];
    end
// SUBSECTION: LEARN PATH
    else if (pkt_valid) begin
        tag = ipv4_hdr.src_ip[31:4];
        idx = ipv4_hdr.src_ip[3:0];
    end
// SUBSECTION: LOOKUP PATH
    else if (egress) begin
        tag = ip_addr_in[31:4];
        idx = ip_addr_in[3:0];
    end
end

// SECTION: CACHE HIT / NEXT FREE
always_comb begin
    automatic logic found = 1'b0;
    hit         = '0;
    hit_way     = '0;
    free_way    = '0;

    for (int i = 0; i < 4; i++) begin
        logic match = cache[i][idx].valid && (cache[i][idx].tag == tag);

        if (match && !hit) begin
            hit     = 1'b1;
            hit_way = {i[1:0]};
        end
    end

    for (int i = 0; i < 4; i++) begin
        if (!found && !cache[i][idx].valid) begin
            free_way = {1'b1, i[1:0]};
            found = 1'b1;
        end

        if (!found && cache[i][idx].state == FAILED) begin
            free_way = {1'b1, i[1:0]};
            found = 1'b1;
        end

        if (!found && cache[i][idx].state == STALE) begin
            free_way = {1'b1, i[1:0]};
            found = 1'b1;
        end
    end
end

// SECTION: DESCRIPTOR CONSTRUCTION
always_comb begin
    arp_valid   = '0;
    arp_desc    = 'x;

    arp_desc.dest_mac   = 48'hFF_FF_FF_FF_FF_FF;
    arp_desc.src_mac    = FPGA_MAC;
    arp_desc.sha    = FPGA_MAC;
    arp_desc.spa    = FPGA_IP;

// SUBSECTION: INGRESS DESCRIPTOR
    if (ingress) begin
        // REPLY TO INCOMING ARP REQUEST
        if ((arp_hdr.oper == 16'h0001) && (arp_hdr.tpa == FPGA_IP)) begin
            arp_valid       = 1'b1;

            arp_desc.dest_mac   = arp_hdr.sha;
            arp_desc.oper   = 16'h0002;
            arp_desc.tha    = arp_hdr.sha;
            arp_desc.tpa    = arp_hdr.spa;
        end
    end
// SUBSECTION: EGRESS DESCRIPTOR
    else if (egress) begin
        // SEND ARP REQUEST TO FILL NEW ENTRY
        if (!hit && free_way[2]) begin
            arp_valid       = 1'b1;

            arp_desc.oper   = 16'h0001;
            arp_desc.tha    = '0;
            arp_desc.tpa    = ip_addr_in;
        end
        else if (hit && (cache[hit_way][idx].state == FAILED)) begin
            // Re-open FAILED entry when traffic needs it again.
            arp_valid       = 1'b1;
            arp_desc.oper   = 16'h0001;
            arp_desc.tha    = '0;
            arp_desc.tpa    = cache[hit_way][idx].ip_addr;
        end
    end
// SUBSECTION: TIMEOUT
    else if (timeout_retry_valid &&
             ((cache[timeout_retry_way][timeout_retry_idx].state == INCOMPLETE) ||
              (cache[timeout_retry_way][timeout_retry_idx].state == DELAY) ||
              (cache[timeout_retry_way][timeout_retry_idx].state == PROBE))) begin
        arp_valid       = 1'b1;
        arp_desc.oper   = 16'h0001;
        arp_desc.tha    = '0;
        arp_desc.tpa    = cache[timeout_retry_way][timeout_retry_idx].ip_addr;
    end
end

// SECTION: TIMER INPUT
always_comb begin
    arm_retry_valid   = 1'b0;
    arm_retry_cancel  = 1'b0;
    arm_retry_way     = '0;
    arm_retry_idx     = '0;
    arm_retry_deadline= '0;

    arm_stale_valid   = 1'b0;
    arm_stale_cancel  = 1'b0;
    arm_stale_way     = '0;
    arm_stale_idx     = '0;

    if (timeout_retry_valid) begin
        // RESCHEDULE SEND
        unique case (cache[timeout_retry_way][timeout_retry_idx].state)
            INCOMPLETE, DELAY, PROBE: begin
                arm_retry_valid   = 1'b1;
                arm_retry_way     = timeout_retry_way;
                arm_retry_idx     = timeout_retry_idx;
                arm_retry_deadline= 10'd4;
            end
            default: begin
                arm_retry_valid   = 1'b1;
                arm_retry_cancel  = 1'b1;
                arm_retry_way     = timeout_retry_way;
                arm_retry_idx     = timeout_retry_idx;
            end
        endcase
    end

    if (ingress) begin
        if (hit) begin
            arm_retry_valid   = 1'b1;
            arm_retry_cancel  = 1'b1;
            arm_retry_way     = hit_way;
            arm_retry_idx     = idx;
            arm_retry_deadline= '0;

            arm_stale_valid = 1'b1;
            arm_stale_way   = hit_way;
            arm_stale_idx   = idx;
        end
        else if (free_way[2]) begin
            arm_stale_valid = 1'b1;
            arm_stale_way   = free_way[1:0];
            arm_stale_idx   = idx;
        end
    end
    else if (egress) begin
        if (!hit && free_way[2]) begin
            arm_retry_valid   = 1'b1;
            arm_retry_way     = free_way[1:0];
            arm_retry_idx     = idx;
            arm_retry_deadline= 10'd4;
        end
        else if (hit) begin
            if ((cache[hit_way][idx].state == STALE) || (cache[hit_way][idx].state == PROBE) || (cache[hit_way][idx].state == FAILED)) begin
                arm_retry_valid   = 1'b1;
                arm_retry_way     = hit_way;
                arm_retry_idx     = idx;
                arm_retry_deadline= 10'd4;
            end
        end
    end
    else if (pkt_valid) begin
        if (hit) begin
            arm_retry_valid   = 1'b1;
            arm_retry_cancel  = 1'b1;
            arm_retry_way     = hit_way;
            arm_retry_idx     = idx;
            arm_retry_deadline= '0;

            arm_stale_valid = 1'b1;
            arm_stale_way   = hit_way;
            arm_stale_idx   = idx;
        end
        else if (free_way[2]) begin
            arm_stale_valid = 1'b1;
            arm_stale_way   = free_way[1:0];
            arm_stale_idx   = idx;
        end
    end
end

// SECTION: STATE TRANSITION / RESPONSE
always_ff @(posedge clk) begin
    if (rst) begin
        mac_valid       <= '0;
        resolved_ip     <= '0;
        resolved_mac    <= '0;

        cache   <= '{default : '{default : ARP_CACHE_DEFAULT}};
    end
    else begin
        mac_valid       <= '0;
        resolved_ip     <= '0;
        resolved_mac    <= '0;

        if (valid_in || pkt_valid || timeout_retry_valid || timeout_stale_valid) begin
    // SUBSECTION: INCOMING ARP REQUEST
            if (ingress) begin
                mac_valid       <= '1;
                resolved_ip     <= arp_hdr.spa;
                resolved_mac    <= arp_hdr.sha;

                if (hit) begin
                    cache[hit_way][idx].valid           <= 1'b1;
                    cache[hit_way][idx].tag             <= tag;
                    cache[hit_way][idx].ip_addr         <= arp_hdr.spa;
                    cache[hit_way][idx].mac_addr        <= arp_hdr.sha;
                    cache[hit_way][idx].state           <= REACHABLE;
                    cache[hit_way][idx].age             <= '0;
                    cache[hit_way][idx].retry_timeout   <= '0;
                end
                else begin
                    if (free_way[2] == 1'b1) begin
                        cache[free_way[1:0]][idx].valid         <= 1'b1;
                        cache[free_way[1:0]][idx].tag           <= tag;
                        cache[free_way[1:0]][idx].ip_addr       <= arp_hdr.spa;
                        cache[free_way[1:0]][idx].mac_addr      <= arp_hdr.sha;
                        cache[free_way[1:0]][idx].state         <= REACHABLE;
                        cache[free_way[1:0]][idx].age           <= '0;
                        cache[free_way[1:0]][idx].retry_timeout <= '0;
                    end
                end
            end
    // SUBSECTION: OUTGOING PACKET
            else if (egress) begin
                if (hit) begin
                    unique case (cache[hit_way][idx].state)
                        INCOMPLETE  : begin
                            // Waiting for ARP response / timer retry.
                        end
                        REACHABLE   : begin
                            mac_valid       <= 1'b1;
                            resolved_ip     <= cache[hit_way][idx].ip_addr;
                            resolved_mac    <= cache[hit_way][idx].mac_addr;
                        end
                        STALE       : begin
                            mac_valid       <= 1'b1;
                            resolved_ip     <= cache[hit_way][idx].ip_addr;
                            resolved_mac    <= cache[hit_way][idx].mac_addr;
                            cache[hit_way][idx].state <= DELAY;
                        end
                        DELAY       : begin
                            mac_valid       <= 1'b1;
                            resolved_ip     <= cache[hit_way][idx].ip_addr;
                            resolved_mac    <= cache[hit_way][idx].mac_addr;
                        end
                        PROBE       : begin
                            // Conservative policy: do not use stale MAC while actively probing.
                        end
                        FAILED      : begin
                            cache[hit_way][idx].state         <= INCOMPLETE;
                            cache[hit_way][idx].retry_timeout <= '0;
                        end
                    endcase
                end
                else begin
                    if (free_way[2] == 1'b1) begin
                        cache[free_way[1:0]][idx].valid         <= 1'b1;
                        cache[free_way[1:0]][idx].tag           <= tag;
                        cache[free_way[1:0]][idx].ip_addr       <= ip_addr_in;
                        cache[free_way[1:0]][idx].mac_addr      <= 48'h0;
                        cache[free_way[1:0]][idx].state         <= INCOMPLETE;
                        cache[free_way[1:0]][idx].age           <= '0;
                        cache[free_way[1:0]][idx].retry_timeout <= '0;
                    end
                end
            end
    // SUBSECTION: INCOMING PACKET
            else begin
                mac_valid       <= '1;
                resolved_ip     <= ipv4_hdr.src_ip;
                resolved_mac    <= l2_hdr.src_mac;

                if (pkt_valid && hit) begin
                    cache[hit_way][idx].valid           <= 1'b1;
                    cache[hit_way][idx].tag             <= tag;
                    cache[hit_way][idx].ip_addr         <= ipv4_hdr.src_ip;
                    cache[hit_way][idx].mac_addr        <= l2_hdr.src_mac;
                    cache[hit_way][idx].state           <= REACHABLE;
                    cache[hit_way][idx].age             <= '0;
                    cache[hit_way][idx].retry_timeout   <= '0;
                end
                else if (pkt_valid && !hit) begin
                    /*
                        ARP cache full or miss.
                        Replacement Policy:
                            - Invalid?
                            - FAILED
                            - STALE
                            - skip
                    */
                    if (free_way[2] == 1'b1) begin
                        cache[free_way[1:0]][idx].valid         <= 1'b1;
                        cache[free_way[1:0]][idx].tag           <= tag;
                        cache[free_way[1:0]][idx].ip_addr       <= ipv4_hdr.src_ip;
                        cache[free_way[1:0]][idx].mac_addr      <= l2_hdr.src_mac;
                        cache[free_way[1:0]][idx].state         <= REACHABLE;
                        cache[free_way[1:0]][idx].age           <= '0;
                        cache[free_way[1:0]][idx].retry_timeout <= '0;
                    end
                end
            end

            if (timeout_retry_valid) begin
                automatic logic [1:0] retry_timeout = cache[timeout_retry_way][timeout_retry_idx].retry_timeout;
                unique case (cache[timeout_retry_way][timeout_retry_idx].state)
                    INCOMPLETE: begin
                        if (retry_timeout == 2'b11) begin
                            cache[timeout_retry_way][timeout_retry_idx].state <= FAILED;
                            cache[timeout_retry_way][timeout_retry_idx].valid <= 1'b0;
                        end
                        cache[timeout_retry_way][timeout_retry_idx].retry_timeout <= retry_timeout + 1'b1;
                    end
                    REACHABLE: begin
                        cache[timeout_retry_way][timeout_retry_idx].retry_timeout <= '0;
                    end
                    DELAY: begin
                        cache[timeout_retry_way][timeout_retry_idx].state <= PROBE;
                        cache[timeout_retry_way][timeout_retry_idx].retry_timeout <= '0;
                    end
                    PROBE: begin
                        if (retry_timeout == 2'b11) begin
                            cache[timeout_retry_way][timeout_retry_idx].state <= FAILED;
                            cache[timeout_retry_way][timeout_retry_idx].valid <= 1'b0;
                        end
                        cache[timeout_retry_way][timeout_retry_idx].retry_timeout <= retry_timeout + 1'b1;
                    end
                    default: begin
                    end
                endcase
            end

            if (timeout_stale_valid) begin
                if (cache[timeout_stale_way][timeout_stale_idx].state == REACHABLE && cache[timeout_stale_way][timeout_stale_idx].valid) begin
                    cache[timeout_stale_way][timeout_stale_idx].state <= STALE;
                end
            end
        end
        end
end


endmodule
