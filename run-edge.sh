#!/bin/bash
make edge
rm edge.csv

for file in `echo testcases/in/1e3`; do
  for percent in `echo 0 25 50 75 100`; do
    nvprof --output-profile $file.$percent.prof ./bin/edge $file out $percent >> edge.csv;
  done
done
