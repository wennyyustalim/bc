#!/bin/bash
for file in `echo testcases/in/1e4`; do
  for percent in `echo 0 25 50 75 100`; do
    scp m13515002@167.205.32.100:/home/m13515002/bc/$file.$percent.nvprof result/
  done
done
