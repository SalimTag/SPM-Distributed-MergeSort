#!/bin/bash
#SBATCH --job-name=mergesort_comprehensive
#SBATCH --output=results/comprehensive_%j.out
#SBATCH --error=results/comprehensive_%j.err
#SBATCH --nodes=8
#SBATCH --ntasks=16
#SBATCH --cpus-per-task=8
#SBATCH --time=01:00:00
#SBATCH --partition=normal

# Comprehensive MergeSort testing across all implementations
# This script tests scalability from single-node to multi-node

echo "=== Comprehensive MergeSort Performance Analysis ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Nodes: $SLURM_JOB_NUM_NODES"
echo "Max Tasks: $SLURM_NTASKS"
echo "CPUs per task: $SLURM_CPUS_PER_TASK"
echo "==============================================="

# Load required modules
module load gcc/latest openmpi/latest python/3

# Change to job directory and create results
cd $SLURM_SUBMIT_DIR
mkdir -p results

# Test datasets
declare -a DATASETS=(
    "test_data/test1M_64B.bin:1M_64B"
    "test_data/test1M_1024B.bin:1M_1024B"
    "test_data/test2M_64B.bin:2M_64B"
)

# Generate test data if needed
echo "Preparing test datasets..."
for dataset_info in "${DATASETS[@]}"; do
    IFS=':' read -r file label <<< "$dataset_info"
    
    if [ ! -f "$file" ]; then
        echo "Generating $file..."
        case $label in
            "1M_64B")
                ./generate_records "$file" 1000000 64
                ;;
            "1M_1024B")
                ./generate_records "$file" 1000000 1024
                ;;
            "2M_64B")
                ./generate_records "$file" 2000000 64
                ;;
        esac
    fi
    
    if [ -f "$file" ]; then
        echo "✅ $file ready ($(ls -lh $file | awk '{print $5}'))"
    else
        echo "❌ Failed to prepare $file"
    fi
done

# Initialize comprehensive results file
comp_results="results/comprehensive_results_${SLURM_JOB_ID}.csv"
echo "Implementation,Dataset,Threads/Ranks,Time_ms,Status,Verification" > $comp_results

echo ""
echo "=== Single-Node Performance Tests ==="

# Test each dataset with OpenMP
for dataset_info in "${DATASETS[@]}"; do
    IFS=':' read -r file label <<< "$dataset_info"
    
    if [ ! -f "$file" ]; then
        echo "⚠️  Skipping $label - file not found"
        continue
    fi
    
    echo ""
    echo "--- OpenMP tests for $label ---"
    
    for threads in 1 2 4 8 16; do
        if [ $threads -le $SLURM_CPUS_PER_TASK ]; then
            export OMP_NUM_THREADS=$threads
            output="results/openmp_${label}_${threads}t.bin"
            log="results/openmp_${label}_${threads}t.log"
            
            echo "Testing OpenMP $threads threads on $label..."
            
            if timeout 300 ./main_openmp "$file" "$output" > "$log" 2>&1; then
                if python3 verify_output.py "$output" >> "$log" 2>&1; then
                    time_ms=$(grep "Total sort time" "$log" | tail -1 | grep -o '[0-9]*' | tail -1)
                    echo "OpenMP,$label,$threads,${time_ms:-UNKNOWN},SUCCESS,PASSED" >> $comp_results
                    echo "  ✅ $threads threads: ${time_ms}ms"
                else
                    echo "OpenMP,$label,$threads,UNKNOWN,SUCCESS,FAILED" >> $comp_results
                    echo "  ❌ $threads threads: Verification failed"
                fi
            else
                echo "OpenMP,$label,$threads,UNKNOWN,FAILED,UNKNOWN" >> $comp_results
                echo "  ❌ $threads threads: Execution failed"
            fi
        fi
    done
    
    # Test FastFlow if available
    if [ -f "./main_fastflow" ]; then
        echo "Testing FastFlow on $label..."
        output="results/fastflow_${label}.bin"
        log="results/fastflow_${label}.log"
        
        if timeout 300 ./main_fastflow "$file" "$output" > "$log" 2>&1; then
            if python3 verify_output.py "$output" >> "$log" 2>&1; then
                time_ms=$(grep "Total sort time" "$log" | tail -1 | grep -o '[0-9]*' | tail -1)
                echo "FastFlow,$label,AUTO,${time_ms:-UNKNOWN},SUCCESS,PASSED" >> $comp_results
                echo "  ✅ FastFlow: ${time_ms}ms"
            else
                echo "FastFlow,$label,AUTO,UNKNOWN,SUCCESS,FAILED" >> $comp_results
                echo "  ❌ FastFlow: Verification failed"
            fi
        else
            echo "FastFlow,$label,AUTO,UNKNOWN,FAILED,UNKNOWN" >> $comp_results
            echo "  ❌ FastFlow: Execution failed"
        fi
    fi
