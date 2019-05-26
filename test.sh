#!/bin/bash
nvcc cpugpu.cu -o bin/cpugpu -std=c++11 -O2 -Xcompiler -fopenmp
nvcc parallel-edge.cu -o bin/edge -std=c++11 -O2

for file in `echo custom1 custom2`; do
  ./bin/cpugpu testcases/in/$file out 5 > testcases/out/$file.cpugpu;
  ./bin/edge testcases/in/$file out > testcases/out/$file.edge;
  diff -q testcases/out/$file.cpugpu testcases/ans/$file;
  diff -q testcases/out/$file.edge testcases/ans/$file;
done
