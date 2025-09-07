#!/bin/bash

# Comprehensive test runner for Distributed MergeSort
# Supports both local and cluster environments

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
TEST_DATA_DIR="test_data"
RESULTS_DIR="results"
LOG_FILE="$RESULTS_DIR/test_run_$(date +%Y%m%d_%H%M%S).log"

# Create directories
mkdir -p "$TEST_DATA_DIR" "$RESULTS_DIR"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
}

print_header() {
    echo ""
    echo "=============================================="
    echo "  Distributed Out-of-Core MergeSort Tests"
    echo "=============================================="
    echo "Started: $(date)"
    echo "Log file: $LOG_FILE"
    echo "=============================================="
    echo ""
}

check_environment() {
    print_info "Checking environment..."
    
    local missing=0
    
    # Check basic tools
    for cmd in g++ make python3; do
        if ! command -v $cmd >/dev/null 2>&1; then
            print_error "$cmd not found"
            missing=1
        fi
    done
    
    # Check MPI (optional for single-node tests)
    if command -v mpirun >/dev/null 2>&1; then
        print_success "MPI support available"
        MPI_AVAILABLE=true
    else
        print_warning "MPI not available - skipping distributed tests"
        MPI_AVAILABLE=false
    fi
    
    # Check if we're on a cluster
    if command -v sbatch >/dev/null 2>&1; then
        print_success "SLURM detected - cluster environment"
        CLUSTER_ENV=true
    else
        print_info "No SLURM - local environment"
        CLUSTER_ENV=false
    fi
    
    if [ $missing -eq 1 ]; then
        print_error "Missing required dependencies"
        exit 1
    fi
    
    print_success "Environment check passed"
}

build_project() {
    print_info "Building project..."
    
    log "Starting build process"
    
    # Initialize FastFlow if needed
    if [ ! -f "fastflow/ff/ff.hpp" ]; then
        print_info "Initializing FastFlow submodule..."
        git submodule update --init --recursive 2>&1 | tee -a "$LOG_FILE"
    fi
    
    # Build
    if make clean && make all 2>&1 | tee -a "$LOG_FILE"; then
        print_success "Build completed successfully"
        log "Build successful"
    else
        print_error "Build failed"
        log "Build failed"
        exit 1
    fi
}

generate_test_data() {
    print_info "Generating test data..."
    
    # Standard test datasets
    local datasets=(
        "test1M_64B.bin:1000000:64"
        "test500K_64B.bin:500000:64"
        "test1M_1024B.bin:1000000:1024"
    )
    
    for dataset in "${datasets[@]}"; do
        IFS=':' read -r filename records payload <<< "$dataset"
        filepath="$TEST_DATA_DIR/$filename"
        
        if [ ! -f "$filepath" ]; then
            print_info "Generating $filename ($records records, ${payload}B payload)..."
            if ./generate_records "$filepath" "$records" "$payload" 2>&1 | tee -a "$LOG_FILE"; then
                print_success "Generated $filename ($(ls -lh $filepath | awk '{print $5}'))"
                log "Generated test data: $filename"
            else
                print_error "Failed to generate $filename"
                log "Failed to generate: $filename"
                exit 1
            fi
        else
            print_info "$filename already exists ($(ls -lh $filepath | awk '{print $5}'))"
        fi
    done
}

run_openmp_tests() {
    print_info "Running OpenMP tests..."
    
    local test_file="$TEST_DATA_DIR/test1M_64B.bin"
    local threads_list="1 2 4 8"
    
    if [ ! -f "$test_file" ]; then
        print_error "Test file $test_file not found"
        return 1
    fi
    
    echo ""
    echo "OpenMP Performance Results:"
    echo "=========================="
    
    for threads in $threads_list; do
        local output="$RESULTS_DIR/sorted_openmp_${threads}t.bin"
        local log_file="$RESULTS_DIR/openmp_${threads}t.log"
        
        export OMP_NUM_THREADS=$threads
        
        print_info "Testing OpenMP with $threads threads..."
        
        if timeout 300 ./main_openmp "$test_file" "$output" > "$log_file" 2>&1; then
            # Verify output
            if python3 verify_output.py "$output" >> "$log_file" 2>&1; then
                local time_ms=$(grep "Total sort time" "$log_file" | grep -o '[0-9]\+' | tail -1)
                print_success "OpenMP $threads threads: ${time_ms}ms ✓"
                echo "OpenMP,$threads,${time_ms},SUCCESS" >> "$RESULTS_DIR/performance.csv"
                log "OpenMP test successful: $threads threads, ${time_ms}ms"
            else
                print_error "OpenMP $threads threads: Verification failed"
                echo "OpenMP,$threads,UNKNOWN,VERIFY_FAILED" >> "$RESULTS_DIR/performance.csv"
                log "OpenMP verification failed: $threads threads"
            fi
        else
            print_error "OpenMP $threads threads: Execution failed"
            echo "OpenMP,$threads,UNKNOWN,EXEC_FAILED" >> "$RESULTS_DIR/performance.csv"
            log "OpenMP execution failed: $threads threads"
        fi
    done
}

