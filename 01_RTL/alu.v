module alu #(
    parameter INST_W = 4,
    parameter INT_W  = 6,
    parameter FRAC_W = 10,
    parameter DATA_W = INT_W + FRAC_W
)(
    input                      i_clk,
    input                      i_rst_n,

    input                      i_in_valid,
    output                     o_busy,
    input         [INST_W-1:0] i_inst,
    input  signed [DATA_W-1:0] i_data_a,
    input  signed [DATA_W-1:0] i_data_b,

    output                     o_out_valid,
    output        [DATA_W-1:0] o_data
);

    localparam S_IDLE = 2'b00;
    localparam S_BUSY = 2'b01;
    localparam S_DONE = 2'b10;

/*--------------------------------------------------------- registers ---------------------------------------------------*/

    reg output_valid_r;
    reg output_busy_r;
    reg [1:0] state_r;
    reg [35:0] data_acc_r;
    reg [DATA_W-1:0] o_data_r;
    reg signed [DATA_W-1:0] signed_o_data_r;

    wire signed [DATA_W:0] sum_w = i_data_a + i_data_b;
    wire signed [DATA_W:0] diff_w = i_data_a - i_data_b;
    wire signed [35:0] data_acc_w = data_acc_r;
    wire signed [36:0] mul_w = i_data_a * i_data_b;
    wire signed [36:0] mac_w = mul_w + data_acc_w;
    wire signed [16:0] rounded_sum_w = (mac_w + (1 <<< 9)) >>> 10;
    
    assign o_out_valid = output_valid_r;
    assign o_busy = output_busy_r;
    assign o_data = (i_inst == 4'b0100) ? o_data_r : signed_o_data_r;

/*--------------------------------------------------------- comb loop ---------------------------------------------------*/

    always @(*) begin
        
    end

/*--------------------------------------------------------- sequ loop ---------------------------------------------------*/

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            output_valid_r <= 0;
            output_busy_r <= 0;
            data_acc_r <= 0;
            o_data_r <= 0;
            signed_o_data_r <= 0;
            state_r <= S_IDLE;
        end
        else if (i_in_valid) begin
            if (state_r == S_IDLE) begin
                case (i_inst)
                    4'b0000: begin
                        signed_o_data_r <= overflow_check(sum_w);
                        output_valid_r <= 1;
                    end
                    4'b0001: begin
                        signed_o_data_r <= overflow_check(diff_w);
                        output_valid_r <= 1;
                    end
                    4'b0010: begin
                        data_acc_r <= long_overflow_check(mac_w);
                        signed_o_data_r <= overflow_check(rounded_sum_w);
                        output_valid_r <= 1;
                    end
                    default: begin
                        output_valid_r <= output_valid_r;
                        signed_o_data_r <= signed_o_data_r;
                        o_data_r <= o_data_r;
                    end
                endcase
            end
        end
        else if (!i_in_valid) begin
            output_valid_r <= 0;
            signed_o_data_r <= signed_o_data_r;
            o_data_r <= o_data_r;
        end
    end

/*--------------------------------------------------------- function ----------------------------------------------------*/

    function signed [DATA_W-1:0] overflow_check;

        input signed [DATA_W:0] i_data;

        begin
            if (i_data > 17'sd32767) begin
                overflow_check = 16'sh7FFF;
            end
            else if (i_data < -17'sd32768) begin
                overflow_check = -16'sh8000;
            end
            else begin
                overflow_check = i_data[15:0];
            end
        end
        
    endfunction

    function signed [35:0] long_overflow_check;

        input signed [36:0] i_data;

        begin
            if (i_data > 37'sd34359738367) begin
                long_overflow_check = 36'sh7FFFFFFFF;
            end
            else if (i_data < -37'sd34359738368) begin
                long_overflow_check = -36'sh800000000;
            end
            else begin
                long_overflow_check = i_data[35:0];
            end
        end
        
    endfunction

endmodule
