#include <bits/stdc++.h>
using namespace std;

int main(int argc, char *argv[]) {
  if (argc < 2) {
    cout << "Usage: " << argv[0] << " <graph_file_name>\n";
    return 0;
  }

  int n, m;
  int x, y;

  cout << "Enter number of nodes: ";
  cin >> n;
  cout << "Enter number of edges: ";
  cin >> m;

  freopen(argv[1], "w", stdout);
  cout << n << " " << m << endl;

  vector<int> *v = new vector<int>[n + 1];

  // srand(time(0));
  // By defaut srand(0), so the generated graphs are same everytime
  for (int i = 0; i < m; i++) {
    do {
      x = rand() % n;
      y = rand() % n;
    } while (x == y);

    // Edge between x and y
    v[x].push_back(y);
    v[y].push_back(x);
  }

  // R
  cout << "0 ";
  int cur = 0;
  for (int i = 0; i < n; i++) {
    cur += v[i].size();
    cout << cur << " ";
  }
  cout << endl;

  // C
  for (int i = 0; i < n; i++)
    for (int it : v[i]) cout << it << " ";
  cout << endl;

  delete[] v;
}
