#include "Graph.h"
using namespace std;

void printTime(float ms) {
  int h = ms / (1000 * 3600);
  int m = (((int)ms) / (1000 * 60)) % 60;
  int s = (((int)ms) / 1000) % 60;
  int intMS = ms;
  intMS %= 1000;

  printf("Time Taken (Serial) = %dh %dm %ds %dms\n", h, m, s, intMS);
  printf("Time Taken in milliseconds : %d\n", (int)ms);
}

double *calculateBc(Graph *graph) {
  const int nodeCount = graph->getNodeCount();

  double *bc = new double[nodeCount]();
  vector<int> *predecessor = new vector<int>[nodeCount];

  double *dependency = new double[nodeCount];
  int *sigma = new int[nodeCount];
  int *distance = new int[nodeCount];

  for (int s = 0; s < nodeCount; s++) {
    stack<int> st;

    memset(distance, -1, nodeCount * sizeof(int));
    memset(sigma, 0, nodeCount * sizeof(int));
    memset(dependency, 0, nodeCount * sizeof(double));

    distance[s] = 0;
    sigma[s] = 1;
    queue<int> q;
    q.push(s);

    while (!q.empty()) {
      int v = q.front();
      q.pop();
      st.push(v);

      for (int i = graph->adjacencyListPointers[v];
           i < graph->adjacencyListPointers[v + 1]; i++) {
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

      if (w != s) bc[w] += dependency[w] / 2;
    }

    for (int i = 0; i < nodeCount; ++i) {
      predecessor[i].clear();
    }
  }

  delete[] predecessor, sigma, dependency, distance;

  return bc;
}

int main(int argc, char *argv[]) {
  if (argc < 2) {
    cout << "Usage: " << argv[0] << " <graph_input_file> [output_file]\n";
    return 0;
  }

  char choice;
  cout << "Would you like to print the Graph Betweenness Centrality for all "
          "nodes? (y/n) ";
  cin >> choice;

  freopen(argv[1], "r", stdin);

  Graph *graph = new Graph();
  graph->readGraph();

  int nodeCount = graph->getNodeCount();
  int edgeCount = graph->getEdgeCount();

  clock_t start, end;
  start = clock();

  double *bc = calculateBc(graph);

  end = clock();
  float time_taken = 1000.0 * (end - start) / (float)CLOCKS_PER_SEC;

  double maxBetweenness = -1;
  for (int i = 0; i < nodeCount; i++) {
    maxBetweenness = max(maxBetweenness, bc[i]);
    if (choice == 'y' || choice == 'Y')
      printf("Node %d => Betweeness Centrality %0.2lf\n", i, bc[i]);
  }

  cout << endl;
  printf("\nMaximum Betweenness Centrality ==> %0.2lf\n", maxBetweenness);
  printTime(time_taken);

  if (argc == 3) {
    freopen(argv[2], "w", stdout);
    for (int i = 0; i < nodeCount; i++) cout << bc[i] << " ";
    cout << endl;
  }

  // Free all memory
  delete[] bc;
  delete graph;

  return 0;
}
