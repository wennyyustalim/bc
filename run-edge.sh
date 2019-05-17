#!/bin/bash
make edge
rm edge.csv

for file in `echo testcases/in/flickr`; do
  for percent in `echo 0 25 50 75 100`; do
    ./bin/edge $file out $percent >> edge.csv;
  done
done