run_fastflow_tests() {
    print_info "Running FastFlow tests..."
    
    local test_file="$TEST_DATA_DIR/test1M_64B.bin"
    local output="$RESULTS_DIR/sorted_fastflow.bin"
    local log_file="$RESULTS_DIR/fastflow.log"
    
    if [ ! -f "./main_fastflow" ]; then
        print_warning "FastFlow binary not found, skipping FastFlow tests"
        return 0
    fi
    
    if [ ! -f "$test_file" ]; then
        print_error "Test file $test_file not found"
        return 1
    fi
    
    print_info "Testing FastFlow implementation..."
    
    if timeout 300 ./main_fastflow "$test_file" "$output" > "$log_file" 2>&1; then
        if python3 verify_output.py "$output" >> "$log_file" 2>&1; then
            local time_ms=$(grep "Total sort time" "$log_file" | grep -o '[0-9]\+' | tail -1)
            print_success "FastFlow: ${time_ms}ms ✓"
            echo "FastFlow,AUTO,${time_ms},SUCCESS" >> "$RESULTS_DIR/performance.csv"
            log "FastFlow test successful: ${time_ms}ms"
        else
            print_error "FastFlow: Verification failed"
            echo "FastFlow,AUTO,UNKNOWN,VERIFY_FAILED" >> "$RESULTS_DIR/performance.csv"
            log "FastFlow verification failed"
        fi
    else
        print_error "FastFlow: Execution failed"
        echo "FastFlow,AUTO,UNKNOWN,EXEC_FAILED" >> "$RESULTS_DIR/performance.csv"
        log "FastFlow execution failed"
    fi
}

run_mpi_tests() {
    if [ "$MPI_AVAILABLE" != true ]; then
        print_warning "MPI not available, skipping distributed tests"
        return 0
    fi
    
    print_info "Running MPI+OpenMP tests..."
    
    local test_file="$TEST_DATA_DIR/test1M_64B.bin"
    local ranks_list="1 2 4"
    
    if [ ! -f "$test_file" ]; then
        print_error "Test file $test_file not found"
        return 1
    fi
    
    if [ ! -f "./hybrid_sort_main" ]; then
        print_warning "MPI binary not found, skipping MPI tests"
        return 0
    fi
    
    export OMP_NUM_THREADS=4  # Fixed threads per rank
    
    echo ""
    echo "MPI+OpenMP Performance Results:"
    echo "=============================="
    
    for ranks in $ranks_list; do
        local output="$RESULTS_DIR/sorted_mpi_${ranks}r.bin"
        local log_file="$RESULTS_DIR/mpi_${ranks}r.log"
        
        print_info "Testing MPI with $ranks ranks..."
        
        if timeout 600 mpirun -np $ranks ./hybrid_sort_main "$test_file" "$output" > "$log_file" 2>&1; then
            if python3 verify_output.py "$output" >> "$log_file" 2>&1; then
                local time_ms=$(grep "total sort time" "$log_file" | grep -o '[0-9]\+' | tail -1)
                print_success "MPI $ranks ranks: ${time_ms}ms ✓"
                echo "MPI,$ranks,${time_ms},SUCCESS" >> "$RESULTS_DIR/performance.csv"
                log "MPI test successful: $ranks ranks, ${time_ms}ms"
            else
                print_error "MPI $ranks ranks: Verification failed"
                echo "MPI,$ranks,UNKNOWN,VERIFY_FAILED" >> "$RESULTS_DIR/performance.csv"
                log "MPI verification failed: $ranks ranks"
            fi
        else
            print_error "MPI $ranks ranks: Execution failed"
            echo "MPI,$ranks,UNKNOWN,EXEC_FAILED" >> "$RESULTS_DIR/performance.csv"
            log "MPI execution failed: $ranks ranks"
        fi
    done
}

