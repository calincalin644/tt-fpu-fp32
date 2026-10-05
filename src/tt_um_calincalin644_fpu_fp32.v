`default_nettype none
// Bundled-data request/acknowledge toggle protocol; see docs/fpga.md.
module tt_um_calincalin644_fpu_fp32 (
    input wire [7:0] ui_in, output reg [7:0] uo_out,
    input wire [7:0] uio_in, output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input wire ena, clk, rst_n
);
    wire _unused = &{uio_in[7:6], 1'b0};
    reg req_meta, req_sync, ack;
    reg [31:0] a, b, result;
    reg [4:0] flags;
    reg [2:0] command, rounding;
    reg busy, done, error;
    wire [31:0] core_result, core_fixed;
    wire [4:0] core_flags;
    wire core_finish;
    wire core_reset_n = rst_n & ena;
    flpoint_iterative core (
        .clk_i(clk), .rst_n_i(core_reset_n), .first_term_i(a), .second_term_i(b),
        .fixed_term_i(a), .cmd_i(command), .fcsr_frm_i(rounding),
        .result_o(core_result), .fixed_result_o(core_fixed),
        .fcsr_fflags_o(core_flags), .finish_stb_o(core_finish)
    );
    assign uio_oe = 8'hc0;
    assign uio_out = {busy,ack,6'b0};
    always @(posedge clk) begin
        if (!rst_n || !ena) begin
            req_meta<=0; req_sync<=0; ack<=0; uo_out<=0;
            a<=0; b<=0; result<=0; flags<=0; command<=0; rounding<=0;
            busy<=0; done<=0; error<=0;
        end else begin
            req_meta<=uio_in[0];
            req_sync<=req_meta;
            if (busy && core_finish) begin
                result <= command==6 ? core_fixed : core_result;
                flags<=core_flags; busy<=0; done<=1; command<=0;
            end
            if (req_sync != ack) begin
                ack<=req_sync;
                if (uio_in[1]) begin
                    case (uio_in[5:2])
                        0,1,2,3: uo_out<=a[8*uio_in[3:2] +: 8];
                        4,5,6,7: uo_out<=b[8*uio_in[3:2] +: 8];
                        8: uo_out<={2'b0,rounding,command};
                        9: uo_out<=result[7:0];
                        10: uo_out<=result[15:8];
                        11: uo_out<=result[23:16];
                        12: uo_out<=result[31:24];
                        13: uo_out<={3'b0,flags};
                        14: uo_out<={5'b0,error,done,busy};
                        15: uo_out<=8'hf1;
                    endcase
                end else if (busy) error<=1;
                else begin
                    case (uio_in[5:2])
                        0,1,2,3: a[8*uio_in[3:2] +: 8]<=ui_in;
                        4,5,6,7: b[8*uio_in[3:2] +: 8]<=ui_in;
                        8: begin
                            if (ui_in[2:0] != 0 && ui_in[7:6] == 0) begin
                                command<=ui_in[2:0]; rounding<=ui_in[5:3];
                                busy<=1; done<=0; error<=0;
                            end else error<=1;
                        end
                        14: begin done<=0; error<=0; end
                        default: error<=1;
                    endcase
                end
            end
        end
    end
endmodule
`default_nettype wire
