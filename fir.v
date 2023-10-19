module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,    

    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  wire                     ss_tready, 

    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);


parameter idle = 2'd0;
parameter operation = 2'd1;
parameter complete = 2'd2;
parameter done = 2'd3;

reg [1:0] state_current,state_next;
reg [4:0] cnt_cal;
reg [9:0] cnt_fir;
reg [9:0] data_length;

reg AW_ready,W_ready,AR_ready,R_valid;
reg AW_handshake,W_handshake,AR_handshake,R_handshake;

reg [pADDR_WIDTH-1:0] AW_addr,AR_addr;
reg [pDATA_WIDTH-1:0] W_data,R_data; 

reg TAP_EN;
reg [3:0] TAP_WE;
reg [(pDATA_WIDTH-1):0] TAP_DI;
reg [(pDATA_WIDTH-1):0] TAP_ADDR;

reg DATA_EN;
reg [3:0] DATA_WE;
reg [(pDATA_WIDTH-1):0] DATA_DI;
reg [(pADDR_WIDTH-1):0] DATA_ADDR;

reg signed [(pDATA_WIDTH-1):0] fir_out;

reg SS_ready;
reg SM_valid,SM_last;
reg [pDATA_WIDTH-1 : 0] SM_data;
reg [3:0] cnt_reset;
reg signed [(pDATA_WIDTH-1):0] SS_data;
reg [2:0] ap_reg_r,ap_reg_w;

assign ss_tready = SS_ready;
assign awready = AW_ready;
assign wready = W_ready;
assign arready = AR_ready;
assign rvalid = R_valid;
assign rdata = R_data;
assign sm_tvalid = SM_valid;
assign sm_tdata = SM_data;
assign sm_tlast = SM_last;

always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n)
        state_current <= 2'd0;
    else
        state_current <= state_next;
end

always @(*) begin
    state_next = state_current;
    case(state_current)
    idle : begin
        if(ap_reg_r[0])
            state_next = operation;
        end
    operation : begin
        if(cnt_fir == 10'd599 && cnt_cal == 5'd21)
            state_next = complete;
    end
    complete : begin
        if(sm_tready && sm_tvalid)
            state_next = done;
    end
    done : begin
        state_next = idle;
    end
    endcase
end

always@(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n) begin
        AW_ready <= 0;
        W_ready <= 0;
        AR_ready <= 0;
        R_valid <= 0;
        AW_handshake <= 0;
        W_handshake <= 0;
        AR_handshake <= 0;
        R_handshake <= 0;
        AW_addr <= 0;
        W_data <= 0;
        AR_addr <= 0;
    end
    else begin
        if(!(awvalid && awready) && !AW_handshake)
            AW_ready <= 1;
        else 
            AW_ready <= 0;

        if(!(wvalid && wready) && !W_handshake)
            W_ready <= 1;
        else
            W_ready <= 0;
        
        if(!(arvalid && arready) && !AR_handshake)
            AR_ready <= 1;
        else 
            AR_ready <= 0;

        if(AR_handshake && R_handshake)
            R_valid <= 0;
        else if(AR_handshake && !rvalid)
            R_valid <= 1;
        else if(rvalid && rready)
            R_valid <= 0;
        else 
            R_valid <= R_valid;

        if(AW_handshake && W_handshake)
            AW_handshake <= 0;
        else if(awvalid && awready)
            AW_handshake <= 1;
        
        if(AW_handshake && W_handshake)
            W_handshake <= 0;
        else if(wvalid && wready)
            W_handshake <= 1;
        
        if(AR_handshake && R_handshake)
            AR_handshake <= 0;
        else if(arvalid && arready)
            AR_handshake <= 1;

        if(AR_handshake && R_handshake)
            R_handshake <= 0;
        else if(rvalid && rready)
            R_handshake <= 1;

        if(awvalid && awready)
            AW_addr <= awaddr;

        if(wvalid && wready)
            W_data <= wdata;
        else if(state_current == done)
            W_data <= 0;

        if(arvalid && arready)
            AR_addr <= araddr;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n) begin
        ap_reg_r <= 3'b100;
        data_length <= 0;
    end
    else begin
        ap_reg_r <= ap_reg_w;
        if(AW_handshake && W_handshake && AW_addr > 12'h9 && AW_addr < 12'h15) begin
            data_length <= W_data;
        end

    end
end

