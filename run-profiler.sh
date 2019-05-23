#!/bin/bash
for file in `echo testcases/in/1e4`; do
  for percent in `echo 0 25 50 75 100`; do
    nvprof --kernels betweennessCentralityKernel --analysis-metrics -o $file.$percent.prof ./bin/edge $file out $percent;
  done
done
