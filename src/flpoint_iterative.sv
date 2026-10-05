// Multi-cycle binary32 core. Same numerical contract as rtl.txt.
// One command is accepted until cmd_i=0 rearms; inputs captured on acceptance.
module flpoint_iterative (
    input wire clk_i, rst_n_i,
    input wire [31:0] first_term_i, second_term_i, fixed_term_i,
    input wire [2:0] cmd_i, fcsr_frm_i,
    output reg [4:0] fcsr_fflags_o,
    output reg [31:0] result_o,
    output reg finish_stb_o,
    output reg [31:0] fixed_result_o
);
    localparam [4:0] NV=16, DZ=8, OF=4, UF=2, NX=1;
    localparam [4:0] IDLE=0, NORMAL=1, SELECT=2, ADD_INIT=3, ALIGN=4,
        ADD=5, MUL=6, DIV=7, DIV_END=8, PACK=9, NORMAL_RESULT=10,
        DENORMAL=11, ROUND=12, FIX_SHIFT=13, FIX_ROUND=14, FINISH=15;
    reg [4:0] state;
    reg armed, sa, sb, sign_result, tiny;
    reg [2:0] op, rm;
    reg [23:0] ma, mb;
    reg signed [10:0] ea, eb, scale, exponent;
    reg [9:0] count;
    reg [63:0] magnitude;
    reg [26:0] aligned;
    reg [24:0] remainder;
    reg [31:0] packed_result;
    reg [4:0] exceptions;
    wire [31:0] a=first_term_i, b=second_term_i;
    wire na=(&a[30:23]) && (|a[22:0]);
    wire nb=(&b[30:23]) && (|b[22:0]);
    wire sna=na && !a[22], snb=nb && !b[22];
    wire ia=a[30:0]==31'h7f800000, ib=b[30:0]==31'h7f800000;
    wire za=a[30:0]==0, zb=b[30:0]==0;
    wire effective_sb=b[31] ^ (cmd_i==2);
    wire [24:0] mul_sum={1'b0,magnitude[47:24]}+(magnitude[0]?{1'b0,ma}:25'b0);
    wire [24:0] div_difference=remainder-{1'b0,mb};
    reg round_up;
    always @* begin
        case (rm)
            0: round_up=magnitude[2] && ((|magnitude[1:0]) || magnitude[3]);
            1: round_up=0;
            2: round_up=sign_result && (|magnitude[2:0]);
            3: round_up=!sign_result && (|magnitude[2:0]);
            4: round_up=magnitude[2];
            default: round_up=0;
        endcase
    end
    wire [31:0] rounded={1'b0,magnitude[33:3]}+{31'b0,round_up};
    wire signed [10:0] final_exponent=exponent+(rounded[24]?11'sd1:11'sd0);
    wire signed [10:0] biased_exponent=final_exponent+11'sd127;
    wire [7:0] encoded_exponent=biased_exponent[7:0];
    wire [10:0] exponent_delta=ea-eb;
    wire _unused = &{biased_exponent[10:8], exponent_delta[10], div_difference[24], 1'b0};
    wire to_inf=(rm==0 || rm==4 || (rm==2 && sign_result) || (rm==3 && !sign_result));
    wire [63:0] jammed={1'b0,magnitude[63:2],magnitude[1]|magnitude[0]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state<=IDLE; armed<=1; finish_stb_o<=0; fcsr_fflags_o<=0;
            result_o<=0; fixed_result_o<=0; sa<=0; sb<=0; sign_result<=0;
            tiny<=0; op<=0; rm<=0; ma<=0; mb<=0; ea<=0; eb<=0;
            scale<=0; exponent<=0; count<=0; magnitude<=0; aligned<=0;
            remainder<=0; packed_result<=0; exceptions<=0;
        end else begin
            finish_stb_o<=0;
            case (state)
                IDLE: begin
                    if (cmd_i==0) armed<=1;
                    else if (armed) begin
                        armed<=0; op<=cmd_i; rm<=fcsr_frm_i; exceptions<=0;
                        sa<=a[31]; sb<=effective_sb; sign_result<=a[31]^b[31];
                        ma<={a[30:23]!=0,a[22:0]}; mb<={b[30:23]!=0,b[22:0]};
                        ea<=za ? -11'sd149 : (a[30:23]==0 ? -11'sd126 : $signed({3'b0,a[30:23]})-11'sd127);
                        eb<=zb ? -11'sd149 : (b[30:23]==0 ? -11'sd126 : $signed({3'b0,b[30:23]})-11'sd127);
                        state<=NORMAL;
                        if (fcsr_frm_i>4 || cmd_i==7) begin
                            packed_result<=cmd_i==6 ? 32'h7fffffff : 32'h7fc00000;
                            exceptions<=NV; state<=FINISH;
                        end else if (cmd_i==5) begin
                            magnitude<={33'b0,fixed_term_i[30:0]}; scale<=-11'sd15;
                            sign_result<=fixed_term_i[31]; state<=PACK;
                        end else if (cmd_i==6) begin
                            sign_result<=a[31];
                            if (na || ia) begin
                                packed_result<=na ? 32'h7fffffff : {a[31],31'h7fffffff};
                                exceptions<=NV; state<=FINISH;
                            end
                        end else if (na || nb) begin
                            packed_result<=32'h7fc00000; exceptions<=(sna||snb)?NV:5'b0;
                            state<=FINISH;
                        end else if (cmd_i==1 || cmd_i==2) begin
                            if (ia || ib) begin
                                state<=FINISH;
                                if (ia && ib && a[31]!=effective_sb) begin
                                    packed_result<=32'h7fc00000; exceptions<=NV;
                                end else packed_result<={ia?a[31]:effective_sb,31'h7f800000};
                            end
                        end else if (cmd_i==3) begin
                            if ((ia && zb) || (ib && za)) begin
                                packed_result<=32'h7fc00000; exceptions<=NV; state<=FINISH;
                            end else if (ia || ib) begin
                                packed_result<={a[31]^b[31],31'h7f800000}; state<=FINISH;
                            end
                        end else if (cmd_i==4) begin
                            if ((za && zb) || (ia && ib)) begin
                                packed_result<=32'h7fc00000; exceptions<=NV; state<=FINISH;
                            end else if (ia) begin
                                packed_result<={a[31]^b[31],31'h7f800000}; state<=FINISH;
                            end else if (ib || za) begin
                                packed_result<={a[31]^b[31],31'b0}; state<=FINISH;
                            end else if (zb) begin
                                packed_result<={a[31]^b[31],31'h7f800000};
                                exceptions<=DZ; state<=FINISH;
                            end
                        end
                    end
                end
                NORMAL: begin
                    if (ma!=0 && !ma[23]) begin ma<=ma<<1; ea<=ea-1'b1; end
                    if (mb!=0 && !mb[23]) begin mb<=mb<<1; eb<=eb-1'b1; end
                    if ((ma==0 || ma[23]) && (mb==0 || mb[23])) state<=SELECT;
                end
                SELECT: begin
                    case (op)
                        1,2: begin
                            if (ea<eb || (ea==eb && ma<mb)) begin
                                ma<=mb; mb<=ma; ea<=eb; eb<=ea; sa<=sb; sb<=sa;
                            end
                            state<=ADD_INIT;
                        end
                        3: begin
                            magnitude<={40'b0,mb}; count<=24;
                            scale<=ea+eb-11'sd46; state<=MUL;
                        end
                        4: begin
                            magnitude<=0; remainder<={1'b0,ma}; count<=28;
                            scale<=ea-eb-11'sd27; state<=DIV;
                        end
                        6: begin
                            if (ma!=0 && ea>=16) begin
                                packed_result<={sa,31'h7fffffff}; exceptions<=NV; state<=FINISH;
                            end else begin
                                magnitude<={37'b0,ma,3'b0}; scale<=ea-11'sd8; state<=FIX_SHIFT;
                            end
                        end
                        default: state<=IDLE;
                    endcase
                end
                ADD_INIT: begin
                    magnitude<={37'b0,ma,3'b0}; aligned<={mb,3'b0};
                    count<=exponent_delta[9:0]; scale<=ea-11'sd26; sign_result<=sa; state<=ALIGN;
                end
                ALIGN: begin
                    if (count!=0) begin
                        aligned<={1'b0,aligned[26:2],aligned[1]|aligned[0]}; count<=count-1'b1;
                    end else state<=ADD;
                end
                ADD: begin
                    magnitude<=sa==sb ? magnitude+{37'b0,aligned} : magnitude-{37'b0,aligned};
                    if (sa!=sb && magnitude=={37'b0,aligned}) sign_result<=rm==2;
                    state<=PACK;
                end
                MUL: begin
                    magnitude<={16'b0,mul_sum,magnitude[23:1]}; count<=count-1'b1;
                    if (count==1) state<=PACK;
                end
                DIV: begin
                    if (remainder>={1'b0,mb}) begin
                        magnitude<={magnitude[62:0],1'b1}; remainder<=div_difference<<1;
                    end else begin
                        magnitude<=magnitude<<1; remainder<=remainder<<1;
                    end
                    count<=count-1'b1;
                    if (count==1) state<=DIV_END;
                end
                DIV_END: begin
                    magnitude[0]<=magnitude[0] || remainder!=0; state<=PACK;
                end
                PACK: begin
                    exponent<=scale+11'sd26; tiny<=0;
                    if (magnitude==0) begin packed_result<={sign_result,31'b0}; state<=FINISH; end
                    else state<=NORMAL_RESULT;
                end
                NORMAL_RESULT: begin
                    if (|magnitude[63:27]) begin magnitude<=jammed; exponent<=exponent+1'b1; end
                    else if (!magnitude[26]) begin magnitude<=magnitude<<1; exponent<=exponent-1'b1; end
                    else begin tiny<=exponent < -126; state<=DENORMAL; end
                end
                DENORMAL: begin
                    if (exponent < -126) begin magnitude<=jammed; exponent<=exponent+1'b1; end
                    else state<=ROUND;
                end
                ROUND: begin
                    exceptions<=(|magnitude[2:0]) ? NX|(tiny?UF:5'b0) : 5'b0;
                    if (final_exponent>127) begin
                        packed_result<=to_inf ? {sign_result,31'h7f800000} : {sign_result,31'h7f7fffff};
                        exceptions<=OF|NX;
                    end else if (rounded[24]) packed_result<={sign_result,encoded_exponent,rounded[23:1]};
                    else if (!rounded[23]) packed_result<={sign_result,8'b0,rounded[22:0]};
                    else packed_result<={sign_result,encoded_exponent,rounded[22:0]};
                    state<=FINISH;
                end
                FIX_SHIFT: begin
                    if (scale<0) begin magnitude<=jammed; scale<=scale+1'b1; end
                    else if (scale>0) begin magnitude<=magnitude<<1; scale<=scale-1'b1; end
                    else state<=FIX_ROUND;
                end
                FIX_ROUND: begin
                    if (rounded[31]) begin packed_result<={sign_result,31'h7fffffff}; exceptions<=NV; end
                    else begin packed_result<={sign_result,rounded[30:0]}; exceptions<=(|magnitude[2:0])?NX:5'b0; end
                    state<=FINISH;
                end
                FINISH: begin
                    if (op==6) fixed_result_o<=packed_result; else result_o<=packed_result;
                    fcsr_fflags_o<=exceptions; finish_stb_o<=1; state<=IDLE;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
