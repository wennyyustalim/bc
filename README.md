# Optimizing Betweenness Centrality with CUDA and OpenMP

- [Wenny Yustalim](https://github.com/wennyyustalim)

## Introduction

This repository is meant for my final project. Some code implementations are modified from [this repository](https://github.com/pvgupta24/Graph-Betweenness-Centrality).

## Running Instructions

### Generating Graphs

Create testcases folder

`mkdir testcases && mkdir testcases/in && mkdir testcases/out`

Create bin folder

`mkdir bin`

Compile everything

`make`

Run graph generator to make testcases

` ./bin/tc_generator testcases/in/<filename>`

> Enter number of nodes: 1000 <br>
Enter number of edges: 1000

### Serial Implementation

Compile the serial BC implementation using

`g++ serial.cpp -o _serial -std=c++11`

Run the generated binary against the graphs generated in CSR formats as:

`./_serial testcases/1x/1e3.in testcases/1x/1e3s.out`

### Parallel Implementation
1. node based

    Compile and Run using

    `nvcc parallel-node.cpp -o _parallel_node -std=c++11`

    `./_parallel_node testcases/1x/1e3.in testcases/1x/1e3pv.out`

2. Edge based

    Compile and Run using

    `nvcc parallel-edge.cpp -o _parallel_edge -std=c++11`

    `./_parallel_edge testcases/1x/1e3.in testcases/1x/1e3pe.out`

> Note: Amount of blocks running in parallel can be controlled by changing the maximize
GPU memory to be allocated in MAX_MEMORY. By default it uses a maximum of 4GB.
