`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/01/2026 06:54:38 PM
// Design Name: 
// Module Name: mac_pe
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


module mac_pe #( parameter datawidth = 8)(
        
        //control signals
        
        input i_clk,
        input i_rst,
        
        input i_step,
        
        //data signals
        
        
        input signed [datawidth-1:0] i_a,
        input  signed [datawidth-1:0] i_b,
        
        output signed [datawidth-1:0] a_o,
        output signed [datawidth-1:0] b_o,
        
        //We hardcode the output accumulator -> in the future we should use
        //something like 2*datawidth+log2(datawidth)
        
        output signed [31:0] y_o    
    );
    
    
    wire signed [datawidth-1:0] operand_a;
    wire signed [datawidth-1:0] operand_b;
    wire signed [2*datawidth-1:0] product;
    wire signed [4*datawidth-1:0] mac_d;
    reg signed [4*datawidth-1:0] mac_q;
   
    //MAC logic
    
    assign operand_a = i_a;
    assign operand_b = i_b;
    
    assign product = operand_a*operand_b;
    
    assign mac_d = (i_step) ? (mac_q + product) : mac_q;
    
    always @(posedge i_clk) begin
        if(i_rst) begin
            mac_q <= {(4*datawidth){1'b0}};
        end
        else begin
            mac_q <= mac_d;
        end
     end
    
    assign y_o = mac_q;

    // we create the output registers for a and b outputs
    //

    reg signed [datawidth-1:0] a_q, b_q;
    wire signed [datawidth-1:0] a_d, b_d;
    
    //mux logic
    //
    assign a_d = i_step ? i_a : a_q;
    assign b_d = i_step ? i_b : b_q;



    always @(posedge i_clk) begin
	    if(i_rst) begin
		    a_q <= {datawidth{1'b0}};
		    b_q <= {datawidth{1'b0}};
	    end
	    else begin
		    a_q <= a_d;
		    b_q <= b_d;
	    end
    end

    assign a_o = a_q;
    assign b_o = b_q;

endmodule
