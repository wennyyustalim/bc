#!/bin/bash
make parallelcpu
make edge
rm parallel-cpu.csv
rm edge.csv

for file in `echo testcases/in/sp500-038 testcases/in/bo testcases/in/cg-web testcases/in/as-rel testcases/in/hep-th`; do
  for i in `seq 1 5`; do
    ./bin/edge $file out >> edge.csv;
    for percent in `echo 1 5 10 20 30 40 50 75 100`; do
      ./bin/parallel-cpu $file out $percent >> parallel-cpu.csv;
    done
  done
done
