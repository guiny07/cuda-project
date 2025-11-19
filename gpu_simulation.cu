
// gpu_simulation_opt.cu
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <cuda_runtime.h> // Biblioteca para codificar em CUDA, necessita placa gráfica NVIDIA. 

#define HEALTH 1
#define INFECTED -1
#define DEAD -2
#define EMPTY 0

// Simple CUDA error checker
void checkCuda(cudaError_t err, const char *msg) {
    if (err != cudaSuccess) {
        fprintf(stderr, "CUDA error (%s): %s\n", msg, cudaGetErrorString(err));
        exit(1);
    }
}

__global__ void step_kernel_optimized(
    int *d_current, int *d_next,
    int *d_dead_age, int *d_next_dead_age,
    int N, int M, int iter,
    int *d_changed, int *d_living
) {
    extern __shared__ int sdata[];
    int *s_living = sdata;                
    int *s_changed = sdata + blockDim.x;   

    int tid = threadIdx.x;
    int threads_in_grid = blockDim.x * gridDim.x;
    int idx0 = blockIdx.x * blockDim.x + threadIdx.x;
    int total = N * M;

    int local_living = 0;
    int local_changed = 0;

    // Strided loop para cobrir todo o array
    for (int pos = idx0; pos < total; pos += threads_in_grid) {
        int i = pos / M;
        int j = pos % M;
        int cur = d_current[pos];
        int nex = EMPTY;
        int ndage = 0;

        // verifica vizinhos (horizontal/vertical)
        int hasNeighbor = 0;

        // cima
        if (i > 0) {
            int v = d_current[(i-1) * M + j];
            if (v == INFECTED || v == DEAD) hasNeighbor = 1;
        }

        // baixo
        if (!hasNeighbor && i + 1 < N) {
            int v = d_current[(i+1) * M + j];
            if (v == INFECTED || v == DEAD) hasNeighbor = 1;
        }

        // esquerda
        if (!hasNeighbor && j > 0) {
            int v = d_current[i * M + (j-1)];
            if (v == INFECTED || v == DEAD) hasNeighbor = 1;
        }

        // direita
        if (!hasNeighbor && j + 1 < M) {
            int v = d_current[i * M + (j+1)];
            if (v == INFECTED || v == DEAD) hasNeighbor = 1;
        }


        if (cur == HEALTH) {
            if (hasNeighbor()) nex = INFECTED;
            else nex = HEALTH;
        }
        else if (cur == INFECTED) {

            unsigned int seed = (unsigned int)(pos * 1664525u + (unsigned int)iter * 1013904223u);
            seed = seed * 1103515245u + 12345u;
            int rv = (int)(seed % 10000u);

            if (rv <= 999) nex = HEALTH;
            else if (rv <= 3999) nex = INFECTED;
            else { nex = DEAD; ndage = 1; }
        }
        else if (cur == DEAD) {
            int dage = d_dead_age[pos];
            if (dage == 1) { nex = DEAD; ndage = 2; }
            else if (dage == 2) { nex = EMPTY; ndage = 0; }
            else { nex = EMPTY; ndage = 0; }
        }
        else {
            nex = EMPTY;
            ndage = 0;
        }

        d_next[pos] = nex;
        d_next_dead_age[pos] = ndage;

        if (nex == HEALTH || nex == INFECTED) local_living++;
        if (nex != cur) local_changed = 1;
    }

    s_living[tid] = local_living;
    s_changed[tid] = local_changed;
    __syncthreads();

    if (tid == 0) {
        int block_sum_living = 0;
        int block_any_changed = 0;
        for (int k = 0; k < blockDim.x; ++k) {
            block_sum_living += s_living[k];
            block_any_changed |= s_changed[k];
        }
        if (block_sum_living > 0) atomicAdd(d_living, block_sum_living);
        if (block_any_changed) atomicExch(d_changed, 1);
    }
}

int *read_input(const char *filename, int *outN, int *outM) {
    FILE *f = fopen(filename, "r");
    if (!f) { perror("fopen"); return NULL; }
    int N, M;
    if (fscanf(f, "%d %d", &N, &M) != 2) { fclose(f); return NULL; }
    int total = N * M;
    int *arr = (int *)malloc(total * sizeof(int));
    for (int i = 0; i < total; ++i) {
        if (fscanf(f, "%d", &arr[i]) != 1) {
            fprintf(stderr, "Erro lendo input na posição %d\n", i);
            free(arr); fclose(f); return NULL;
        }
    }
    fclose(f);
    *outN = N; *outM = M;
    return arr;
}

