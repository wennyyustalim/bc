#include <iostream>
#include <cuda.h>
#include <stdlib.h> // for strtol
#include "Graph.h"
#include <omp.h>

#define MAX_THREAD_COUNT 1024
#define CEIL(a, b) ((a - 1) / b + 1)

#define catchCudaError(error) { gpuAssert((error), __FILE__, __LINE__); }

using namespace std;

float device_time_taken;

void printTime(float ms) {
  printf("%d,", (int)ms);
}

// Catch Cuda errors
inline void gpuAssert(cudaError_t error, const char *file, int line, bool abort = false) {
    if (error != cudaSuccess) {
        printf("\nCUDA error code %i: %s\n", error, cudaGetErrorString(error));
        printf("\nIn file: %s on line: %d\n", file, line);

        if (abort)
            exit(-1);
    }
}

__global__ void betweennessCentralityKernel(Graph *graph, float *bwCentrality, 
                                            int nodeFrom, int nodeTo, int nodeCount,
                                            int *sigma, int *distance, float *dependency)
{
    int idx = threadIdx.x;
    if(idx >= max((2*(graph->edgeCount)), nodeCount))
        return;

    __shared__ int s;
    __shared__ int current_depth;
    __shared__ bool done;

    if(idx == 0) {
        s = nodeFrom - 1;
    }
    __syncthreads();

    while(s <= nodeTo) {
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

            if (threadIdx.x == 0) {
                current_depth++;
            }
            done = true;
            __syncthreads();

            for (int i = idx; i < (2*(graph->edgeCount)); i += blockDim.x) {
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
            if (idx == 0){
                current_depth--;
            }
            __syncthreads();

            for (int i = idx; i < (2*(graph->edgeCount)); i += blockDim.x)  {
                int v = graph->edgeList1[i];
                if(distance[v] == current_depth) {
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

float *betweennessCentralityCPU(Graph *graph, int nodeFrom, int nodeTo) {
    const int nodeCount = graph->getNodeCount();
    const int edgeCount = graph->getEdgeCount();

    float *bcs = new float[nodeCount]();

    for (int i = nodeFrom; i < nodeTo; ++i) {
      bcs[i] = 0.0;
    }

    #pragma omp parallel
    {
      vector<int> adjacencyListPointers(
        graph->adjacencyListPointers,
        graph->adjacencyListPointers + nodeCount + 1);
      vector<int> adjacencyList(graph->adjacencyList,
                                graph->adjacencyList + 2 * edgeCount + 1);
      vector<double> dependency(nodeCount, 0);
      vector<int> sigma(nodeCount, 0);
      vector<int> distance(nodeCount, -1);
      vector<vector<int> > predecessor(nodeCount);
      vector<double> localBcs(nodeCount, 0.0);
      stack<int> st;
      queue<int> q;

      for (int i = nodeFrom; i < nodeTo; ++i) {
        predecessor[i].reserve(20);
      }

      #pragma omp for schedule(dynamic, 4)
      for (int s = nodeFrom; s <= nodeTo; s++) {
        printf( "Thread %d works with s_node %d\n", omp_get_thread_num(), s);
        for (int i = nodeFrom; i < nodeTo; ++i) {
            predecessor[i].clear();
        }

        fill(dependency.begin(), dependency.end(), 0);
        fill(sigma.begin(), sigma.end(), 0);
        fill(distance.begin(), distance.end(), -1);

        distance[s] = 0;
        sigma[s] = 1;
        q.push(s);
        while (!q.empty()) {
          int v = q.front();
          q.pop();
          st.push(v);

          for (int i = graph->adjacencyListPointers[v]; i < graph->adjacencyListPointers[v + 1]; i++) {
            int w = graph->adjacencyList[i];
            if (distance[w] < 0) {
              q.push(w);
              distance[w] = distance[v] + 1;
            }
            if (distance[w] == distance[v] + 1) {
              sigma[w] += sigma[v];
              predecessor[w].push_back(v);
            }
          }
        }

        while (!st.empty()) {
          int w = st.top();
          st.pop();

          for (const int &v : predecessor[w]) {
            if (sigma[w] != 0)
              dependency[v] += (sigma[v] * 1.0 / sigma[w]) * (1 + dependency[w]);
          }
          if (w != s) {
            localBcs[w] += dependency[w] / 2;
          }
        }

        #pragma omp critical
        {
          for (int i = 0; i < nodeCount; ++i) {
            bcs[i] += localBcs[i];
          }
        }
      }
    }
    cout << endl;
    return bcs;
}

float *betweennessCentrality(Graph *graph, int nodeCount, int nodeFrom, int nodeTo)
{
    float *bwCentrality = new float[nodeCount]();
    float *device_bwCentrality, *dependency;
    int *sigma, *distance;

    //TODO: Allocate device memory for bwCentrality
    catchCudaError(cudaMalloc((void **)&device_bwCentrality, sizeof(float) * nodeCount));
    catchCudaError(cudaMalloc((void **)&sigma, sizeof(int) * nodeCount));
    catchCudaError(cudaMalloc((void **)&distance, sizeof(int) * nodeCount));
    catchCudaError(cudaMalloc((void **)&dependency, sizeof(float) * nodeCount));
    catchCudaError(cudaMemcpy(device_bwCentrality, bwCentrality, sizeof(float) * nodeCount, cudaMemcpyHostToDevice));

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
    
    //End of progress bar
    // cout << endl;

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

    const long threshold_percent = strtol(argv[3], NULL, 10);

    Graph *host_graph = new Graph();
    Graph *device_graph;

    catchCudaError(cudaMalloc((void **)&device_graph, sizeof(Graph)));
    host_graph->readGraph();
    host_graph->convertToCOO();

    int nodeCount = host_graph->getNodeCount();
    int edgeCount = host_graph->getEdgeCount();
    catchCudaError(cudaMemcpy(device_graph, host_graph, sizeof(Graph), cudaMemcpyHostToDevice));

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

    const int threshold = (int) ((float)nodeCount * (float)threshold_percent / (float) 100);
    float *bwCentralityGPU;
    float *bwCentralityCPU;

    clock_t start, end;

    #pragma omp parallel sections
    {
      #pragma omp section
      {
        const int nodeFrom = threshold;
        const int nodeTo = nodeCount - 1;
        bwCentralityGPU = betweennessCentrality(device_graph, nodeCount, nodeFrom, nodeTo);
      }

      #pragma omp section
      {
        const int nodeFrom = 0;
        const int nodeTo = threshold - 1;
        
        start = clock();
        bwCentralityCPU = betweennessCentralityCPU(host_graph, nodeFrom, nodeTo);
      }
    }

    float *bwCentrality = new float[nodeCount];
    float maxBetweenness = -1;
    for (int i = 0; i < nodeCount; i++) {
      bwCentrality[i] = bwCentralityCPU[i] + bwCentralityGPU[i];
      maxBetweenness = max(maxBetweenness, bwCentrality[i]);
    }
    end = clock();

    float host_time_taken = 1000.0 * (end - start) / (float)CLOCKS_PER_SEC;

    printf("%s, %s, ", argv[1], argv[3]);
    printf("%0.2lf, ", maxBetweenness);
    printTime(device_time_taken);
    printTime(host_time_taken);
    printTime(max(device_time_taken, host_time_taken));

    if (argc == 3) {
      freopen(argv[2], "w", stdout);
      for (int i = 0; i < nodeCount; i++)
        cout << bwCentrality[i] << " ";
      cout << endl;
    }

    // Free all memory
    delete[] bwCentrality;
    catchCudaError(cudaFree(edgeList1));
    catchCudaError(cudaFree(edgeList2));
    catchCudaError(cudaFree(device_graph));
}