done

echo ""
echo "=== Multi-Node MPI Tests ==="

# Test MPI scaling with the primary dataset
primary_file="test_data/test1M_64B.bin"
primary_label="1M_64B"

if [ -f "$primary_file" ]; then
    export OMP_NUM_THREADS=4  # Fixed threads per rank for MPI tests
    
    for ranks in 1 2 4 8 16; do
        if [ $ranks -le $SLURM_NTASKS ]; then
            output="results/mpi_${primary_label}_${ranks}r.bin"
            log="results/mpi_${primary_label}_${ranks}r.log"
            
            echo "Testing MPI $ranks ranks on $primary_label..."
            
            if timeout 600 mpirun -np $ranks ./hybrid_sort_main "$primary_file" "$output" > "$log" 2>&1; then
                if python3 verify_output.py "$output" >> "$log" 2>&1; then
                    time_ms=$(grep "total sort time" "$log" | tail -1 | grep -o '[0-9]*' | tail -1)
                    echo "MPI_OpenMP,$primary_label,$ranks,${time_ms:-UNKNOWN},SUCCESS,PASSED" >> $comp_results
                    echo "  ✅ $ranks ranks: ${time_ms}ms"
                else
                    echo "MPI_OpenMP,$primary_label,$ranks,UNKNOWN,SUCCESS,FAILED" >> $comp_results
                    echo "  ❌ $ranks ranks: Verification failed"
                fi
            else
                echo "MPI_OpenMP,$primary_label,$ranks,UNKNOWN,FAILED,UNKNOWN" >> $comp_results
                echo "  ❌ $ranks ranks: Execution failed"
            fi
        fi
    done
else
    echo "⚠️  Primary test file not found, skipping MPI tests"
fi

echo ""
echo "=== Generating Performance Report ==="

# Create detailed performance report
report_file="results/performance_report_${SLURM_JOB_ID}.txt"

cat > "$report_file" << EOF
Comprehensive MergeSort Performance Analysis
==========================================
Job ID: $SLURM_JOB_ID
Date: $(date)
Cluster: $(hostname)
Nodes: $SLURM_JOB_NUM_NODES
Max Tasks: $SLURM_NTASKS
CPUs per Task: $SLURM_CPUS_PER_TASK

Test Environment:
$(module list 2>&1)

Performance Results:
EOF

# Process CSV results into readable format
echo "" >> "$report_file"
echo "Single-Node OpenMP Results:" >> "$report_file"
echo "===========================" >> "$report_file"
grep "OpenMP" "$comp_results" | while IFS=',' read -r impl dataset threads time status verif; do
    echo "$dataset with $threads threads: $time ms ($status, $verif)" >> "$report_file"
done

echo "" >> "$report_file"
echo "FastFlow Results:" >> "$report_file"
echo "================" >> "$report_file"
grep "FastFlow" "$comp_results" | while IFS=',' read -r impl dataset threads time status verif; do
    echo "$dataset: $time ms ($status, $verif)" >> "$report_file"
done

echo "" >> "$report_file"
echo "Multi-Node MPI+OpenMP Results:" >> "$report_file"
echo "=============================" >> "$report_file"
grep "MPI_OpenMP" "$comp_results" | while IFS=',' read -r impl dataset ranks time status verif; do
    echo "$dataset with $ranks ranks: $time ms ($status, $verif)" >> "$report_file"
done

echo ""
echo "=== Results Summary ==="
echo "Detailed CSV: $comp_results"
echo "Performance Report: $report_file"
echo ""
echo "Quick Performance Overview:"
echo "=========================="

# Show best times for each implementation
echo "Best OpenMP time: $(grep "OpenMP.*SUCCESS.*PASSED" "$comp_results" | awk -F',' 'BEGIN{min=999999} {if($4<min && $4>0) min=$4} END{print min}') ms"
echo "FastFlow time: $(grep "FastFlow.*SUCCESS.*PASSED" "$comp_results" | awk -F',' '{print $4}' | head -1) ms"
echo "Best MPI time: $(grep "MPI_OpenMP.*SUCCESS.*PASSED" "$comp_results" | awk -F',' 'BEGIN{min=999999} {if($4<min && $4>0) min=$4} END{print min}') ms"

echo ""
echo "=== Job Complete ==="
echo "End time: $(date)"
echo "All results in: results/"
