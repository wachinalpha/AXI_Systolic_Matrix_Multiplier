#include "xaxidma.h"
#include "xparameters.h"
#include <stdlib.h>
#include <xil_cache.h>
#include <xil_printf.h>
#include <xil_types.h>
#include <xstatus.h>


#define POLL_TIMEOUT_COUNTER    1000000U 
#define NUMBER_OF_TRANSFERS	10
#define N 8

#define TX_BYTES (2U*N*N*sizeof(s8)) // 128 bytes
#define RX_BYTES (N*N*sizeof(s32))  // 256 bytes

typedef void  (*matrix_generator_t) (s8* a, s8* b); 

XAxiDma AxiDma;

static u32 random_state = 0x12345678U;


//Xilink uses 2 structs, usally one for represent the HW and another for configuration

//Suite of auxiliary functions

static int config_and_initialize_dma(UINTPTR BaseAddress);

static int run_systolic(s8* tx_buffer, s32* rx_buffer );

static int test(s8* tx_buffer, s32* rx_buffer, matrix_generator_t gen_mat);

static void matmul_reference(s8* a, s8*b, s32* c_ref); 

static int compare_results(const s32 *received, const s32 *reference);

static void gen_identity(s8 *a, s8 *b);

static void gen_zeros(s8 *a, s8 *b);

static void seed_random_matrices(u32 seed);

static u32 next_random_u32(void);

static void gen_random(s8 *a, s8 *b);

static void gen_extreme_values(s8 *a, s8 *b);

static void gen_signed_values(s8 *a, s8 *b);




    
int main(){
    
    xil_printf("Configuration and initialization of DMA\r\n");
    
    int status;
    
    status = config_and_initialize_dma(XPAR_AXI_DMA_0_BASEADDR);

    if (status!=XST_SUCCESS) {
        xil_printf("Fail configuration\r\n");
        return XST_FAILURE;
    }
    
    xil_printf("Initialazing test configuration:\r\n");
    
    xil_printf("Setting buffers in memory\r\n");

    static s8  tx_buffer[2 * N * N] __attribute__((aligned(64)));
    static s32 rx_buffer[N * N]     __attribute__((aligned(64)));
    
    /* Test random matrices values  */

    xil_printf("Running Identity test\r\n");
    
    status = test(tx_buffer, rx_buffer, gen_identity);

    if (status!=XST_SUCCESS) {
        xil_printf("Fail TEST\r\n");
        return XST_FAILURE;
    }
    
    xil_printf("%d\r\n",status);

    xil_printf("Elementos de la matriz\r\n");
    
    for (int i =0; i< N*N; i++){
        xil_printf("%d\r\n", rx_buffer[i]);
    }

    
    /* Test random matrices values  */

    xil_printf("Running Zeros test\r\n");
    
    status = test(tx_buffer, rx_buffer, gen_zeros);

    if (status!=XST_SUCCESS) {
        xil_printf("Fail TEST\r\n");
        return XST_FAILURE;
    }
 
    xil_printf("status: %d\r\n",status);

    xil_printf("Elementos de la matriz\r\n");
    
    for (int i =0; i< N*N; i++){
        xil_printf("%d\r\n", rx_buffer[i]);
    }

    /* Test signed  */
    xil_printf("Running Signed test\r\n");
    
    status = test(tx_buffer, rx_buffer, gen_signed_values);

    if (status!=XST_SUCCESS) {
        xil_printf("Fail TEST\r\n");
        return XST_FAILURE;
    }
    
    xil_printf("%d\r\n",status);

    xil_printf("Elementos de la matriz\r\n");
    
    for (int i =0; i< N*N; i++){
        xil_printf("%d\r\n", rx_buffer[i]);
    }
    
    /* Test Extreme values  */
    xil_printf("Running Signed test\r\n");
    
    status = test(tx_buffer, rx_buffer, gen_extreme_values);

    if (status!=XST_SUCCESS) {
        xil_printf("Fail TEST\r\n");
        return XST_FAILURE;
    }
    
    xil_printf("%d\r\n",status);

    xil_printf("Elementos de la matriz\r\n");
    
    for (int i =0; i< N*N; i++){
        xil_printf("%d\r\n", rx_buffer[i]);
    }
    
    /* Test random matrices values  */

    seed_random_matrices(0x12345678U);

    for (int test_number = 0; test_number < 1000; test_number++) {
        status = test(tx_buffer, rx_buffer, gen_random);
        xil_printf("status: %d\r\n" , status);

    if (status != XST_SUCCESS) {
        xil_printf("Random test %d failed\r\n", test_number);
        break;
        }
    }
    
    return 0;
}



static int config_and_initialize_dma(UINTPTR BaseAddress){
    
    XAxiDma_Config *CfgPtr;
	int Status;
    
    // Begginging of the DMA configuration
    CfgPtr = XAxiDma_LookupConfig(BaseAddress);
	if (!CfgPtr) {
		xil_printf("No config found for %d\r\n", BaseAddress);
		return XST_FAILURE;
	}
    //Initialization
    Status = XAxiDma_CfgInitialize(&AxiDma, CfgPtr);
    
    if (Status != XST_SUCCESS) {
		xil_printf("Initialization failed %d\r\n", Status);
		return XST_FAILURE;
	}
    return Status;
};

