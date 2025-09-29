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

    localparam S_IDLE        = 2'b00;
    localparam S_BUSY_LRCW   = 2'b01;
    localparam S_BUSY_INPUT  = 2'b10;
    localparam S_BUSY_OUTPUT = 2'b11;

    localparam C_1 = 16'sh00ab;
    localparam C_2 = 16'sh0009;

    integer i, j;

/*--------------------------------------------------- registers and wires---------------------------------------------------*/

    reg output_valid_r;
    reg output_busy_r;
    reg [3:0] matrix_counter;
    reg [4:0] cpop_r;
    reg [1:0] state_r;
    reg [1:0] next_state_r;
    reg [35:0] data_acc_r;
    reg [1:0] matrix_mem_r [0:7][0:7];
    reg signed [DATA_W-1:0] signed_o_data_r;

    // 0000: sum
    wire signed [DATA_W:0] sum_w = i_data_a + i_data_b;
    // 0001: sub
    wire signed [DATA_W:0] diff_w = i_data_a - i_data_b;
    // 0010: mac
    wire signed [35:0] data_acc_w = data_acc_r;
    wire signed [36:0] mul_w = i_data_a * i_data_b;
    wire signed [36:0] mac_w = mul_w + data_acc_w;
    wire signed [16:0] rounded_mac_w = (mac_w + (1 <<< 9)) >>> 10;
    // 0011: sin
    wire signed [96:0] sin_x1_temp_w = $signed(i_data_a);
    wire signed [96:0] sin_x3_temp_w = $signed(C_1) * $signed(i_data_a) * $signed(i_data_a) * $signed(i_data_a);
    wire signed [96:0] sin_x1_w = sin_x1_temp_w <<< 50;
    wire signed [96:0] sin_x3_w = sin_x3_temp_w <<< 20;
    wire signed [96:0] sin_x5_w = $signed(C_2) * $signed(i_data_a) * $signed(i_data_a) * $signed(i_data_a) * $signed(i_data_a) * $signed(i_data_a);
    wire signed [96:0] sin_w = sin_x1_w - sin_x3_w + sin_x5_w;
    wire signed [16:0] rounded_sin_w = (sin_w + (97'sd1 <<< 49)) >>> 50;
    // 0110: right rotation
    wire [31:0] i_data_a_con = {2{i_data_a}};
    
    assign o_out_valid = output_valid_r;
    assign o_busy = output_busy_r;
    assign o_data = signed_o_data_r;

/*--------------------------------------------------------- comb loop ---------------------------------------------------*/

    always @(*) begin
        next_state_r = state_r;
        case (state_r)
            S_IDLE: begin
                if (i_in_valid) begin
                    case (i_inst)
                        4'b0101: next_state_r = S_BUSY_LRCW;
                        4'b1001: next_state_r = S_BUSY_INPUT;
                        default: next_state_r = S_IDLE;
                    endcase
                end
            end
            S_BUSY_LRCW: begin
                if (cpop_r == 0) next_state_r = S_IDLE;
            end
            S_BUSY_INPUT: begin
                if (matrix_counter == 7 && i_in_valid) next_state_r = S_BUSY_OUTPUT;
                else next_state_r = S_BUSY_INPUT;
            end
            S_BUSY_OUTPUT: begin
                if (matrix_counter == 8) next_state_r = S_IDLE;
                else next_state_r = S_BUSY_OUTPUT;
            end
        endcase
    end

/*--------------------------------------------------------- sequ loop ---------------------------------------------------*/

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            state_r <= S_IDLE;
        else
            state_r <= next_state_r;
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            output_valid_r   <= 0;
            output_busy_r    <= 0;
            signed_o_data_r  <= 0;
            cpop_r           <= 0;
            matrix_counter   <= 0;
            data_acc_r       <= 0;
            for (i = 0; i < 8; i = i + 1) begin
                for (j = 0; j < 8; j = j + 1) begin
                    matrix_mem_r[i][j] <= 0;
                end
            end
        end
        else begin
            case (state_r)
                S_IDLE: begin
                    output_valid_r <= 0;
                    if (i_in_valid) begin
                        case (i_inst)
                            4'b0000: signed_o_data_r <= overflow_check(sum_w);
                            4'b0001: signed_o_data_r <= overflow_check(diff_w);
                            4'b0010: begin
                                data_acc_r       <= long_overflow_check(mac_w);
                                signed_o_data_r  <= overflow_check(rounded_mac_w);
                            end
                            4'b0011: signed_o_data_r <= overflow_check(rounded_sin_w);
                            4'b0100: begin
                                signed_o_data_r[15] <= i_data_a[15];
                                for (i = 14; i >= 0; i = i - 1)
                                    signed_o_data_r[i] <= i_data_a[i+1] ^ i_data_a[i];
                            end
                            4'b0101: begin
                                cpop_r          <= cpop_count(i_data_a);
                                signed_o_data_r <= i_data_b;
                                output_busy_r   <= 1;
                            end
                            4'b0110: signed_o_data_r <= (i_data_b >= 16) ? i_data_a : i_data_a_con[i_data_b[3:0] +: 16];
                            4'b0111: signed_o_data_r <= count_leading_zero(i_data_a);
                            4'b1000: signed_o_data_r <= reverse_match4(i_data_a, i_data_b);
                            4'b1001: begin
                                for (i = 0; i < 8; i = i + 1) begin
                                    matrix_mem_r[i][0] <= i_data_a[(i<<1)+:2];
                                end
                                matrix_counter <= 1;
                            end
                        endcase
                        output_valid_r <= (i_inst != 4'b0101 && i_inst != 4'b1001);
                    end
                end

                S_BUSY_LRCW: begin
                    if (cpop_r != 0) begin
                        signed_o_data_r <= {signed_o_data_r[14:0], !signed_o_data_r[15]};
                        cpop_r          <= cpop_r - 1;
                    end else begin
                        output_valid_r <= 1;
                        output_busy_r  <= 0;
                    end
                end

                S_BUSY_INPUT: begin
                    if (i_in_valid) begin
                        for (i = 0; i < 8; i = i + 1) begin
                            matrix_mem_r[i][matrix_counter[2:0]] <= i_data_a[(i<<1)+:2];
                        end
                        if (matrix_counter == 7) begin
                            matrix_counter <= 0;
                            output_busy_r <= 1;
                        end
                        else begin
                            matrix_counter <= matrix_counter + 1;
                        end
                    end
                end

                S_BUSY_OUTPUT: begin
                    if (matrix_counter < 8) begin
                        signed_o_data_r <= {
                            matrix_mem_r[7-matrix_counter[2:0]][0], matrix_mem_r[7-matrix_counter[2:0]][1],
                            matrix_mem_r[7-matrix_counter[2:0]][2], matrix_mem_r[7-matrix_counter[2:0]][3],
                            matrix_mem_r[7-matrix_counter[2:0]][4], matrix_mem_r[7-matrix_counter[2:0]][5],
                            matrix_mem_r[7-matrix_counter[2:0]][6], matrix_mem_r[7-matrix_counter[2:0]][7]
                        };
                        matrix_counter  <= matrix_counter + 1;
                        output_valid_r  <= 1;
                        output_busy_r <= 1;
                    end else begin
                        matrix_counter <= 0;
                        output_valid_r <= 0;
                        output_busy_r  <= 0;
                    end
                end
            endcase
        end
    end


/*--------------------------------------------------------- function ----------------------------------------------------*/

    function automatic signed [DATA_W-1:0] overflow_check;

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

    function automatic signed [35:0] long_overflow_check;

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

    function automatic [4:0] cpop_count;

        input [DATA_W-1:0] i_data;
        integer i;
        begin
            cpop_count = 0;
            for (i = 0; i < 16; i = i + 1) begin
                cpop_count = cpop_count + (i_data[i] ? 5'd1 : 5'd0);
            end
        end
        
    endfunction

    function automatic [4:0] count_leading_zero;
        
        input [15:0] i_data;
        reg stop;
        integer i;
        begin
            stop = 0;
            count_leading_zero = 0;
            for (i = 15; i >= 0; i = i - 1) begin
                if (!stop) begin
                    if (!i_data_a[i]) count_leading_zero = count_leading_zero + 1;
                    else stop = 1;
                end
                else begin
                    
                end
            end
        end
        
    endfunction

    function automatic [15:0] reverse_match4;

        input [15:0] i_data_a;
        input [15:0] i_data_b;
        integer i;

        begin
            for (i = 0; i < 13; i = i + 1) begin
                reverse_match4[i] = (i_data_a[i+:4] == i_data_b[15-i-:4]);
            end
            reverse_match4[15:13] = 3'b000;
        end

    endfunction

endmodule
