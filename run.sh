#!/bin/bash
make parallelcpu
make edge
rm parallel-cpu.csv
rm edge.csv

for file in `echo testcases/in/facebook`; do
  # for i in `seq 1 5`; do
    for percent in `echo 0 25 50 75 100`; do
      ./bin/edge $file out $percent >> edge.csv;
      ./bin/parallel-cpu $file out $percent >> parallel-cpu.csv;
    done
  # done
done