always @(*) begin
    ap_reg_w = ap_reg_r;

    //ap_start
    if(AW_handshake && W_handshake && (AW_addr == 12'h0) && (state_current == idle)) begin
        ap_reg_w[0] = W_data;
    end
    else begin
        ap_reg_w[0] = 0;
    end

    //ap_done
    if(state_current == done) begin 
        if(rvalid && rready && AR_addr == 12'h00 && ap_reg_r[1])
            ap_reg_w[1] = 0;
        else
            ap_reg_w[1] = 1;
    end
    else if(state_current == idle) begin
        if(rvalid && rready && AR_addr == 12'h00 && ap_reg_r[1])
            ap_reg_w[1] = 0;
        else
            ap_reg_w[1] = ap_reg_r[1];
    end
    else 
        ap_reg_w[1] = 0;

    //ap_idle
    // if(cnt_fir == 599 && cnt_cal == 22)
    //     ap_reg_w[2] = 1;
    if(cnt_fir == 599 && cnt_cal == 21 && !ap_reg_r[2])
        ap_reg_w[2] = 1;
    else if(rvalid && rready && AR_addr == 12'h00 && ap_reg_r[2])
        ap_reg_w[2] = 0;
    else if(state_current == idle && state_next == operation)
        ap_reg_w[2] = 0;
     
end

always @(*) begin
    R_data = 0;
    if(AR_handshake) begin
        case(AR_addr)
        12'h00 : begin
            R_data = {29'd0,ap_reg_r};
        end
        12'h10,
        12'h11,
        12'h12,
        12'h13,
        12'h14 : begin
            R_data = {22'd0,data_length};
        end
        default : begin
            R_data = tap_Do;
        end
        endcase
    end
end

assign tap_WE = TAP_WE;
assign tap_EN = TAP_EN;
assign tap_Di = TAP_DI;
assign tap_A = TAP_ADDR;
assign data_Di = DATA_DI;
assign data_A = DATA_ADDR;
assign data_WE = DATA_WE;
assign data_EN = DATA_EN;

always @(*) begin
    TAP_WE = 0;
    TAP_EN = 0;
    TAP_ADDR = 0;
    TAP_DI = 0;
    DATA_WE = 0;
    DATA_EN = 0;
    DATA_DI = 0;
    DATA_ADDR = 0;

    if(state_current == operation) begin
        TAP_EN = 1;
        DATA_EN = 1;

        if(cnt_reset < 4'd11) begin 
            DATA_ADDR = cnt_reset << 2 ;
            DATA_DI = 0;
            DATA_WE = 4'b1111;
            DATA_EN = 1;
        end
        else if(cnt_cal[0]) begin     //odd
            DATA_ADDR = 44 - ( (cnt_cal >> 1) << 2);
            DATA_WE = 4'b1111;
            DATA_DI = data_Do;
        end
        else if(cnt_cal < 22)begin    //even
            DATA_ADDR = 40 - ( (cnt_cal >> 1) << 2);
            TAP_ADDR = DATA_ADDR;
        end 
        else begin
            DATA_ADDR = 4;
            DATA_WE = 4'b1111;
            DATA_DI = SS_data;
        end
    end
    else begin
        TAP_EN = 1;
        if(AW_handshake && W_handshake && awaddr[1:0] == 2'd0 && awaddr >= 12'h20) begin
            TAP_WE = 4'b1111;
            TAP_ADDR = AW_addr - 12'h20;
            TAP_DI = W_data;
        end
        else if(AR_handshake && araddr[1:0] == 2'd0 && araddr >= 12'h20) begin
            TAP_ADDR = AR_addr - 12'h20;
        end
    end
end


wire [(pDATA_WIDTH-1) : 0] mult_in;
assign mult_in = (cnt_cal == 21) ? SS_data : data_Do;

// always @(posedge axis_clk or negedge axis_rst_n) begin
//     if(!axis_rst_n) begin
//         fir_out <= 0;
//     end
//     else if(cnt_cal == 0) begin
//         fir_out <= 0;
//     end
//     else if(cnt_cal == 21) begin
//         fir_out <= fir_out + tap_Do * SS_data;
//     end
//     else if(cnt_cal[0])begin
//         fir_out <= fir_out + tap_Do * data_Do;
//     end
//     else
//         fir_out <= fir_out;
// end

always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n) begin
        fir_out <= 0;
    end
    else if(cnt_cal == 0) begin
        fir_out <= 0;
    end
    else if(cnt_cal == 21 || cnt_cal[0]) begin
        fir_out <= fir_out + tap_Do * mult_in;
    end
    else
        fir_out <= fir_out;
end



always @(*) begin
    SS_ready = 0;
    SM_valid = 0;
    SM_data = 0;
    SM_last = 0;
    
    if(state_current == operation && cnt_cal == 5'd0 && cnt_reset == 4'd11) begin
        SS_ready = 1;
    end

    if(cnt_cal == 22) begin
        SM_valid = 1;
        SM_data = fir_out;
    end
        
    if(cnt_fir == 599 && cnt_cal == 22 && sm_tvalid)
        SM_last = 1;
end


always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n) begin
        SS_data <= 0;
    end
    else if(cnt_cal == 0 && ss_tready && ss_tvalid) begin
        SS_data <= ss_tdata;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n) begin
        cnt_cal <= 0;
        cnt_fir <= 0;
    end
    else if(state_current == idle) begin
        cnt_cal <= 0;
        cnt_fir <= 0;
    end
    else if(cnt_cal == 0 && cnt_reset != 4'd11) begin
        cnt_cal <= 0;
    end
    else if(cnt_cal == 0 && !ss_tvalid ) begin
        cnt_cal <= 0;
    end
    else if(cnt_cal == 5'd22 && sm_tready) begin
        cnt_cal <= 0;
        cnt_fir = cnt_fir + 1;
    end
    else if(cnt_cal == 5'd22 & !sm_tready) begin
        cnt_cal <= 5'd22;
    end
    else begin
        cnt_cal <= cnt_cal + 1;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin
    if(!axis_rst_n) begin
        cnt_reset <= 0;
    end
    else if(state_current == idle && state_next == operation) begin
        cnt_reset <= 0;
    end
    else if(state_current == idle) begin
        cnt_reset <= 0;
    end
    else if(cnt_reset == 4'd11) begin
        cnt_reset <= cnt_reset;
    end
    else begin
        cnt_reset <= cnt_reset + 1;
    end
end

endmodule