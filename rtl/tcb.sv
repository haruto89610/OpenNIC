// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps

import packages::*;
module tcb(
    input logic             clk,
    input logic             rst,

    input logic [5:0]       addra,
    input logic             wea,
    input tcb_t             dina,
    output tcb_t            douta,

    input logic [5:0]       addrb,
    output tcb_t            doutb
);

localparam int TCB_WIDTH = 392;

xpm_memory_tdpram #(
    .ADDR_WIDTH_A        (6),
    .ADDR_WIDTH_B        (6),
    .AUTO_SLEEP_TIME     (0),
    .BYTE_WRITE_WIDTH_A  (TCB_WIDTH),
    .BYTE_WRITE_WIDTH_B  (TCB_WIDTH),
    .CLOCKING_MODE       ("independent_clock"),
    .ECC_MODE            ("no_ecc"),
    .MEMORY_INIT_FILE    ("none"),
    .MEMORY_INIT_PARAM   ("0"),
    .MEMORY_OPTIMIZATION ("true"),
    .MEMORY_PRIMITIVE    ("block"),
    .MEMORY_SIZE         (TCB_WIDTH * 64),
    .MESSAGE_CONTROL     (0),
    .READ_DATA_WIDTH_A   (TCB_WIDTH),
    .READ_DATA_WIDTH_B   (TCB_WIDTH),
    .READ_LATENCY_A      (1),
    .READ_LATENCY_B      (1),
    .READ_RESET_VALUE_A  ("0"),
    .READ_RESET_VALUE_B  ("0"),
    .RST_MODE_A          ("SYNC"),
    .RST_MODE_B          ("SYNC"),
    .SIM_ASSERT_CHK      (0),
    .USE_MEM_INIT        (0),
    .WAKEUP_TIME         ("disable_sleep"),
    .WRITE_DATA_WIDTH_A  (TCB_WIDTH),
    .WRITE_DATA_WIDTH_B  (TCB_WIDTH),
    .WRITE_MODE_A        ("write_first"),
    .WRITE_MODE_B        ("write_first")
) tcb_mem (
    .clka           (clk),
    .clkb           (clk),
    .ena            (1'b1),
    .enb            (1'b1),
    .addra          (addra),
    .addrb          (addrb),
    .dina           (dina),
    .dinb           ('0),
    .wea            (wea),
    .web            (1'b0),
    .douta          (douta),
    .doutb          (doutb),
    .regcea         (1'b1),
    .regceb         (1'b1),
    .rsta           (rst),
    .rstb           (rst),
    .sleep          (1'b0)
);

endmodule
