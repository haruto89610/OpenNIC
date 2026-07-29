// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps

import packages::*;
module cache #(
    parameter WIDTH = 32,
    parameter DEPTH = 16,
    parameter WAYS  = 4
)(
    input logic             clk,
    input logic             rst,

    input logic             read,
    input logic             alloc_ena,
    input logic [127:0]     input_tuple,

    output logic            read_miss,
    output logic            tcb_full,

    output logic [95:0]     input_addr,
    output logic            tcb_addr_valid,
    output logic [5:0]      tcb_addr,

    input logic             invalidate,
    input logic [5:0]       invalidate_addr
);


localparam int MISS_LATENCY = 1;
localparam int HIT_LATENCY  = 1;

logic [MISS_LATENCY-1:0] req_valid;

logic [15:0]    valid [4];
logic [63:0]    valid_bitmap;
cache_rmap_t    reverse_map [64];

logic [31:0]    hash_l;
logic [31:0]    hash_l_d;
logic [25:0]    tag_l;
logic [3:0]     set_addr_l [4];
logic [3:0]     free_addr_l [4];
logic [3:0]     hit_l_one_hot;
logic [3:0]     hit_l_one_hot_d;
logic [1:0]     hit_way_l;

logic [31:0]    hash_r;
logic [31:0]    hash_r_d;
logic [25:0]    tag_r;
logic [3:0]     set_addr_r [4];
logic [3:0]     free_addr_r [4];
logic [3:0]     hit_r_one_hot;
logic [3:0]     hit_r_one_hot_d;
logic [1:0]     hit_way_r;

logic wea [4];
logic web [4];
logic [31:0] din_l  [4];
logic [31:0] dout_l [4];
logic [31:0] din_r  [4];
logic [31:0] dout_r [4];
(* ram_style = "distributed" *) logic [31:0] cache_mem [4][16];

logic alloc_ena_d;
logic read_d;
logic [5:0] tcb_alloc;
logic [5:0] alloc_addr;

logic [3:0] free_l_one_hot;
logic [3:0] free_r_one_hot;
logic [1:0] free_l;
logic [1:0] free_r;
logic [2:0] free_l_cnt;
logic [2:0] free_r_cnt;

logic [25:0] tag_l_d;
logic [25:0] tag_r_d;

assign tag_l = hash_l[31:6];
assign tag_r = hash_r[31:6];

assign input_addr = input_tuple[95:0];

logic cache_hit;
logic has_free_way;
logic can_alloc;

assign cache_hit    = read_d && (|hit_l_one_hot || |hit_r_one_hot);
assign read_miss    = read_d && !cache_hit;
assign has_free_way = |free_l_one_hot || |free_r_one_hot;
assign can_alloc    = read_miss && alloc_ena_d && !valid_bitmap[alloc_addr] && has_free_way;
assign tcb_full     = read_miss && !can_alloc;

toeplitz_hash toeplitz_hash_i (
    .tuple_input    (input_addr),
    .hash_out_1     (hash_l),
    .hash_out_2     (hash_r)
);

always_ff @(posedge clk) begin
    if (rst) begin
        alloc_ena_d <= '0;
    end
    else if (read) begin
        alloc_ena_d <= alloc_ena;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        cache_mem <= '{default : '0};
        dout_l    <= '{default : '0};
        dout_r    <= '{default : '0};
    end
    else begin
        for (int i = 0; i < 4; i++) begin
            dout_l[i] <= cache_mem[i][set_addr_l[i]];
            if (wea[i]) begin
                cache_mem[i][free_addr_l[i]] <= din_l[i];
                dout_l[i] <= din_l[i];
            end

            dout_r[i] <= cache_mem[i][set_addr_r[i]];
            if (web[i]) begin
                cache_mem[i][free_addr_r[i]] <= din_r[i];
                dout_r[i] <= din_r[i];
            end
        end
    end
end

