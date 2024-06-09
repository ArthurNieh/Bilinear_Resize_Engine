module interpolation (
    input           clk,
    input           RST,
    input           START,
    input   [5:0]   H0,
    input   [5:0]   V0,
    input   [3:0]   SW,
    input   [3:0]   SH,
    output          REN,
    input   [7:0]   R_DATA,
    output  [11:0]  ADDR,
    output  [7:0]   O_DATA,
    output          O_VALID
);

reg [5:0] reg_H0, reg_H0_next;
reg [5:0] reg_V0, reg_V0_next;
reg [3:0] reg_SW, reg_SW_next;
reg [3:0] reg_SH, reg_SH_next;

reg [11:0] reg_ADDR, reg_ADDR_next;
reg        output_valid, output_valid_next; // maybe can reduce
reg        done, done_next; // active low: 0 means done
assign ADDR = reg_ADDR;
assign REN = 1'b0;
assign O_VALID = output_valid;

reg [9:0] width_sum, width_sum_next;
reg [9:0] height_sum, height_sum_next;
wire [5:0] X_lower, X_upper, Y_lower, Y_upper;
reg [5:0] last_y_row, last_y_row_next; // keep the last y row for FSM
reg x_divide, y_divide, x_divide_next, y_divide_next;
assign X_lower = width_sum[9:4];
assign X_upper = x_divide_next ? width_sum[9:4] : width_sum[9:4] + 1;
assign Y_lower = height_sum[9:4];
assign Y_upper = y_divide_next ? height_sum[9:4] : height_sum[9:4] + 1;

wire [5:0] next_X_lower, next_X_upper, next_Y_lower, next_Y_upper;
assign next_X_lower = width_sum_next[9:4];
assign next_X_upper = (width_sum_next[3:0] == 0) ? width_sum_next[9:4] : width_sum_next[9:4] + 1;
assign next_Y_lower = height_sum_next[9:4];
assign next_Y_upper = (height_sum_next[3:0] == 0) ? height_sum_next[9:4] : height_sum_next[9:4] + 1;

reg [3:0] x_ratio, x_ratio_next; // keep the ration of x insertion
reg [3:0] y_ratio, y_ratio_next; // keep the ration of y insertion
wire [7:0] left_margin, right_margin;

reg [7:0] data_y_lower [0:1];
reg [7:0] data_y_lower_next [0:1];
reg [7:0] data_y_upper [0:1];
reg [7:0] data_y_upper_next [0:1];
reg [4:0] count_cycle, count_cycle_next;

// FSM for interpolation
reg [1:0] pre_pre_state, pre_state, state, state_next;
wire pre_pre_state_is_11, pre_pre_state_is_10, pre_pre_state_is_01, pre_pre_state_is_00;
assign pre_pre_state_is_11 = pre_pre_state[1] & pre_pre_state[1];
assign pre_pre_state_is_00 = ~pre_pre_state[1] & ~pre_pre_state[0];
wire [5:0] x_ADDR, y_ADDR;
assign x_ADDR = state[1] ? X_upper : X_lower;
assign y_ADDR = state[0] ? Y_upper : Y_lower;

// Sub modules
    Cal_Interpolation cal_inter_left (
        .DATA_1(data_y_lower[0]),
        .DATA_2(data_y_upper[0]),
        .ratio(y_ratio),
        .Out_DATA(left_margin)
    );
    Cal_Interpolation cal_inter_right (
        .DATA_1(data_y_lower[1]),
        .DATA_2(data_y_upper[1]),
        .ratio(y_ratio),
        .Out_DATA(right_margin)
    );
    Cal_Interpolation cal_inter (
        .DATA_1(left_margin),
        .DATA_2(right_margin),
        .ratio(x_ratio),
        .Out_DATA(O_DATA)
    );