run_cluster_tests() {
    if [ "$CLUSTER_ENV" != true ]; then
        print_info "Not in cluster environment, skipping SLURM tests"
        return 0
    fi
    
    print_info "Submitting cluster tests..."
    
    # Submit SLURM jobs if we're on a cluster
    if [ -f "examples/slurm_mpi_test.sh" ]; then
        print_info "Submitting MPI scaling test..."
        local job_id=$(sbatch examples/slurm_mpi_test.sh | grep -o '[0-9]\+')
        print_success "Submitted job $job_id for MPI testing"
        log "Submitted SLURM job: $job_id (MPI test)"
    fi
    
    if [ -f "examples/slurm_openmp_test.sh" ]; then
        print_info "Submitting OpenMP scaling test..."
        local job_id=$(sbatch examples/slurm_openmp_test.sh | grep -o '[0-9]\+')
        print_success "Submitted job $job_id for OpenMP testing"
        log "Submitted SLURM job: $job_id (OpenMP test)"
    fi
    
    print_info "Check job status with: squeue -u $USER"
}

generate_report() {
    print_info "Generating performance report..."
    
    local report_file="$RESULTS_DIR/performance_report.txt"
    
    cat > "$report_file" << EOF
Distributed MergeSort Performance Report
=======================================
Generated: $(date)
Environment: $(if [ "$CLUSTER_ENV" = true ]; then echo "Cluster (SLURM)"; else echo "Local"; fi)
MPI Available: $MPI_AVAILABLE

Hardware Information:
$(if command -v lscpu >/dev/null 2>&1; then lscpu | grep -E "(Model name|CPU\(s\)|Thread|Memory)"; fi)

Test Results:
EOF

    if [ -f "$RESULTS_DIR/performance.csv" ]; then
        echo "" >> "$report_file"
        echo "Performance Summary:" >> "$report_file"
        echo "===================" >> "$report_file"
        
        while IFS=',' read -r impl threads time status; do
            if [ "$status" = "SUCCESS" ]; then
                echo "$impl with $threads threads/ranks: $time ms" >> "$report_file"
            else
                echo "$impl with $threads threads/ranks: $status" >> "$report_file"
            fi
        done < "$RESULTS_DIR/performance.csv"
    fi
    
    print_success "Report generated: $report_file"
    
    # Show quick summary
    echo ""
    echo "Performance Summary:"
    echo "==================="
    if [ -f "$RESULTS_DIR/performance.csv" ]; then
        cat "$RESULTS_DIR/performance.csv" | while IFS=',' read -r impl threads time status; do
            if [ "$status" = "SUCCESS" ]; then
                echo "  $impl ($threads): $time ms"
            fi
        done
    fi
}

main() {
    print_header
    
    # Initialize CSV header
    echo "Implementation,Threads_Ranks,Time_ms,Status" > "$RESULTS_DIR/performance.csv"
    
    log "Starting comprehensive test run"
    
    check_environment
    build_project
    generate_test_data
    
    # Run tests
    run_openmp_tests
    run_fastflow_tests
    run_mpi_tests
    
    # Submit cluster tests if available
    run_cluster_tests
    
    generate_report
    
    print_success "Test run completed successfully!"
    print_info "Results saved in: $RESULTS_DIR/"
    print_info "Full log: $LOG_FILE"
    
    log "Test run completed successfully"
}

# Parse command line arguments
case "${1:-all}" in
    "all")
        main
        ;;
    "env")
        check_environment
        ;;
    "build")
        build_project
        ;;
    "data")
        generate_test_data
        ;;
    "openmp")
        check_environment
        build_project
        generate_test_data
        run_openmp_tests
        ;;
    "fastflow")
        check_environment
        build_project
        generate_test_data
        run_fastflow_tests
        ;;
    "mpi")
        check_environment
        build_project
        generate_test_data
        run_mpi_tests
        ;;
    "cluster")
        run_cluster_tests
        ;;
    *)
        echo "Usage: $0 {all|env|build|data|openmp|fastflow|mpi|cluster}"
        echo ""
        echo "Commands:"
        echo "  all      - Run complete test suite (default)"
        echo "  env      - Check environment only"
        echo "  build    - Build project only"
        echo "  data     - Generate test data only"
        echo "  openmp   - Run OpenMP tests only"
        echo "  fastflow - Run FastFlow tests only"  
        echo "  mpi      - Run MPI tests only"
        echo "  cluster  - Submit cluster jobs only"
        exit 1
        ;;
esac
