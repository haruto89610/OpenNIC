// Copyright (c) 2026 Haruto Iguchi. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-RTL-NIC-Educational-Academic-Hobby-1.1
//
// Licensed only under the RTL-NIC Educational, Academic, and Hobby License
// Version 1.1. See the LICENSE file in the repository root.
// Commercial use is prohibited. Narrow for-profit employment evaluation is
// permitted only as stated in Section 1(d) of the license.

`timescale 1ns / 1ps

import packages::*;
module router(
    // ---------------------------------- DATA INPUTS
    input logic         valid_in,
    input tcb_t         tcb_in,
    input header_t      header_in,
    input logic [1:0]   path,

    // ---------------------------------- ROUTE OUTPUTS
    output logic        tcp_ctrl_valid,
    output logic        app_ctrl_valid,
    output logic        establish_ctrl_valid
);

always_comb begin
    tcp_ctrl_valid          = '0;
    app_ctrl_valid          = '0;
    establish_ctrl_valid    = '0;

    if (valid_in) begin
        if (path == 2'd2) begin
            app_ctrl_valid = '1;
        end
        else if (path == 2'd3) begin
            app_ctrl_valid = (tcb_in.tcp_curr_t == ESTABLISHED);
        end
        else if (tcb_in.tcp_curr_t != ESTABLISHED ||
            header_in.tcp_csr.rst ||
            header_in.tcp_csr.syn ||
            header_in.tcp_csr.fin) begin
            tcp_ctrl_valid = '1;
        end
        else begin
            establish_ctrl_valid = '1;
        end
    end
end

endmodule
