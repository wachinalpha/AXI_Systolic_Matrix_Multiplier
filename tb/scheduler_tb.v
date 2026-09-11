`timescale 1ns / 1ps

module matrix_scheduler_tb;

    parameter N          = 8;
    parameter DATA_WIDTH = 8;

    localparam integer ACC_WIDTH     = 4 * DATA_WIDTH;
    localparam integer MATRIX_ELEMS  = N * N;
    localparam integer MATRIX_BITS   = MATRIX_ELEMS * DATA_WIDTH;
    localparam integer RESULT_BITS   = MATRIX_ELEMS * ACC_WIDTH;
    localparam integer TIMEOUT_CYCLES = 100;

    reg i_clk;
    reg i_rst;
    reg i_start;

    reg signed [MATRIX_BITS-1:0] i_matrix_a;
    reg signed [MATRIX_BITS-1:0] i_matrix_b;

    wire signed [RESULT_BITS-1:0] o_matrix_c;
    wire o_busy;
    wire o_valid;

    /* Matrices de referencia, almacenadas en orden row-major. */
    reg signed [DATA_WIDTH-1:0] a_ref [0:MATRIX_ELEMS-1];
    reg signed [DATA_WIDTH-1:0] b_ref [0:MATRIX_ELEMS-1];
    reg signed [ACC_WIDTH-1:0] expected [0:MATRIX_ELEMS-1];

    integer errors;

    matrix_scheduler #(
        .N(N),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .i_clk      (i_clk),
        .i_rst      (i_rst),
        .i_start    (i_start),
        .i_matrix_a (i_matrix_a),
        .i_matrix_b (i_matrix_b),
        .o_matrix_c (o_matrix_c),
        .o_busy     (o_busy),
        .o_valid    (o_valid)
    );

    /* Clock de 100 MHz. */
    initial begin
        i_clk = 1'b0;
        forever #5 i_clk = ~i_clk;
    end

    /*
     * Copia las memorias de referencia a los buses planos del DUT:
     *
     * bits [7:0]   = elemento [0][0]
     * bits [15:8]  = elemento [0][1]
     * ...
     * bits [511:504] = elemento [7][7]
     */
    task pack_input_matrices;
        integer index;
        begin
            i_matrix_a = {MATRIX_BITS{1'b0}};
            i_matrix_b = {MATRIX_BITS{1'b0}};

            for (index = 0; index < MATRIX_ELEMS; index = index + 1) begin
                i_matrix_a[index*DATA_WIDTH +: DATA_WIDTH] = a_ref[index];
                i_matrix_b[index*DATA_WIDTH +: DATA_WIDTH] = b_ref[index];
            end
        end
    endtask

    /* Calcula C = A*B en el testbench. */
    task calculate_expected;
        integer row;
        integer col;
        integer k;
        integer accumulator;
        integer a_value;
        integer b_value;
        begin
            for (row = 0; row < N; row = row + 1) begin
                for (col = 0; col < N; col = col + 1) begin
                    accumulator = 0;

                    for (k = 0; k < N; k = k + 1) begin
                        a_value = $signed(a_ref[row*N+k]);
                        b_value = $signed(b_ref[k*N+col]);
                        accumulator = accumulator + a_value*b_value;
                    end

                    expected[row*N+col] = accumulator;
                end
            end
        end
    endtask

    /* Primer caso: A es identidad, por lo tanto C debe ser igual a B. */
    task prepare_identity_test;
        integer row;
        integer col;
        integer index;
        begin
            for (row = 0; row < N; row = row + 1) begin
                for (col = 0; col < N; col = col + 1) begin
                    index = row*N + col;

                    if (row == col)
                        a_ref[index] = 1;
                    else
                        a_ref[index] = 0;

                    /* Valores diferentes, incluyendo negativos. */
                    b_ref[index] = index - 32;
                end
            end
        end
    endtask

    /* Segundo caso: dos matrices densas con valores signed pequeños. */
    task prepare_dense_test;
        integer row;
        integer col;
        integer index;
        begin
            for (row = 0; row < N; row = row + 1) begin
                for (col = 0; col < N; col = col + 1) begin
                    index = row*N + col;
                    a_ref[index] = row - col;
                    b_ref[index] = ((2*row + col) % 7) - 3;
                end
            end
        end
    endtask

    /* Inicia una operación, espera o_valid y compara los 64 resultados. */
    task run_and_check;
        input integer test_number;
        integer index;
        integer timeout;
        reg signed [ACC_WIDTH-1:0] received;
        begin
            pack_input_matrices;
            calculate_expected;

            /* i_start dura exactamente un ciclo. */
            @(negedge i_clk);
            i_start = 1'b1;

            @(negedge i_clk);
            i_start = 1'b0;

            if (o_busy !== 1'b1) begin
                $display("ERROR test %0d: o_busy no se activo", test_number);
                errors = errors + 1;
            end

            timeout = 0;

            while ((o_valid !== 1'b1) && (timeout < TIMEOUT_CYCLES)) begin
                @(posedge i_clk);
                #1;
                timeout = timeout + 1;
            end

            if (o_valid !== 1'b1) begin
                $display("ERROR test %0d: timeout esperando o_valid",
                         test_number);
                errors = errors + 1;
            end
            else begin
                for (index = 0; index < MATRIX_ELEMS; index = index + 1) begin
                    received = o_matrix_c[
                        index*ACC_WIDTH +: ACC_WIDTH
                    ];

                    if (received !== expected[index]) begin
                        $display(
                            "ERROR test %0d: C[%0d][%0d] esperado=%0d recibido=%0d",
                            test_number,
                            index/N,
                            index%N,
                            $signed(expected[index]),
                            $signed(received)
                        );
                        errors = errors + 1;
                    end
                end

                $display("Test %0d terminado despues de %0d ciclos de espera",
                         test_number, timeout);
            end

            /* DONE debe durar un ciclo y luego regresar a IDLE. */
            @(posedge i_clk);
            #1;

            if (o_valid !== 1'b0) begin
                $display("ERROR test %0d: o_valid duro mas de un ciclo",
                         test_number);
                errors = errors + 1;
            end

            if (o_busy !== 1'b0) begin
                $display("ERROR test %0d: el scheduler no regreso a IDLE",
                         test_number);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        i_rst      = 1'b1;
        i_start    = 1'b0;
        i_matrix_a = {MATRIX_BITS{1'b0}};
        i_matrix_b = {MATRIX_BITS{1'b0}};
        errors     = 0;

        /* Reset sincrónico. */
        repeat (3) @(posedge i_clk);
        @(negedge i_clk);
        i_rst = 1'b0;

        prepare_identity_test;
        run_and_check(1);

        /* Segunda operación sin aplicar nuevamente el reset global. */
        prepare_dense_test;
        run_and_check(2);

        if (errors == 0)
            $display("PASS: todas las multiplicaciones fueron correctas");
        else
            $display("FAIL: se encontraron %0d errores", errors);

        #20;
        $finish;
    end

endmodule