always_ff @(posedge clk) begin
    req_valid <= req_valid << 1'b1;

    if (rst) begin
        req_valid <= '0;
        tcb_addr_valid  <= 1'b0;
    end
    else begin
        tcb_addr_valid  <= 1'b0;
        if (read) begin
            req_valid[0]    <= 1'b1;
            tcb_addr_valid  <= 1'b0;
        end
        if (req_valid[HIT_LATENCY-1] && cache_hit) begin   // Read hit
            tcb_addr_valid              <= 1'b1;
        end
        if (req_valid[MISS_LATENCY-1] && can_alloc) begin
            tcb_addr_valid              <= 1'b1;
        end
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        tcb_addr <= 'X;
    end
    else if (|hit_l_one_hot) begin
        tcb_addr <= dout_l[hit_way_l][5:0];
    end
    else if (|hit_r_one_hot) begin
        tcb_addr <= dout_r[hit_way_r][5:0];
    end
    // Multi-flow allocation behavior requires additional regression coverage.
    else if (can_alloc) begin
        tcb_addr <= alloc_addr;
    end
    else begin
        tcb_addr <= 'X;
    end
end

always_ff @(posedge clk) begin
    hit_l_one_hot_d <= hit_l_one_hot;
    hit_r_one_hot_d <= hit_r_one_hot;
end

always_ff @(posedge clk) begin
    if (rst) begin
        hash_l_d <= '0;
        hash_r_d <= '0;

        tag_l_d <= '0;
        tag_r_d <= '0;
    end
    else begin
        if (read) begin
            hash_l_d <= hash_l;
            hash_r_d <= hash_r;

            tag_l_d <= tag_l;
            tag_r_d <= tag_r;
        end
    end
end

always_comb begin
    for (int i = 0; i < 4; i++) begin
        wea[i]      = '0;
        web[i]      = '0;
        din_l[i]    = '0;
        din_r[i]    = '0;
    end

    if (can_alloc && !invalidate) begin
        // ALLOCATE
        if (|free_l_one_hot && |free_r_one_hot) begin
            if (free_l_cnt >= free_r_cnt) begin
                wea[free_l]     = '1;
                din_l[free_l]   = {tag_l_d, alloc_addr};
            end
            else begin
                web[free_r]     = '1;
                din_r[free_r]   = {tag_r_d, alloc_addr};
            end
        end
        else if (|free_l_one_hot) begin
            wea[free_l]     = '1;
            din_l[free_l]   = {tag_l_d, alloc_addr};
        end
        else if (|free_r_one_hot) begin
            web[free_r]     = '1;
            din_r[free_r]   = {tag_r_d, alloc_addr};
        end
    end
end

