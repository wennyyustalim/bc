#include <iostream>
#include <cuda.h>
#include "Graph.h"

#define MAX_THREAD_COUNT 1024
#define CEIL(a, b) ((a - 1) / b + 1)
#define catchCudaError(error) { gpuAssert((error), __FILE__, __LINE__); }

using namespace std;

float device_time_taken;

void printTime(float ms) {
  printf("%d,", (int)ms);
}

inline void gpuAssert(cudaError_t error, const char *file, int line,  bool abort = false) {
  if (error != cudaSuccess) {
    printf("\n====== Cuda Error Code %i ======\n %s in CUDA %s\n", error, cudaGetErrorString(error));
    printf("\nIn file :%s\nOn line: %d", file, line);
    
    if(abort)
      exit(-1);
  }
}

__global__ void betweennessCentralityKernel(
  Graph *graph,
  double *bwCentrality,
  int nodeFrom,
  int nodeTo,
  int nodeCount,
  int *sigma,
  int *distance,
  double *dependency) {
    
  int idx = threadIdx.x;
  if (idx >= nodeCount)
    return;
  
  __shared__ int s;
  __shared__ int current_depth;
  __shared__ bool done;

  if(idx == 0) {
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

    for (int v = idx; v < nodeCount; v += blockDim.x) {
        if (v == s) {
          distance[v] = 0;
          sigma[v] = 1;
        } else {
          distance[v] = INT_MAX;
          sigma[v] = 0;
        }
        dependency[v] = 0.0;
    }
    __syncthreads();

    while (!done) {
      if (idx == 0) {
          current_depth++;
      }
      done = true;
      __syncthreads();

      for (int v = idx; v < nodeCount; v += blockDim.x) {
        if (distance[v] == current_depth) {
          for (int r = graph->adjacencyListPointers[v]; r < graph->adjacencyListPointers[v + 1]; r++) {
            int w = graph->adjacencyList[r];
            if (distance[w] == INT_MAX) {
              distance[w] = distance[v] + 1;
              done = false;
            }
            if (distance[w] == (distance[v] + 1)) {
              atomicAdd(&sigma[w], sigma[v]);
            }
          }
        }
      }
      __syncthreads();
    }

    while(current_depth) {
      if (idx == 0) {
        current_depth--;
      }
      __syncthreads();

      for (int v = idx; v < nodeCount; v += blockDim.x) {
        if (distance[v] == current_depth) {
          for (int r = graph->adjacencyListPointers[v]; r < graph->adjacencyListPointers[v + 1]; r++) {
            int w = graph->adjacencyList[r];
            if (distance[w] == (distance[v] + 1)) {
              if (sigma[w] != 0)
                dependency[v] += (sigma[v] * 1.0 / sigma[w]) * (1 + dependency[w]);
            }
          }

          if (v != s) {
            bwCentrality[v] += dependency[v] / 2;
          }
        }
      }
      __syncthreads();
    }
  }
}

double *betweennessCentrality(Graph *graph, int nodeCount, int nodeFrom, int nodeTo) {
  double *bwCentrality = new double[nodeCount]();
  double *device_bwCentrality, *dependency;
  int *sigma, *distance;

  catchCudaError(cudaMalloc((void **)&device_bwCentrality, sizeof(double) * nodeCount));
  catchCudaError(cudaMalloc((void **)&sigma, sizeof(int) * nodeCount));
  catchCudaError(cudaMalloc((void **)&distance, sizeof(int) * nodeCount));
  catchCudaError(cudaMalloc((void **)&dependency, sizeof(double) * nodeCount));
  catchCudaError(cudaMemcpy(device_bwCentrality, bwCentrality, sizeof(double) * nodeCount, cudaMemcpyHostToDevice));

  // Timer
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
  cout << endl;

  // Timer
  catchCudaError(cudaEventRecord(device_end));
  catchCudaError(cudaEventSynchronize(device_end));
  cudaEventElapsedTime(&device_time_taken, device_start, device_end);

  // Copy back and free memory
  catchCudaError(cudaMemcpy(bwCentrality, device_bwCentrality, sizeof(double) * nodeCount, cudaMemcpyDeviceToHost));
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

  int nodeCount = host_graph->getNodeCount();
  int edgeCount = host_graph->getEdgeCount();
  catchCudaError(cudaMemcpy(device_graph, host_graph, sizeof(Graph), cudaMemcpyHostToDevice));

  // Set threshold
  const long threshold_percent = strtol(argv[3], NULL, 10);
  const int threshold = (int) ((float)nodeCount * (float)threshold_percent / (float) 100);
  const int nodeFrom = threshold;
  const int nodeTo = nodeCount - 1;

  int *adjacencyList;
  catchCudaError(cudaMalloc((void **)&adjacencyList, sizeof(int) * (2 * edgeCount + 1)));
  catchCudaError(cudaMemcpy(adjacencyList, host_graph->adjacencyList, sizeof(int) * (2 * edgeCount + 1), cudaMemcpyHostToDevice));
  catchCudaError(cudaMemcpy(&(device_graph->adjacencyList), &adjacencyList, sizeof(int *), cudaMemcpyHostToDevice));

  int *adjacencyListPointers;
  catchCudaError(cudaMalloc((void **)&adjacencyListPointers, sizeof(int) * (nodeCount + 1)));
  catchCudaError(cudaMemcpy(adjacencyListPointers, host_graph->adjacencyListPointers, sizeof(int) * (nodeCount + 1), cudaMemcpyHostToDevice));
  catchCudaError(cudaMemcpy(&(device_graph->adjacencyListPointers), &adjacencyListPointers, sizeof(int *), cudaMemcpyHostToDevice));

  double *bwCentrality = betweennessCentrality(device_graph, nodeCount, nodeFrom, nodeTo);

  double maxBetweenness = -1;
  for (int i = 0; i < nodeCount; i++) {
    maxBetweenness = max(maxBetweenness, bwCentrality[i]);
  }

  printf("%s, %03d, ", argv[1], atoi(argv[3]));
  // printf("%0.2lf, ", maxBetweenness);
  printf("%0.2lf\n", device_time_taken);

  if (argc == 3) {
    freopen(argv[2], "w", stdout);
    for (int i = 0; i < nodeCount; i++)
      cout << bwCentrality[i] << " ";
    cout << endl;
  }

  // Free all memory
  delete[] bwCentrality;
  catchCudaError(cudaFree(adjacencyList));
  catchCudaError(cudaFree(adjacencyListPointers));
  catchCudaError(cudaFree(device_graph));
}
