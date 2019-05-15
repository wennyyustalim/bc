#!/bin/bash
nvcc cpugpu.cu -o hybrid -std=c++11 -O2 -Xcompiler -fopenmp
nvcc parallel-edge.cu -o edge -std=c++11 -O2

for file in `echo custom1 custom2`; do
  ./hybrid testcases/in/$file out 5 > testcases/out/$file.hybrid;
  ./edge testcases/in/$file out > testcases/out/$file.edge;
  diff -q testcases/out/$file.hybrid testcases/ans/$file;
  diff -q testcases/out/$file.edge testcases/ans/$file;
done
