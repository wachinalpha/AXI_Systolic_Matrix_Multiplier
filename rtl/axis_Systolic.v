`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/18/2026 07:19:51 PM
// Design Name: 
// Module Name: axis_multiplier
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module axis_Systolic #( parameter N             = 8,
                        parameter ELEMENT_WIDTH = 8,
                        parameter AXIS_WIDTH = 128)
    (
        //Control signals
        input axis_clk,
        input axis_aresetn,
        
        // Slave signals
        input [AXIS_WIDTH-1:0] S_axis_data,
        input S_axis_valid,
        output S_axis_ready,
        input S_axis_last,
        
        // Master signals
        output [AXIS_WIDTH-1:0] M_axis_data,
        output M_axis_valid,
        input  M_axis_ready, 
        output M_axis_last
    );
    //Axis control signals
    wire input_transfer = S_axis_valid && S_axis_ready;
    wire output_transfer = M_axis_valid && M_axis_ready;
    
    wire finish;
    wire scheduler_busy;
    wire scheduler_start;
    
    //counter parameters
    localparam ACC_WIDTH   = 4 * ELEMENT_WIDTH;
    localparam BUFF_SIZE   = N * N * ELEMENT_WIDTH;
    
    localparam INPUT_BITS  = 2*N*N*ELEMENT_WIDTH;
    localparam INPUT_BEATS = INPUT_BITS / AXIS_WIDTH;  // 1024/128 = 8
    localparam COUNT_WIDTH = $clog2(INPUT_BEATS);      // 3 bits

    localparam RESULT_BITS      = 4 * ELEMENT_WIDTH * N * N;
    localparam OUTPUT_BEATS     = RESULT_BITS / AXIS_WIDTH;  // 16
    localparam OUT_COUNT_WIDTH  = $clog2(OUTPUT_BEATS);      // 4

    //States definitions
    localparam [1:0] STATE_RECEIVE = 2'b00;
    localparam [1:0] STATE_START = 2'b01;
    localparam [1:0] STATE_COMPUTE = 2'b10;
    localparam [1:0] STATE_SEND = 2'b11;

    //reg for the state encoding
    reg [1:0] state_d, state_q;
    
    //the beat t = beat_q
    reg [COUNT_WIDTH-1:0] beat_counter_q;
    
    //send counter
    reg [OUT_COUNT_WIDTH-1:0] send_counter_q;
    
    //out buff
    wire signed [N*N*ACC_WIDTH-1:0] scheduler_result;

    //We need two buffers for the matrix multiplication
    reg signed [2*BUFF_SIZE-1:0] i_Buffer;
    wire signed [BUFF_SIZE-1:0] A_buff, B_buff;
        
    /*
     * Registro de estado.
     */
    always @(posedge axis_clk) begin
        if (~axis_aresetn)
            state_q <= STATE_RECEIVE;
        else
            state_q <= state_d;
    end

    /*
     * Lógica de próximo estado.
     */
    always @(*) begin
        state_d = state_q;

        case (state_q)

            STATE_RECEIVE: begin
                if (input_transfer && (beat_counter_q == INPUT_BEATS-1))
                    state_d = STATE_START;
            end

            STATE_START: begin
                    state_d = STATE_COMPUTE;
            end

            STATE_COMPUTE: begin
                if (finish)
                    state_d = STATE_SEND;
            end

            STATE_SEND: begin
                if(output_transfer && M_axis_last) begin
                    state_d = STATE_RECEIVE;
                end
            end

            default: begin
                state_d = STATE_RECEIVE;
            end

        endcase
    end


    //We add a counter for the inputs
    always @(posedge axis_clk) begin
	    if(~axis_aresetn) begin
		      beat_counter_q <= {COUNT_WIDTH{1'b0}};
	    end
	    else if (state_q != STATE_RECEIVE) begin
		      beat_counter_q <= {COUNT_WIDTH{1'b0}};
	    end
	    else if ((beat_counter_q < INPUT_BEATS -1) && input_transfer ) begin
		    beat_counter_q <= beat_counter_q +1;
	    end
    end
    
    //load the buffer
    always @(posedge axis_clk) begin
            if(~axis_aresetn) begin
                i_Buffer <= {2*BUFF_SIZE{1'b0}};
            end
            else if ((state_q == STATE_RECEIVE) && input_transfer) begin  
                i_Buffer[AXIS_WIDTH*beat_counter_q+:AXIS_WIDTH] <= S_axis_data; 
            end 
        end
     

    always @(posedge axis_clk) begin
        if (~axis_aresetn)
            send_counter_q <= 0;
        else if (state_q != STATE_SEND)
            send_counter_q <= 0;
        else if (output_transfer) begin
            if (send_counter_q < OUTPUT_BEATS - 1)
                send_counter_q <= send_counter_q + 1'b1;
        end
    end
        
         
    assign scheduler_start = (state_q == STATE_START);    
    
    //Assign the right entries A and B
    
    assign A_buff = i_Buffer[BUFF_SIZE-1:0];
    assign B_buff = i_Buffer[2*BUFF_SIZE-1:BUFF_SIZE];      
                
    
    assign M_axis_valid = (state_q == STATE_SEND);

    assign M_axis_data =
    scheduler_result[
        send_counter_q*AXIS_WIDTH +: AXIS_WIDTH
    ];

    assign M_axis_last =
        M_axis_valid && (send_counter_q == OUTPUT_BEATS - 1);
        
    assign S_axis_ready =
        axis_aresetn && (state_q == STATE_RECEIVE);
        
    matrix_scheduler #(
    .N(N),
    .DATA_WIDTH(ELEMENT_WIDTH)
) scheduler(
           .i_clk(axis_clk),
           .i_rst(~axis_aresetn),
           .i_start(scheduler_start),
           .i_matrix_a(A_buff),
           .i_matrix_b(B_buff),
           .o_matrix_c(scheduler_result),
           .o_busy(scheduler_busy),
           .o_valid(finish)
);      
   
endmodule
