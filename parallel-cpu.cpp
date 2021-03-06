#include <omp.h>
#include "Graph.h"
using namespace std;

double *betweennessCentrality(Graph *graph, int nodeFrom, int nodeTo) {
  const int nodeCount = graph->getNodeCount();
  const int edgeCount = graph->getEdgeCount();

  double *bcs = new double[nodeCount];

  for (int i = 0; i < nodeCount; ++i) {
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

    for (int i = 0; i < nodeCount; ++i) {
      predecessor[i].reserve(20);
    }

    #pragma omp for schedule(dynamic, 4)
    for (int s = nodeFrom; s <= nodeTo; s++) {
      // Forward Propagation
      for (int i = 0; i < nodeCount; ++i) {
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

        for (int i = adjacencyListPointers[v]; i < adjacencyListPointers[v + 1];
             i++) {
          int w = adjacencyList[i];
          if (distance[w] < 0) {
            q.push(w);
            distance[w] = distance[v] + 1;
          }

          // Path Counting
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
    }

    #pragma omp critical
    {
      for (int i = 0; i < nodeCount; ++i) {
        bcs[i] += localBcs[i];
      }
    }
  }

  return bcs;
}

int main(int argc, char *argv[]) {
  if (argc < 3) {
    cout << "Usage: " << argv[0] << " <input_file> <output_file> <threshold>\n";
    return 0;
  }

  freopen(argv[1], "r", stdin);

  Graph *graph = new Graph();
  graph->readGraph();

  int nodeCount = graph->getNodeCount();
  int edgeCount = graph->getEdgeCount();

  // Set threshold
  const long threshold_percent = strtol(argv[3], NULL, 10);
  const int threshold = (int) ((float)nodeCount * (float)threshold_percent / (float) 100);
  const int nodeFrom = 0;
  const int nodeTo = threshold - 1;

  clock_t start, end;
  double wstart, wend;

  start = clock();
  wstart = omp_get_wtime();

  double *bwCentrality = betweennessCentrality(graph, nodeFrom, nodeTo);

  end = clock();
  wend = omp_get_wtime();

  double time_taken = 1000.0 * (end - start) / (float)CLOCKS_PER_SEC;
  double wtime_taken = wend - wstart;

  double maxBetweenness = -1;
  for (int i = 0; i < nodeCount; i++) {
    maxBetweenness = max(maxBetweenness, bwCentrality[i]);
  }

  printf("%s, %03d, ", argv[1], atoi(argv[3]));
  // printf("%0.2lf, ", maxBetweenness);
  // printf("%0.2lf, ", time_taken);
  printf("%0.2lf \n", wtime_taken * 1000);

  if (argc == 3) {
    freopen(argv[2], "w", stdout);
    for (int i = 0; i < nodeCount; i++) cout << bwCentrality[i] << " ";
    cout << endl;
  }

  // Free all memory
  delete[] bwCentrality;
  delete graph;

  return 0;
}