always @(*)begin
    count_cycle_next = count_cycle;
    case(state)
        2'b00: begin
            if(y_divide_next | x_divide_next) begin
                state_next = 2'b11;
            end
            else begin
                state_next = 2'b01;
            end
        end
        2'b01: begin
            state_next = 2'b10;
        end
        2'b10: begin
            state_next = 2'b11;
        end
        2'b11: begin
            count_cycle_next = (count_cycle == 5'd16) ? 0 : count_cycle + 1;
            if(X_lower == next_X_lower && Y_upper == next_Y_upper) begin
                state_next = (X_upper == next_X_upper) ? 2'b11 : 2'b01;
            end
            else if(X_upper == next_X_lower) begin
                state_next = 2'b10;
            end
            else begin
                state_next = 2'b00;
            end
        end
    endcase
end
always @(*)begin
    // state: current reading address
    reg_ADDR_next[5:0] = x_ADDR + reg_H0;
    reg_ADDR_next[11:6] = y_ADDR + reg_V0;
    output_valid_next = pre_state[1] & pre_state[0];
end
// save ROM data to local memory
always @(*)begin
    case(pre_state)
        2'b00: begin
            data_y_lower_next[0] = R_DATA;
            data_y_lower_next[1] = x_divide ? R_DATA : data_y_lower[1];
            data_y_upper_next[0] = y_divide ? R_DATA : data_y_upper[0];
            data_y_upper_next[1] = data_y_upper[1];
        end
        2'b01: begin
            data_y_upper_next[0] = R_DATA;
            data_y_lower_next[0] = data_y_lower[0];
            data_y_lower_next[1] = data_y_lower[1];
            data_y_upper_next[1] = data_y_upper[1];
        end
        2'b10: begin
            data_y_lower_next[1] = R_DATA;
            data_y_lower_next[0] = pre_pre_state_is_11 ? data_y_lower[1] : data_y_lower[0]; //x_divide ? R_DATA : 
            data_y_upper_next[0] = pre_pre_state_is_11 ? data_y_upper[1] : data_y_upper[0];
            data_y_upper_next[1] = data_y_upper[1];
        end
        2'b11: begin
            data_y_upper_next[1] = R_DATA;
            data_y_lower_next[1] = y_divide ? R_DATA : data_y_lower[1];
            data_y_upper_next[0] = x_divide ? R_DATA : data_y_upper[0];
            data_y_lower_next[0] = y_divide ? data_y_upper[0] :
                                    x_divide ? data_y_lower[1] : data_y_lower[0];
        end
    endcase
end
// save initial input data
always @(*)begin
    if(START) begin
        reg_H0_next = H0;
        reg_V0_next = V0;
        reg_SW_next = SW - 1;
        reg_SH_next = SH - 1;
    end
    else begin
        reg_H0_next = reg_H0;
        reg_V0_next = reg_V0;
        reg_SW_next = reg_SW;
        reg_SH_next = reg_SH;
    end
end
// calculate upper and lower bound of X and Y for each interpolation
always @(*)begin
    if(state == 2'b11) begin
        if(count_cycle == 5'd16) begin
            width_sum_next = 0;
            height_sum_next = height_sum + reg_SH;
        end
        else begin
            width_sum_next = width_sum + reg_SW;
            height_sum_next = height_sum;
        end
    end
    else begin
        width_sum_next = width_sum;
        height_sum_next = height_sum;
    end
    x_divide_next = (width_sum[3:0] == 0);
    y_divide_next = (height_sum[3:0] == 0);

    x_ratio_next = width_sum[3:0];
    y_ratio_next = height_sum[3:0];

    if(height_sum[9:4] == reg_V0_next) begin
        done_next = 0;
    end
    else begin
        done_next = 1;
    end
end

always @(negedge clk) begin
    reg_ADDR <= reg_ADDR_next;
    data_y_lower[0] <= data_y_lower_next[0];
    data_y_lower[1] <= data_y_lower_next[1];
    data_y_upper[0] <= data_y_upper_next[0];
    data_y_upper[1] <= data_y_upper_next[1];
    
    output_valid <= output_valid_next;
end

always @(posedge clk) begin
    if(RST | START) begin
        width_sum <= 0;
        height_sum <= 0;
        state <= 2'b00;
        pre_state <= 2'b00;
        pre_pre_state <= 2'b00;
        x_divide <= 0;
        y_divide <= 0;
        x_ratio <= 0;
        y_ratio <= 0;
        done <= 1;
        count_cycle <= 0;
    end
    else begin
        width_sum <= width_sum_next;
        height_sum <= height_sum_next;
        state <= state_next;
        pre_state <= state;
        pre_pre_state <= pre_state;
        x_divide <= x_divide_next;
        y_divide <= y_divide_next;
        x_ratio <= x_ratio_next;
        y_ratio <= y_ratio_next;
        done <= done_next;
        count_cycle <= count_cycle_next;
    end
    reg_H0 <= reg_H0_next;
    reg_V0 <= reg_V0_next;
    reg_SW <= reg_SW_next;
    reg_SH <= reg_SH_next;
end

endmodule

module Cal_Interpolation (
    input   [7:0]   DATA_1,
    input   [7:0]   DATA_2,
    input   [3:0]   ratio,
    output  [7:0]   Out_DATA
);
    reg [3:0] flip_ratio;
    wire [7:0] d1_3, d1_2, d1_1, d1_0, d2_3, d2_2, d2_1, d2_0;
    wire [11:0] output_inter;
    
    assign d1_3 = {8{flip_ratio[3]}} & DATA_1;
    assign d1_2 = {8{flip_ratio[2]}} & DATA_1;
    assign d1_1 = {8{flip_ratio[1]}} & DATA_1;
    assign d1_0 = {8{flip_ratio[0]}} & DATA_1;
    assign d2_3 = {8{ratio[3]}} & DATA_2;
    assign d2_2 = {8{ratio[2]}} & DATA_2;
    assign d2_1 = {8{ratio[1]}} & DATA_2;
    assign d2_0 = {8{ratio[0]}} & DATA_2;
    assign output_inter = {d1_3, 3'b000} + {d1_2, 2'b00} + {d1_1, 1'b0} + d1_0 
                        + {d2_3, 3'b000} + {d2_2, 2'b00} + {d2_1, 1'b0} + d2_0 ;
    assign Out_DATA = (ratio == 4'b0000) ? DATA_1 : output_inter[11:4];

    always @(*)begin
        flip_ratio = ~ratio[3:0] + 1;
    end
endmodule