always_ff @(posedge clk) begin
    read_d  <= read;

    if (rst) begin
        tcb_alloc   <= '0;
        valid_bitmap<= '0;
        valid       <= '{default : 0};
        reverse_map <= '{default : 0};
    end
    else if (invalidate) begin
        automatic logic [1:0] invalidate_way    = reverse_map[invalidate_addr].way;
        automatic logic [3:0] invalidate_set    = reverse_map[invalidate_addr].set;

        valid_bitmap[invalidate_addr]       <= 1'b0;
        reverse_map[invalidate_addr].valid  <= '0;

        if (reverse_map[invalidate_addr].valid) begin
            valid[invalidate_way][invalidate_set]   <= '0;
        end
    end
    else if (can_alloc) begin
        // ALLOCATE
        if (|free_l_one_hot && |free_r_one_hot) begin
            if (free_l_cnt >= free_r_cnt) begin
                reverse_map[alloc_addr].valid    <= 1'b1;
                reverse_map[alloc_addr].side     <= 1'b1;
                reverse_map[alloc_addr].way      <= free_l;
                reverse_map[alloc_addr].set      <= free_addr_l[free_l];

                valid_bitmap[alloc_addr]         <= 1'b1;

                valid[free_l][free_addr_l[free_l]]   <= 1'b1;

                if (alloc_addr == tcb_alloc && tcb_alloc != 6'd63) begin
                    tcb_alloc <= tcb_alloc + 1'b1;
                end
            end
            else begin
                reverse_map[alloc_addr].valid    <= 1'b1;
                reverse_map[alloc_addr].side     <= 1'b0;
                reverse_map[alloc_addr].way      <= free_r;
                reverse_map[alloc_addr].set      <= free_addr_r[free_r];

                valid_bitmap[alloc_addr]         <= 1'b1;

                valid[free_r][free_addr_r[free_r]]   <= 1'b1;

                if (alloc_addr == tcb_alloc && tcb_alloc != 6'd63) begin
                    tcb_alloc <= tcb_alloc + 1'b1;
                end
            end
        end
        else if (|free_l_one_hot) begin
            reverse_map[alloc_addr].valid    <= 1'b1;
            reverse_map[alloc_addr].side     <= 1'b1;
            reverse_map[alloc_addr].way      <= free_l;
            reverse_map[alloc_addr].set      <= free_addr_l[free_l];

            valid_bitmap[alloc_addr]         <= 1'b1;

            valid[free_l][free_addr_l[free_l]]   <= 1'b1;

            if (alloc_addr == tcb_alloc && tcb_alloc != 6'd63) begin
                tcb_alloc <= tcb_alloc + 1'b1;
            end
        end
        else if (|free_r_one_hot) begin
            reverse_map[alloc_addr].valid    <= 1'b1;
            reverse_map[alloc_addr].side     <= 1'b0;
            reverse_map[alloc_addr].way      <= free_r;
            reverse_map[alloc_addr].set      <= free_addr_r[free_r];

            valid_bitmap[alloc_addr]         <= 1'b1;

            valid[free_r][free_addr_r[free_r]]   <= 1'b1;

            if (alloc_addr == tcb_alloc && tcb_alloc != 6'd63) begin
                tcb_alloc <= tcb_alloc + 1'b1;
            end
        end
    end
end

always_comb begin
    alloc_addr = tcb_alloc;
    if (valid_bitmap[tcb_alloc]) begin
        for (int i = 0; i < 64; i++) begin
            if (!valid_bitmap[i]) begin
                alloc_addr = i[5:0];
            end
        end
    end
end

always_comb begin
    set_addr_l = '{default : '0};
    set_addr_r = '{default : '0};

    free_addr_l = '{default : '0};
    free_addr_r = '{default : '0};

    hit_l_one_hot = '0;
    hit_r_one_hot = '0;

    hit_way_l = '0;
    hit_way_r = '0;

    free_l_one_hot = '0;
    free_r_one_hot = '0;

    free_l_cnt = '0;
    free_r_cnt = '0;

    for (int i = 0; i < 4; i++) begin
        set_addr_l[i]   = hash_l[3:0];
        set_addr_r[i]   = hash_r[3:0];

        free_addr_l[i]  = hash_l_d[3:0];
        free_addr_r[i]  = hash_r_d[3:0];
    end

    // ------------------------------------------------------------- HIT LOGIC

    // Compare with registered tag to account for BRAM latency
    for (int i = 0; i < 4; i++) begin
        hit_l_one_hot[i] = valid[i][free_addr_l[i]] && (dout_l[i][31:6] == tag_l_d);
        hit_r_one_hot[i] = valid[i][free_addr_r[i]] && (dout_r[i][31:6] == tag_r_d);
    end

    for (int i = 0; i < 4; i++) begin
        if (hit_l_one_hot[i])
            hit_way_l = i;
    end
    for (int i = 0; i < 4; i++) begin
        if (hit_r_one_hot[i])
            hit_way_r = i;
    end

    // ------------------------------------------------------------- FREE LOGIC

    free_l_one_hot  = {~valid[3][free_addr_l[3]],
                       ~valid[2][free_addr_l[2]],
                       ~valid[1][free_addr_l[1]],
                       ~valid[0][free_addr_l[0]]};

    free_r_one_hot  = {~valid[3][free_addr_r[3]],
                       ~valid[2][free_addr_r[2]],
                       ~valid[1][free_addr_r[1]],
                       ~valid[0][free_addr_r[0]]};

    for (int i = 0; i < 4; i++) begin
        if (free_l_one_hot[i])
            free_l = i;
    end
    for (int i = 0; i < 4; i++) begin
        if (free_r_one_hot[i])
            free_r = i;
    end

    // ------------------------------------------------------------- DLEFT LOGIC

    for (int i = 0; i < 4; i++) begin
        free_l_cnt += free_l_one_hot[i];
        free_r_cnt += free_r_one_hot[i];
    end

end
endmodule