static int run_systolic(s8* tx_buffer, s32* rx_buffer ){
     
    int status;

    Xil_DCacheFlushRange((UINTPTR)tx_buffer,TX_BYTES);
    Xil_DCacheFlushRange((UINTPTR)rx_buffer,RX_BYTES);

    // Set the device
    status = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR) rx_buffer,
						RX_BYTES, XAXIDMA_DEVICE_TO_DMA); 
    
	if (status != XST_SUCCESS) {
			return XST_FAILURE;
		}
        
    xil_printf("Device set \r\n");

    //Set the transfer
    status = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR) tx_buffer,
						TX_BYTES, XAXIDMA_DMA_TO_DEVICE);
    
    if (status != XST_SUCCESS){return XST_FAILURE;}
    
    xil_printf("Transfer ready\r\n");
    
    /*Wait till transfer is done or 1usec * 10^6 iterations of timeout occurs*/
    xil_printf("Waiting for finish...\r\n");
    
    int busy = 1;
	while (busy) {
        u32 busy_rx = XAxiDma_Busy(&AxiDma, XAXIDMA_DEVICE_TO_DMA);
        u32 busy_tx = XAxiDma_Busy(&AxiDma, XAXIDMA_DMA_TO_DEVICE);
        
        busy = busy_rx || busy_tx;
	}

    xil_printf("SGEMM complete\r\n");
    
    Xil_DCacheInvalidateRange((UINTPTR)rx_buffer, RX_BYTES);
    
    return status;
}

static int test(s8* tx_buffer, s32* rx_buffer, matrix_generator_t gen_mat){
    int status;
    
    gen_mat(&tx_buffer[0], &tx_buffer[N*N]);
    
    /* Limpiar salida */
    for(int i=0; i< N*N; i++){
        rx_buffer[i] = 0;
    }

    status = run_systolic(tx_buffer,rx_buffer);
    
    if(status!= XST_SUCCESS) return XST_FAILURE;

    s32* c_ref = malloc(RX_BYTES);

    matmul_reference(&tx_buffer[0], &tx_buffer[N*N], c_ref);
    
    status = compare_results(rx_buffer, c_ref);
    
    free(c_ref);
    
    return status;
}

static void matmul_reference(s8* a, s8*b, s32* c_ref){
    for (int i = 0; i < N; i++){
        for(int j=0; j< N; j++){
            c_ref[i*N + j] = 0;

            for (int k = 0; k < N; k++){
                c_ref[i*N + j] +=
                (s32)a[i*N + k] *
                (s32)b[k*N + j]; 
            }       
        }
    }
}; 

static int compare_results(const s32 *received, const s32 *reference){
    int i;
    int errors = 0;

    for (i = 0; i < N*N; i++) {
        if (received[i] != reference[i]) {
            xil_printf(
                "Mismatch [%d][%d]: FPGA=%d CPU=%d\r\n",
                i / N,
                i % N,
                (int)received[i],
                (int)reference[i]
            );
            errors++;
        }
    }
    if (errors != 0) {
        xil_printf("Total mismatches: %d\r\n", errors);
        return XST_FAILURE;
    }
    
    return XST_SUCCESS;
}

static void gen_identity(s8 *a, s8 *b){
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            /* Primera mitad: matriz A identidad */
            a[i*N + j] = (i == j) ? 1 : 0;

            /* Segunda mitad: matriz B */
            b[i*N + j] = (s8) (i*N + j + 1);

        }
    }
}

static void gen_zeros(s8 *a, s8*b){
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            /* Primera mitad: matriz A identidad */
            a[i*N + j] = 0;

            /* Segunda mitad: matriz B */
            b[i*N + j] = (s8)(i*N + j + 1);
        }
    }
}

static void gen_signed_values(s8 *a, s8 *b)
{
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            a[i*N + j] = (s8)(((3*i + j) % 15) - 7);
            b[i*N + j] = (s8)(((i + 2*j) % 13) - 6);
        }
    }
}

static void gen_extreme_values(s8 *a, s8 *b)
{
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            a[i*N + j] = (i % 2 == 0) ? (s8)127 : (s8)-128;
            b[i*N + j] = (j % 2 == 0) ? (s8)127 : (s8)-128;
        }
    }
}


static void seed_random_matrices(u32 seed)
{
    random_state = (seed != 0U) ? seed : 1U;
}

static u32 next_random_u32(void)
{
    u32 value = random_state;

    value ^= value << 13;
    value ^= value >> 17;
    value ^= value << 5;

    random_state = value;
    return value;
}

static void gen_random(s8 *a, s8 *b)
{
    for (int i = 0; i < N*N; i++) {
        a[i] = (s8)((int)(next_random_u32() & 0xFFU) - 128);
        b[i] = (s8)((int)(next_random_u32() & 0xFFU) - 128);
    }
}
