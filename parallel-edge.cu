#include <iostream>
#include <cuda.h>
#include "Graph.h"

#define MAX_THREAD_COUNT 1024
#define CEIL(a, b) ((a - 1) / b + 1)

using namespace std;

#define catchCudaError(error) { gpuAssert((error), __FILE__, __LINE__); }

float device_time_taken;

void printTime(float ms) {
  // int h = ms / (1000 * 3600);
  // int m = (((int)ms) / (1000 * 60)) % 60;
  // int s = (((int)ms) / 1000) % 60;
  // int intMS = ms;
  // intMS %= 1000;
  // printf("Time Taken (Parallel) = %dh %dm %ds %dms\n", h, m, s, intMS);
  printf("%d,", (int)ms);
}

inline void gpuAssert(cudaError_t error, const char *file, int line, bool abort = false) {
  if (error != cudaSuccess) {
    printf("\n====== Cuda Error Code %i ======\n %s", error, cudaGetErrorString(error));
    printf("\nIn file :%s\nOn line: %d", file, line);

    if (abort)
      exit(-1);
  }
}

__global__ void betweennessCentralityKernel(Graph *graph, float *bwCentrality, 
                                            int nodeFrom, int nodeTo, int nodeCount,
                                            int *sigma, int *distance, float *dependency) {
  int idx = threadIdx.x;
  if (idx >= max((2*(graph->edgeCount)), nodeCount))
    return;

  __shared__ int s;
  __shared__ int current_depth;
  __shared__ bool done;

  if (idx == 0) {
    s = nodeFrom - 1;
  }
  __syncthreads();

  while (s <= nodeTo) {
    if (idx == 0) {
        ++s;
        done = false;
        current_depth = -1;
    }
    __syncthreads();

    for (int i = idx; i < nodeCount; i += blockDim.x) {
      if (i == s) {
        distance[i] = 0;
        sigma[i] = 1;
      } else {
        distance[i] = INT_MAX;
        sigma[i] = 0;
      }
      dependency[i]= 0.0;
    }
    __syncthreads();

    while (!done) {
      __syncthreads();

      if (threadIdx.x == 0){
        current_depth++;
      }
      done = true;
      __syncthreads();

      for (int i = idx; i < (2*(graph->edgeCount)); i += blockDim.x)  {
        int v = graph->edgeList1[i];
        if (distance[v] == current_depth) {    
          int w = graph->edgeList2[i];
          if (distance[w] == INT_MAX) {
            distance[w] = distance[v] + 1;
            done = false;
          }
          if (distance[w] == (distance[v] + 1)) {
            atomicAdd(&sigma[w], sigma[v]);
          }
        }
      }
      __syncthreads();
    }
    __syncthreads();

    // Reverse BFS
    while (current_depth) {
      if (idx == 0) {
        current_depth--;
      }
      __syncthreads();

      for (int i = idx; i < (2*(graph->edgeCount)); i += blockDim.x) {
        int v = graph->edgeList1[i];
        if (distance[v] == current_depth) {
          int w = graph->edgeList2[i];
          if(distance[w] == (distance[v] + 1)) {
            if (sigma[w] != 0) {
              atomicAdd(dependency + v, (sigma[v] * 1.0 / sigma[w]) * (1 + dependency[w]));
            }
          }
        }
      }
      __syncthreads();
    }

    for (int v = idx; v < nodeCount; v += blockDim.x) {
      if (v != s) {
        bwCentrality[v] += dependency[v] / 2;
      }
    }
    __syncthreads();
  }
}

