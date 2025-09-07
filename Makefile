# Distributed Out-of-Core MergeSort - Makefile
# Author: Salim Tagemouati
# University of Pisa - SPM Course

# Include local configuration if available
-include Makefile.config

# Default compiler settings
CXX ?= g++
MPICXX ?= mpicxx
CXXFLAGS = -std=c++17 -O3 -Wall -Wextra
OMPFLAGS = -fopenmp
FFFLAGS = -I./fastflow -pthread

# Target executables
OPENMP_TARGET = openmp_sort
FASTFLOW_TARGET = fastflow_sort
HYBRID_TARGET = hybrid_sort
GENERATOR_TARGET = generate_records
VERIFY_TARGET = verify_sort

# Source files
OPENMP_SRC = main_openmp.cpp
FASTFLOW_SRC = main_fastflow.cpp
HYBRID_SRC = main.cpp
GENERATOR_SRC = generate_records.cpp
VERIFY_SRC = verify_sort.cpp

# Header dependencies
HEADERS = record_structure.hpp mpi_openmp_sort.hpp omp_mergesort.hpp \
          openmp_sort.hpp fastflow_sort.hpp

# Default target
.PHONY: all clean test help

all: $(OPENMP_TARGET) $(FASTFLOW_TARGET) $(HYBRID_TARGET) $(GENERATOR_TARGET) $(VERIFY_TARGET)

# OpenMP version
$(OPENMP_TARGET): $(OPENMP_SRC) $(HEADERS)
	$(CXX) $(CXXFLAGS) $(OMPFLAGS) $(OPENMP_SRC) -o $(OPENMP_TARGET)
	@echo "✅ OpenMP version compiled successfully"

# FastFlow version  
$(FASTFLOW_TARGET): $(FASTFLOW_SRC) $(HEADERS)
	$(CXX) $(CXXFLAGS) $(FFFLAGS) $(FASTFLOW_SRC) -o $(FASTFLOW_TARGET)
	@echo "✅ FastFlow version compiled successfully"

# MPI+OpenMP hybrid version
$(HYBRID_TARGET): $(HYBRID_SRC) $(HEADERS)
	$(MPICXX) $(CXXFLAGS) $(OMPFLAGS) $(HYBRID_SRC) -o $(HYBRID_TARGET)
	@echo "✅ MPI+OpenMP hybrid version compiled successfully"

# Test data generator
$(GENERATOR_TARGET): $(GENERATOR_SRC)
	$(CXX) $(CXXFLAGS) $(GENERATOR_SRC) -o $(GENERATOR_TARGET)
	@echo "✅ Record generator compiled successfully"

# Verification utility
$(VERIFY_TARGET): $(VERIFY_SRC) $(HEADERS)
	$(CXX) $(CXXFLAGS) $(VERIFY_SRC) -o $(VERIFY_TARGET)
	@echo "✅ Verification utility compiled successfully"

# Alternative hybrid main
hybrid_alt: hybrid_sort_main.cpp $(HEADERS)
	$(MPICXX) $(CXXFLAGS) $(OMPFLAGS) hybrid_sort_main.cpp -o hybrid_sort_alt
	@echo "✅ Alternative hybrid version compiled successfully"

# Debug versions (with debug symbols)
debug: CXXFLAGS += -g -DDEBUG
debug: all
	@echo "✅ Debug versions compiled successfully"

# Generate test data
.PHONY: generate-test-data
generate-test-data: $(GENERATOR_TARGET)
	@echo "🔄 Generating test datasets..."
	@mkdir -p test_data
	./$(GENERATOR_TARGET) test_data/test1M_64B.bin 1000000 64
	./$(GENERATOR_TARGET) test_data/test1M_1024B.bin 1000000 1024
	./$(GENERATOR_TARGET) test_data/test500K_64B.bin 500000 64
	./$(GENERATOR_TARGET) test_data/test2M_64B.bin 2000000 64
	@echo "✅ Test datasets generated in test_data/"

# Run basic functionality test
.PHONY: test-basic
test-basic: all generate-test-data
	@echo "🧪 Running basic functionality tests..."
	@mkdir -p test_output
	
	# Test OpenMP version
	./$(OPENMP_TARGET) test_data/test500K_64B.bin test_output/output_omp.bin 4
	python3 verify_output.py test_output/output_omp.bin
	
	# Test FastFlow version
	./$(FASTFLOW_TARGET) test_data/test500K_64B.bin test_output/output_ff.bin 4
	python3 verify_output.py test_output/output_ff.bin
	
	# Test MPI+OpenMP version (single node)
	mpirun -np 1 ./$(HYBRID_TARGET) test_data/test500K_64B.bin test_output/output_hybrid.bin 4
	python3 verify_output.py test_output/output_hybrid.bin
	
	# Compare outputs (should be identical)
	@echo "🔍 Comparing outputs..."
	cmp test_output/output_omp.bin test_output/output_ff.bin && echo "✅ OpenMP vs FastFlow: IDENTICAL"
	cmp test_output/output_omp.bin test_output/output_hybrid.bin && echo "✅ OpenMP vs Hybrid: IDENTICAL"
	
	@echo "✅ All basic tests passed!"

