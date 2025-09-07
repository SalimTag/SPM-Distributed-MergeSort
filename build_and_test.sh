#!/bin/bash

# Distributed MergeSort - Comprehensive Build and Test Script
# Author: Salim Tagemouati
# University of Pisa - SPM Course

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check dependencies
check_dependencies() {
    print_status "Checking dependencies..."
    
    local deps_ok=true
    
    if ! command_exists g++; then
        print_error "g++ not found. Please install GCC compiler."
        deps_ok=false
    fi
    
    if ! command_exists mpirun; then
        print_error "mpirun not found. Please install OpenMPI."
        deps_ok=false
    fi
    
    if ! command_exists python3; then
        print_error "python3 not found. Please install Python 3."
        deps_ok=false
    fi
    
    # Check OpenMP support
    if ! g++ -fopenmp -x c++ -E - </dev/null >/dev/null 2>&1; then
        print_error "OpenMP support not found in g++."
        deps_ok=false
    fi
    
    if [ "$deps_ok" = false ]; then
        print_error "Missing dependencies. Please install required packages."
        exit 1
    fi
    
    print_success "All dependencies found"
}

# Build all targets
build_all() {
    print_status "Building all targets..."
    
    # Clean previous builds
    make clean >/dev/null 2>&1 || true
    
    # Build all targets
    if make all; then
        print_success "All targets built successfully"
    else
        print_error "Build failed"
        exit 1
    fi
}

# Generate test data
generate_test_data() {
    print_status "Generating test data..."
    
    if make generate-test-data; then
        print_success "Test data generated successfully"
    else
        print_error "Test data generation failed"
        exit 1
    fi
}

# Run comprehensive tests
run_tests() {
    print_status "Running comprehensive tests..."
    
    # Create output directory
    mkdir -p test_results
    
    local test_file="test_data/test500K_64B.bin"
    local threads=4
    
    print_status "Testing OpenMP implementation..."
    if timeout 60 ./openmp_sort "$test_file" "test_results/output_omp.bin" $threads; then
        if python3 verify_output.py "test_results/output_omp.bin" >/dev/null 2>&1; then
            print_success "OpenMP test PASSED"
        else
            print_error "OpenMP output verification FAILED"
            return 1
        fi
    else
        print_error "OpenMP test FAILED or TIMEOUT"
        return 1
    fi
    
    print_status "Testing FastFlow implementation..."
    if timeout 60 ./fastflow_sort "$test_file" "test_results/output_ff.bin" $threads; then
        if python3 verify_output.py "test_results/output_ff.bin" >/dev/null 2>&1; then
            print_success "FastFlow test PASSED"
        else
            print_error "FastFlow output verification FAILED"
            return 1
        fi
    else
        print_error "FastFlow test FAILED or TIMEOUT"
        return 1
    fi
    
    print_status "Testing MPI+OpenMP implementation..."
    if timeout 60 mpirun -np 1 ./hybrid_sort "$test_file" "test_results/output_hybrid.bin" $threads; then
        if python3 verify_output.py "test_results/output_hybrid.bin" >/dev/null 2>&1; then
            print_success "MPI+OpenMP test PASSED"
        else
            print_error "MPI+OpenMP output verification FAILED"
            return 1
        fi
    else
        print_error "MPI+OpenMP test FAILED or TIMEOUT"
        return 1
    fi
    
    print_status "Comparing outputs for consistency..."
    if cmp -s "test_results/output_omp.bin" "test_results/output_ff.bin"; then
        print_success "OpenMP vs FastFlow: IDENTICAL"
    else
        print_error "OpenMP vs FastFlow: DIFFERENT"
        return 1
    fi
    
    if cmp -s "test_results/output_omp.bin" "test_results/output_hybrid.bin"; then
        print_success "OpenMP vs MPI+OpenMP: IDENTICAL"
    else
        print_error "OpenMP vs MPI+OpenMP: DIFFERENT"
        return 1
    fi
    
    print_success "All tests PASSED"
}