float *betweennessCentrality(Graph *graph, int nodeCount, int nodeFrom, int nodeTo) {
  float *bwCentrality = new float[nodeCount]();
  float *device_bwCentrality, *dependency;
  int *sigma, *distance;

  catchCudaError(cudaMalloc((void **)&device_bwCentrality, sizeof(float) * nodeCount));
  catchCudaError(cudaMalloc((void **)&sigma, sizeof(int) * nodeCount));
  catchCudaError(cudaMalloc((void **)&distance, sizeof(int) * nodeCount));
  catchCudaError(cudaMalloc((void **)&dependency, sizeof(float) * nodeCount));
  catchCudaError(cudaMemcpy(device_bwCentrality, bwCentrality, sizeof(float) * nodeCount, cudaMemcpyHostToDevice));

  cudaEvent_t device_start, device_end;
  catchCudaError(cudaEventCreate(&device_start));
  catchCudaError(cudaEventCreate(&device_end));
  catchCudaError(cudaEventRecord(device_start));

  betweennessCentralityKernel<<<1, MAX_THREAD_COUNT>>>(
    graph,
    device_bwCentrality,
    nodeFrom,
    nodeTo,
    nodeCount,
    sigma,
    distance,
    dependency
  );
  cudaDeviceSynchronize();
  
  // Timer
  catchCudaError(cudaEventRecord(device_end));
  catchCudaError(cudaEventSynchronize(device_end));
  cudaEventElapsedTime(&device_time_taken, device_start, device_end);

  // Copy back and free memory
  catchCudaError(cudaMemcpy(bwCentrality, device_bwCentrality, sizeof(float) * nodeCount, cudaMemcpyDeviceToHost));
  catchCudaError(cudaFree(device_bwCentrality));
  catchCudaError(cudaFree(sigma));
  catchCudaError(cudaFree(dependency));
  catchCudaError(cudaFree(distance));

  return bwCentrality;
}

int main(int argc, char *argv[]) {
  if (argc < 2) {
    cout << "Usage: " << argv[0] << " <input_file> <output_file>\n";
    return 0;
  }

  freopen(argv[1], "r", stdin);

  Graph *host_graph = new Graph();
  Graph *device_graph;

  catchCudaError(cudaMalloc((void **)&device_graph, sizeof(Graph)));
  host_graph->readGraph();
  host_graph->convertToCOO();

  int nodeCount = host_graph->getNodeCount();
  int edgeCount = host_graph->getEdgeCount();
  catchCudaError(cudaMemcpy(device_graph, host_graph, sizeof(Graph), cudaMemcpyHostToDevice));

  // Set threshold
  const long threshold_percent = strtol(argv[3], NULL, 10);
  const int threshold = (int) ((float)nodeCount * (float)threshold_percent / (float) 100);
  const int nodeFrom = threshold;
  const int nodeTo = nodeCount - 1;

  // Copy edge List to device
  int *edgeList1;
  int *edgeList2;

  // Alocate device memory and copy
  catchCudaError(cudaMalloc((void **)&edgeList1, sizeof(int) * (2 * edgeCount + 1)));
  catchCudaError(cudaMemcpy(edgeList1, host_graph->edgeList1, sizeof(int) * (2 * edgeCount + 1), cudaMemcpyHostToDevice));

  catchCudaError(cudaMalloc((void **)&edgeList2, sizeof(int) * (2 * edgeCount + 1)));
  catchCudaError(cudaMemcpy(edgeList2, host_graph->edgeList2, sizeof(int) * (2 * edgeCount + 1), cudaMemcpyHostToDevice));

  // Update the pointer to this, in device_graph
  catchCudaError(cudaMemcpy(&(device_graph->edgeList1), &edgeList1, sizeof(int *), cudaMemcpyHostToDevice));
  catchCudaError(cudaMemcpy(&(device_graph->edgeList2), &edgeList2, sizeof(int *), cudaMemcpyHostToDevice));

  float *bwCentrality = betweennessCentrality(device_graph, nodeCount, nodeFrom, nodeTo);

  float maxBetweenness = -1;
  for (int i = 0; i < nodeCount; i++) {
    maxBetweenness = max(maxBetweenness, bwCentrality[i]);
  }

  cout << endl;

  printf("%s, %s,", argv[1], argv[3]);
  printf("%0.2lf, %0.2lf\n", maxBetweenness, device_time_taken);

  if (argc == 3) {
    freopen(argv[2], "w", stdout);
    for (int i = 0; i < nodeCount; i++)
      cout << bwCentrality[i] << " ";
    cout << endl;
  }

  delete[] bwCentrality;
  catchCudaError(cudaFree(edgeList1));
  catchCudaError(cudaFree(edgeList2));
  catchCudaError(cudaFree(device_graph));
}