# Performance benchmarks
.PHONY: benchmark
benchmark: all generate-test-data
	@echo "📊 Running performance benchmarks..."
	@mkdir -p benchmark_results
	
	# Single-node benchmarks
	@echo "Testing OpenMP performance..."
	time ./$(OPENMP_TARGET) test_data/test1M_64B.bin benchmark_results/bench_omp.bin 4
	
	@echo "Testing FastFlow performance..."
	time ./$(FASTFLOW_TARGET) test_data/test1M_64B.bin benchmark_results/bench_ff.bin 4
	
	@echo "Testing MPI+OpenMP performance..."
	time mpirun -np 1 ./$(HYBRID_TARGET) test_data/test1M_64B.bin benchmark_results/bench_hybrid.bin 4
	
	@echo "✅ Benchmarks completed. Results in benchmark_results/"

# Cluster test preparation
.PHONY: prepare-cluster
prepare-cluster: all
	@echo "🚀 Preparing for cluster deployment..."
	@echo "#!/bin/bash" > run_cluster_test.sh
	@echo "# SLURM job script for distributed mergesort" >> run_cluster_test.sh
	@echo "#SBATCH --nodes=8" >> run_cluster_test.sh
	@echo "#SBATCH --ntasks-per-node=1" >> run_cluster_test.sh
	@echo "#SBATCH --cpus-per-task=4" >> run_cluster_test.sh
	@echo "#SBATCH --time=00:30:00" >> run_cluster_test.sh
	@echo "#SBATCH --job-name=mergesort" >> run_cluster_test.sh
	@echo "" >> run_cluster_test.sh
	@echo "module load openmpi gcc" >> run_cluster_test.sh
	@echo "" >> run_cluster_test.sh
	@echo "# Test different MPI configurations" >> run_cluster_test.sh
	@echo "for np in 1 2 4 8; do" >> run_cluster_test.sh
	@echo "    echo \"Testing with \$$np MPI ranks...\"" >> run_cluster_test.sh
	@echo "    mpirun -np \$$np ./hybrid_sort test_data/test1M_64B.bin output_\$$np.bin 4" >> run_cluster_test.sh
	@echo "    python3 verify_output.py output_\$$np.bin" >> run_cluster_test.sh
	@echo "done" >> run_cluster_test.sh
	@chmod +x run_cluster_test.sh
	@echo "✅ Cluster test script created: run_cluster_test.sh"

# Clean build artifacts
clean:
	rm -f $(OPENMP_TARGET) $(FASTFLOW_TARGET) $(HYBRID_TARGET) 
	rm -f $(GENERATOR_TARGET) $(VERIFY_TARGET) hybrid_sort_alt
	rm -rf test_data test_output benchmark_results
	rm -f run_cluster_test.sh
	rm -f *.o *.out core.*
	@echo "🧹 Cleaned build artifacts and test data"

# Install dependencies (Ubuntu/Debian)
.PHONY: install-deps
install-deps:
	@echo "📦 Installing dependencies..."
	sudo apt-get update
	sudo apt-get install -y build-essential g++ libomp-dev openmpi-bin libopenmpi-dev python3
	@echo "✅ Dependencies installed"

# Help target
help:
	@echo "🔧 Available targets:"
	@echo "  all              - Build all executables"
	@echo "  openmp_sort      - Build OpenMP version only"
	@echo "  fastflow_sort    - Build FastFlow version only" 
	@echo "  hybrid_sort      - Build MPI+OpenMP version only"
	@echo "  generate_records - Build test data generator"
	@echo "  verify_sort      - Build verification utility"
	@echo "  debug           - Build debug versions with symbols"
	@echo ""
	@echo "🧪 Testing targets:"
	@echo "  generate-test-data - Generate test datasets"
	@echo "  test-basic         - Run basic functionality tests"
	@echo "  benchmark          - Run performance benchmarks"
	@echo "  prepare-cluster    - Create cluster job script"
	@echo ""
	@echo "🧹 Utility targets:"
	@echo "  clean              - Remove build artifacts"
	@echo "  install-deps       - Install system dependencies"
	@echo "  help               - Show this help message"
	@echo ""
	@echo "📖 Usage examples:"
	@echo "  make all && make test-basic"
	@echo "  make benchmark"
	@echo "  make prepare-cluster && sbatch run_cluster_test.sh"
