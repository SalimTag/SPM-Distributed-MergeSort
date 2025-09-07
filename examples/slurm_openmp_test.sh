#!/bin/bash
#SBATCH --job-name=mergesort_openmp
#SBATCH --output=results/openmp_test_%j.out
#SBATCH --error=results/openmp_test_%j.err
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --time=00:15:00
#SBATCH --partition=normal

# SLURM script for OpenMP MergeSort testing
# Single-node multi-threaded performance evaluation

echo "=== OpenMP MergeSort Performance Test ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURM_JOB_NODELIST"
echo "CPUs available: $SLURM_CPUS_PER_TASK"
echo "======================================="

# Load required modules
echo "Loading modules..."
module load gcc/latest
module load python/3

# Change to job directory
cd $SLURM_SUBMIT_DIR

# Create results directory
mkdir -p results

# Test data file
TEST_FILE="test_data/test1M_64B.bin"

# Verify test data exists
if [ ! -f "$TEST_FILE" ]; then
    echo "ERROR: Test file $TEST_FILE not found!"
    echo "Generate it with: ./generate_records $TEST_FILE 1000000 64"
    exit 1
fi

echo ""
echo "Test configuration:"
echo "Input file: $TEST_FILE"
echo "File size: $(ls -lh $TEST_FILE | awk '{print $5}')"

# Test different thread counts
echo ""
echo "=== OpenMP Thread Scaling Test ==="

summary_file="results/openmp_summary_${SLURM_JOB_ID}.txt"
echo "OpenMP Performance Summary - Job $SLURM_JOB_ID" > $summary_file
echo "Generated: $(date)" >> $summary_file
echo "Test file: $TEST_FILE" >> $summary_file
echo "Node: $(hostname)" >> $summary_file
echo "=====================================" >> $summary_file

for threads in 1 2 4 8 12 16; do
    if [ $threads -le $SLURM_CPUS_PER_TASK ]; then
        output_file="results/sorted_openmp_${threads}t.bin"
        log_file="results/openmp_${threads}t_${SLURM_JOB_ID}.log"
        
        export OMP_NUM_THREADS=$threads
        
        echo ""
        echo "--- Testing with $threads OpenMP threads ---"
        echo "Output: $output_file"
        echo "Log: $log_file"
        
        # Run the test
        echo "Command: ./main_openmp $TEST_FILE $output_file"
        
        time ./main_openmp $TEST_FILE $output_file > $log_file 2>&1
        
        if [ $? -eq 0 ]; then
            echo "✅ Test with $threads threads completed successfully"
            
            # Verify output
            if [ -f "verify_output.py" ]; then
                echo "   Verifying output..."
                if python3 verify_output.py $output_file >> $log_file 2>&1; then
                    echo "   ✅ Output verification passed"
                else
                    echo "   ❌ Output verification failed"
                fi
            fi
            
            # Extract performance info
            if grep -q "Total sort time" $log_file; then
                time_info=$(grep "Total sort time" $log_file | tail -1)
                echo "   Performance: $time_info"
                echo "Threads $threads: $time_info" >> $summary_file
            fi
        else
            echo "❌ Test with $threads threads failed"
            echo "Threads $threads: FAILED" >> $summary_file
        fi
    fi
done

echo ""
echo "=== FastFlow Comparison Test ==="

# Test FastFlow if binary exists
if [ -f "./main_fastflow" ]; then
    output_file="results/sorted_fastflow.bin"
    log_file="results/fastflow_${SLURM_JOB_ID}.log"
    
    echo "Testing FastFlow implementation..."
    echo "Output: $output_file"
    
    time ./main_fastflow $TEST_FILE $output_file > $log_file 2>&1
    
    if [ $? -eq 0 ]; then
        echo "✅ FastFlow test completed successfully"
        
        if [ -f "verify_output.py" ]; then
            echo "   Verifying FastFlow output..."
            if python3 verify_output.py $output_file >> $log_file 2>&1; then
                echo "   ✅ FastFlow output verification passed"
            else
                echo "   ❌ FastFlow output verification failed"
            fi
        fi
        
        if grep -q "Total sort time" $log_file; then
            time_info=$(grep "Total sort time" $log_file | tail -1)
            echo "   FastFlow Performance: $time_info"
            echo "FastFlow: $time_info" >> $summary_file
        fi
    else
        echo "❌ FastFlow test failed"
        echo "FastFlow: FAILED" >> $summary_file
    fi
else
    echo "⚠️  FastFlow binary not found, skipping FastFlow test"
    echo "FastFlow: NOT AVAILABLE" >> $summary_file
fi

echo ""
echo "=== Performance Summary ==="
cat $summary_file

echo ""
echo "=== Job Complete ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Summary: $summary_file"
echo "All logs: results/*_${SLURM_JOB_ID}.log"
echo "End time: $(date)"
