#!/bin/bash
make parallelcpu
bin/parallel-cpu testcases/in/1e4 testcases/out/1e4.parallel-cpu
