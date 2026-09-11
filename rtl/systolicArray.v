`timescale 1ns / 1ps

// This module interconnects the PEs to form a systolic array. Below, is an
// example of how PEs in a 4x4 systolic array are interconnected. The horizontal
// lines represent row interconnects, and the vertical lines represent column
// interconnects. The arrows indicate the direction of data flow.

// PE[0][0] --> PE[0][1] --> PE[0][2] --> PE[0][3]
//   |            |            |            |
//   v            v            v            v
// PE[1][0] --> PE[1][1] --> PE[1][2] --> PE[1][3]
//   |            |            |            |
//   v            v            v            v
// PE[2][0] --> PE[2][1] --> PE[2][2] --> PE[2][3]
//   |            |            |            |
//   v            v            v            v
// PE[3][0] --> PE[3][1] --> PE[3][2] --> PE[3][3]
//
//
//

module sistolicArray #( parameter N = 8, parameter DATA_WIDTH = 8)(
                    //control signals
                    input i_clk,
                    input i_rst,
                    input i_step,

                    // systolic interfaz, rows and columns that SA eats
                    input signed [(N*DATA_WIDTH-1):0] rowInput,
                    input signed [(N*DATA_WIDTH-1):0] ColInput,
                    
                    // The N*N accumulator
                    output signed [4*DATA_WIDTH*N*N-1:0] result 
                    );
                    
                    
                    // We need interconects for columns and rows
                    // N for rows, N+1 for input+output+N-1 in betwen and the Datawidth
                    
                    wire signed [N*(N+1)*DATA_WIDTH-1:0] rowInterConnect;
                    wire signed [N*(N+1)*DATA_WIDTH-1:0] colInterConnect;
                    
                    
                    genvar k;
                    generate
                     for ( k = 0; k < N; k=k+1) begin: FirstRow
                         // These are dummy interconnects used to pass data from the row matrices to
                         // the i_a ports of PE in the first col.
                            assign rowInterConnect[k*(N+1)*DATA_WIDTH +: DATA_WIDTH] = rowInput[k*DATA_WIDTH +: DATA_WIDTH];
                          // These are dummy interconnects used to pass data  from the col matrices to
                         // the i_b ports of PE in the first row.
                            assign colInterConnect[k*DATA_WIDTH +: DATA_WIDTH] = ColInput[k*DATA_WIDTH +: DATA_WIDTH];        
                    end
                    endgenerate 
		    
		    genvar i,j;

		    generate 
			    for(i = 0; i < N; i=i+1) begin: RowIteration
				    for(j = 0; j < N; j=j+1) begin: ColumnIteration
					    mac_pe #(.datawidth(DATA_WIDTH)) u_pe (.i_clk(i_clk),
						   .i_rst(i_rst),
						   .i_step(i_step),
						   .i_a(rowInterConnect[(i*(N+1)+j)*DATA_WIDTH+:DATA_WIDTH]),
						   .i_b(colInterConnect[(i*N+j)*DATA_WIDTH+:DATA_WIDTH]),
						   .a_o(rowInterConnect[(i*(N+1)+(j+1))*DATA_WIDTH+:DATA_WIDTH]),
						   .b_o(colInterConnect[((i+1)*N+j)*DATA_WIDTH+:DATA_WIDTH]),
						   .y_o(result[(i*N+j)*4*DATA_WIDTH+:4*DATA_WIDTH]));
				   end
			   end
		   endgenerate
endmodule
                    
                    
                    