# Run performance benchmarks
run_benchmarks() {
    print_status "Running performance benchmarks..."
    
    mkdir -p benchmark_results
    local test_file="test_data/test1M_64B.bin"
    local threads=4
    
    print_status "Benchmarking OpenMP (1M records, 64B payloads)..."
    time_result=$(timeout 300 /usr/bin/time -f "%e" ./openmp_sort "$test_file" "benchmark_results/bench_omp.bin" $threads 2>&1 | tail -n1)
    print_success "OpenMP completed in ${time_result}s"
    
    print_status "Benchmarking FastFlow (1M records, 64B payloads)..."
    time_result=$(timeout 300 /usr/bin/time -f "%e" ./fastflow_sort "$test_file" "benchmark_results/bench_ff.bin" $threads 2>&1 | tail -n1)
    print_success "FastFlow completed in ${time_result}s"
    
    print_status "Benchmarking MPI+OpenMP (1M records, 64B payloads)..."
    time_result=$(timeout 300 /usr/bin/time -f "%e" mpirun -np 1 ./hybrid_sort "$test_file" "benchmark_results/bench_hybrid.bin" $threads 2>&1 | tail -n1)
    print_success "MPI+OpenMP completed in ${time_result}s"
    
    print_success "All benchmarks completed"
}

# Test MPI scaling (if multiple cores available)
test_mpi_scaling() {
    local cores=$(nproc)
    if [ $cores -gt 1 ]; then
        print_status "Testing MPI scaling on $cores cores..."
        
        local test_file="test_data/test1M_64B.bin"
        
        for np in 1 2 4; do
            if [ $np -le $cores ]; then
                print_status "Testing with $np MPI ranks..."
                if timeout 120 mpirun -np $np ./hybrid_sort "$test_file" "test_results/output_mpi_${np}.bin" 2; then
                    if python3 verify_output.py "test_results/output_mpi_${np}.bin" >/dev/null 2>&1; then
                        print_success "MPI scaling test with $np ranks PASSED"
                    else
                        print_warning "MPI scaling test with $np ranks - verification FAILED"
                    fi
                else
                    print_warning "MPI scaling test with $np ranks FAILED or TIMEOUT"
                fi
            fi
        done
    else
        print_warning "Single core system - skipping MPI scaling tests"
    fi
}

# Main execution
main() {
    echo "======================================"
    echo "Distributed MergeSort - Build & Test"
    echo "======================================"
    echo ""
    
    # Parse command line arguments
    case "${1:-all}" in
        "deps")
            check_dependencies
            ;;
        "build")
            check_dependencies
            build_all
            ;;
        "test")
            check_dependencies
            build_all
            generate_test_data
            run_tests
            ;;
        "bench")
            check_dependencies
            build_all
            generate_test_data
            run_benchmarks
            ;;
        "scale")
            check_dependencies
            build_all
            generate_test_data
            test_mpi_scaling
            ;;
        "all")
            check_dependencies
            build_all
            generate_test_data
            run_tests
            run_benchmarks
            test_mpi_scaling
            ;;
        "clean")
            make clean
            rm -rf test_results benchmark_results
            print_success "Cleaned all build artifacts and test results"
            ;;
        "help")
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  deps     - Check dependencies only"
            echo "  build    - Build all targets"
            echo "  test     - Run functionality tests"
            echo "  bench    - Run performance benchmarks"
            echo "  scale    - Test MPI scaling"
            echo "  all      - Run everything (default)"
            echo "  clean    - Clean build artifacts"
            echo "  help     - Show this help"
            ;;
        *)
            print_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
    
    if [ "${1:-all}" != "help" ] && [ "${1:-all}" != "clean" ]; then
        echo ""
        print_success "Operation completed successfully!"
        echo ""
        echo "📁 Results:"
        [ -d "test_results" ] && echo "  - Test outputs: test_results/"
        [ -d "benchmark_results" ] && echo "  - Benchmarks: benchmark_results/"
        [ -d "test_data" ] && echo "  - Test data: test_data/"
        echo ""
        echo "🔧 Next steps:"
        echo "  - Run 'make help' for more build options"
        echo "  - Check README.md for detailed usage"
        echo "  - Use 'make prepare-cluster' for HPC deployment"
    fi
}

# Run main function with all arguments
main "$@"
