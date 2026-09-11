`timescale 1ns / 1ps


module matrix_scheduler #(
    parameter N = 8,
    parameter DATA_WIDTH = 8
)(
    input  i_clk,
    input  i_rst,
    input  i_start,

     /* i_matrix_a[(i*N+k)*DATA_WIDTH +: DATA_WIDTH] = A[i][k] */
     /* i_matrix_b[(k*N+j)*DATA_WIDTH +: DATA_WIDTH] = B[k][j] */

    input  [N*N*DATA_WIDTH-1:0] i_matrix_a,
    input  [N*N*DATA_WIDTH-1:0] i_matrix_b,

    output [32*N*N-1:0] o_matrix_c,
    output o_busy,
    output o_valid
); 

    localparam integer ACC_WIDTH = 4*DATA_WIDTH;
    localparam integer MULT_CYCLES = (3 * N)-2;
    
    localparam integer COUNT_WIDTH = $clog2(MULT_CYCLES);
    

    //States definitions
    localparam [1:0] STATE_IDLE = 2'b00;
    localparam [1:0] STATE_CLEAR = 2'b01;
    localparam [1:0] STATE_RUN = 2'b10;
    localparam [1:0] STATE_DONE = 2'b11;

    //reg for the state encoding
    reg [1:0] state_d, state_q;

    //the timer t = cycle
    reg [COUNT_WIDTH-1:0] cycle_q;

    // The matrices N*N
    reg signed [N*N*DATA_WIDTH-1:0] matrix_a_q;
    reg signed [N*N*DATA_WIDTH-1:0] matrix_b_q;
	
    //We are going to use the arrays as inputs of the systolic array
    reg signed [N*DATA_WIDTH-1:0] row_to_array;
    reg signed [N*DATA_WIDTH-1:0] col_to_array;

    // The result
    wire signed [N*N*ACC_WIDTH-1:0] array_result;

	
    wire array_rst;
    wire array_step;

    /*
     * Registro de estado.
     */
    always @(posedge i_clk) begin
        if (i_rst)
            state_q <= STATE_IDLE;
        else
            state_q <= state_d;
    end

    /*
     * Lógica de próximo estado.
     */
    always @(*) begin
        state_d = state_q;

        case (state_q)

            STATE_IDLE: begin
                if (i_start)
                    state_d = STATE_CLEAR;
            end

            STATE_CLEAR: begin
                state_d = STATE_RUN;
            end

            STATE_RUN: begin
                if (cycle_q == MULT_CYCLES - 1)
                    state_d = STATE_DONE;
            end

            STATE_DONE: begin
                state_d = STATE_IDLE;
            end

            default: begin
                state_d = STATE_IDLE;
            end

        endcase
    end

    /*
     * Guardar matrices cuando comienza una operación.
     */
    always @(posedge i_clk) begin
        if (i_rst) begin
            matrix_a_q <= {N*N*DATA_WIDTH{1'b0}};
            matrix_b_q <= {N*N*DATA_WIDTH{1'b0}};
        end
        else if ((state_q == STATE_IDLE) && i_start) begin
            matrix_a_q <= i_matrix_a;
            matrix_b_q <= i_matrix_b;
        end
    end

    //Agregamos un contador
    always @(posedge i_clk) begin
	    if(i_rst) begin
		cycle_q <= {COUNT_WIDTH{1'b0}};
	    end
	    else if (state_q != STATE_RUN) begin
		cycle_q <= {COUNT_WIDTH{1'b0}};
	    end
	    else if (cycle_q < MULT_CYCLES -1) begin
		    cycle_q <= cycle_q +1;
	    end
    end
 
    integer lane;
    integer k;

    always @(*) begin
        row_to_array = {N*DATA_WIDTH{1'b0}};
        col_to_array = {N*DATA_WIDTH{1'b0}};

        if (state_q == STATE_RUN) begin
            for (lane = 0; lane < N; lane = lane + 1) begin
                for (k = 0; k < N; k = k + 1) begin

                    if (cycle_q == (lane + k)) begin

                        row_to_array[
                            lane*DATA_WIDTH +: DATA_WIDTH
                        ] = matrix_a_q[
                            (lane*N + k)*DATA_WIDTH +: DATA_WIDTH
                        ];

                        col_to_array[
                            lane*DATA_WIDTH +: DATA_WIDTH
                        ] = matrix_b_q[
                            (k*N + lane)*DATA_WIDTH +: DATA_WIDTH
                        ];

                    end
                end
            end
        end
    end


    /*
     * Control global del array.
     */
    assign array_rst  = i_rst || (state_q == STATE_CLEAR);
    assign array_step = (state_q == STATE_RUN);

    /*
     * Estado visible externamente.
     */
       assign o_busy  = (state_q != STATE_IDLE);
       assign  o_valid = (state_q == STATE_DONE);


    /*
     * Instancia del array que ya implementamos.
     */
    sistolicArray #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_sistolic_array (
        .i_clk     (i_clk),
        .i_rst     (array_rst),
        .i_step    (array_step),
        .rowInput  (row_to_array),
        .ColInput  (col_to_array),
        .result    (array_result)
    );

    assign o_matrix_c = array_result;


endmodule