int main(int argc, char **argv) {
    if (argc < 4) {
        printf("Uso: %s input.txt threadsPerBlock numBlocks\n", argv[0]);
        printf("Ex: %s input_2000.txt 256 128\n", argv[0]);
        return 1;
    }

    const char *inputfile = argv[1];
    int tpblock = atoi(argv[2]);
    int nblocks = atoi(argv[3]);

    int N, M;
    int *h_current = read_input(inputfile, &N, &M);
    if (!h_current) return 1;
    int total = N * M;
    int max_iter = N * M;

    // host dead_age init
    int *h_dead_age = (int *)calloc(total, sizeof(int));
    for (int idx = 0; idx < total; ++idx) if (h_current[idx] == DEAD) h_dead_age[idx] = 1;

    // device buffers
    int *d_current = NULL, *d_next = NULL;
    int *d_dead_age = NULL, *d_next_dead_age = NULL;
    int *d_changed = NULL, *d_living = NULL;

    checkCuda(cudaMalloc(&d_current, total * sizeof(int)), "cudaMalloc d_current");
    checkCuda(cudaMalloc(&d_next, total * sizeof(int)), "cudaMalloc d_next");
    checkCuda(cudaMalloc(&d_dead_age, total * sizeof(int)), "cudaMalloc d_dead_age");
    checkCuda(cudaMalloc(&d_next_dead_age, total * sizeof(int)), "cudaMalloc d_next_dead_age");
    checkCuda(cudaMalloc(&d_changed, sizeof(int)), "cudaMalloc d_changed");
    checkCuda(cudaMalloc(&d_living, sizeof(int)), "cudaMalloc d_living");

    // copia input para device
    checkCuda(cudaMemcpy(d_current, h_current, total * sizeof(int), cudaMemcpyHostToDevice), "memcpy cur");
    checkCuda(cudaMemcpy(d_dead_age, h_dead_age, total * sizeof(int), cudaMemcpyHostToDevice), "memcpy dead_age");

    // eventos para timing
    cudaEvent_t start, stop;
    checkCuda(cudaEventCreate(&start), "create start");
    checkCuda(cudaEventCreate(&stop), "create stop");

    dim3 block(tpblock);
    dim3 grid(nblocks);

    size_t shared_bytes = 2 * tpblock * sizeof(int);

    float elapsed_ms = 0.0f;
    checkCuda(cudaEventRecord(start), "eventRecord start");

    int iter = 0;
    int h_changed = 0, h_living = 0;

    while (iter < max_iter) {

        checkCuda(cudaMemset(d_changed, 0, sizeof(int)), "memset changed");
        checkCuda(cudaMemset(d_living, 0, sizeof(int)), "memset living");

        step_kernel_optimized<<<grid, block, shared_bytes>>>(
            d_current, d_next,
            d_dead_age, d_next_dead_age,
            N, M, iter,
            d_changed, d_living
        );
        checkCuda(cudaGetLastError(), "kernel launch");
        checkCuda(cudaDeviceSynchronize(), "sync after kernel");

        checkCuda(cudaMemcpy(&h_changed, d_changed, sizeof(int), cudaMemcpyDeviceToHost), "copy changed");
        checkCuda(cudaMemcpy(&h_living, d_living, sizeof(int), cudaMemcpyDeviceToHost), "copy living");

        int *tmpi = d_current; d_current = d_next; d_next = tmpi;
        int *tmpt = d_dead_age; d_dead_age = d_next_dead_age; d_next_dead_age = tmpt;

        iter++;
        if (h_changed == 0) break;
        if (h_living == 0) break;
    }

    checkCuda(cudaEventRecord(stop), "eventRecord stop");
    checkCuda(cudaEventSynchronize(stop), "event sync stop");
    checkCuda(cudaEventElapsedTime(&elapsed_ms, start, stop), "event elapsed");

    int *h_final = (int *)malloc(total * sizeof(int));
    checkCuda(cudaMemcpy(h_final, d_current, total * sizeof(int), cudaMemcpyDeviceToHost), "copy final");

    // contar mortos e sobreviventes
    int totalDeaths = 0, totalAlive = 0;
    for (int k = 0; k < total; ++k) {
        if (h_final[k] == DEAD) totalDeaths++;
        else if (h_final[k] == HEALTH || h_final[k] == INFECTED) totalAlive++;
    }

    printf("Iterações feitas: %d\n", iter);
    printf("Tempo GPU (ms): %.3f\n", elapsed_ms);
    printf("Mortos: %d  Sobreviventes: %d\n", totalDeaths, totalAlive);

    FILE *out = fopen("gpu_output_opt.txt", "w");
    fprintf(out, "Mortos: %d\nSobreviventes: %d\nIteracoes: %d\nTempo_ms: %.3f\n", totalDeaths, totalAlive, iter, elapsed_ms);
    fclose(out);

    free(h_current); free(h_dead_age); free(h_final);
    cudaFree(d_current); cudaFree(d_next); cudaFree(d_dead_age); cudaFree(d_next_dead_age);
    cudaFree(d_changed); cudaFree(d_living);
    cudaEventDestroy(start); cudaEventDestroy(stop);
    return 0;
}