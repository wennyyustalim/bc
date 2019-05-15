serial: serial.cpp
	g++ serial.cpp -o bin/serial -std=c++11 -O2

cpugpu:
	nvcc cpugpu.cu -o bin/hybrid -std=c++11 -O2 -Xcompiler -fopenmp

edge: parallel-edge.cu
	nvcc parallel-edge.cu -o bin/edge -std=c++11 -O2

node: parallel-node.cu
	nvcc parallel-node.cu -o bin/node -std=c++11

generator: tc_generator.cpp
	g++ tc_generator.cpp -o bin/tc_generator -std=c++11

parallelcpu: parallel-cpu.cpp
	g++ -o bin/parallel-cpu parallel-cpu.cpp -std=c++11 -O2 -fopenmp

test: test.cpp
	g++ -o bin/test test.cpp -std=c++11 -O2 -fopenmp
