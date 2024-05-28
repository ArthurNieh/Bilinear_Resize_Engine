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

reg [5:0] X_lower, X_lower_next; 
reg [5:0] X_upper, X_upper_next;
reg [5:0] Y_lower, Y_lower_next;
reg [5:0] Y_upper, Y_upper_next;
reg [9:0] width_sum, width_sum_next;
reg [9:0] height_sum, height_sum_next;

reg [11:0] reg_ADDR, reg_ADDR_next;
reg       reg_REN, reg_REN_next;
assign ADDR = reg_ADDR;
assign REN = reg_REN;

reg right_ready, right_ready_next;
wire x_same_left, x_left_right;
assign x_same_left = (X_lower_next == X_lower); // next left == left
assign x_left_right = (X_lower_next == X_upper);// next left == right

always @(*)begin
    if(START) begin
        reg_H0_next = H0;
        reg_V0_next = V0;
        reg_SW_next = SW;
        reg_SH_next = SH;
    end
    else begin
        reg_H0_next = reg_H0;
        reg_V0_next = reg_V0;
        reg_SW_next = reg_SW;
        reg_SH_next = reg_SH;
    end
end

always @(*)begin
    if(width_sum[9:4] == SW) begin
        width_sum_next = 0;
        height_sum_next = height_sum + SH;
    end
    else begin
        width_sum_next = width_sum + SW;
        height_sum_next = height_sum;
    end
end

always @(*)begin
    X_lower_next = width_sum[9:4];
    X_upper_next = (width_sum[3:0] == 0) ? width_sum[9:4] : width_sum[9:4] + 1;
    Y_lower_next = height_sum[9:4];
    Y_upper_next = (height_sum[3:0] == 0) ? height_sum[9:4] : height_sum[9:4] + 1;
end

always @(*)begin
    case ({x_same_left, x_left_right})
        2'b11: begin // current left right are the same
            reg_ADDR_next = {X_upper_next, Y_lower_next};
            reg_REN_next = 0;       // read right margin of next vertex
            right_ready_next = 1;   // ready to read right margin of next vertex
        end
        2'b10: begin // fall into the same block as last one
            reg_ADDR_next = reg_ADDR;
            reg_REN_next = 1;       // don't need to read
            right_ready_next = 1;   // right margin of next vertex is ready
        end
        2'b01: begin // next left == current right
            reg_ADDR_next = {X_upper_next, Y_lower_next};
            reg_REN_next = 0;       // read right margin of next vertex
            right_ready_next = 1;   // ready to read right margin of next vertex
        end
        2'b00: begin // next left > current right
            reg_ADDR_next = {X_lower_next, Y_lower_next};
            reg_REN_next = 0;       // read left margin of next vertex
            right_ready_next = 0;   // not ready to read right margin of next vertex
        end
        default: 
    endcase
        
    end
    
end
always @(posedge clk) begin
    if(RST or START) begin
        width_sum <= 0;
        height_sum <= 0;
        X_lower <= 0;
        X_upper <= 0;
        Y_lower <= 0;
        Y_upper <= 0;
    end
    else begin
        width_sum <= width_sum_next;
        height_sum <= height_sum_next;
        X_lower <= X_lower_next;
        X_upper <= X_upper_next;
        Y_lower <= Y_lower_next;
        Y_upper <= Y_upper_next;
    end
    reg_H0 <= reg_H0_next;
    reg_V0 <= reg_V0_next;
    reg_SW <= reg_SW_next;
    reg_SH <= reg_SH_next;
end

endmodule