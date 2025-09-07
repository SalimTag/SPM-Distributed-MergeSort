#!/bin/bash
#SBATCH --job-name=mergesort_mpi
#SBATCH --output=results/mpi_test_%j.out
#SBATCH --error=results/mpi_test_%j.err
#SBATCH --nodes=4
#SBATCH --ntasks=8
#SBATCH --cpus-per-task=4
#SBATCH --time=00:30:00
#SBATCH --partition=normal

# SLURM script for MPI+OpenMP hybrid MergeSort testing
# Designed for SPM cluster - adjust parameters for your cluster

echo "=== MPI+OpenMP Hybrid MergeSort Test ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Nodes: $SLURM_JOB_NUM_NODES"
echo "Tasks: $SLURM_NTASKS" 
echo "CPUs per task: $SLURM_CPUS_PER_TASK"
echo "Partition: $SLURM_JOB_PARTITION"
echo "========================================"

# Load required modules for SPM cluster
echo "Loading modules..."
module load gcc/latest
module load openmpi/latest  
module load python/3

# Set OpenMP thread count
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
echo "OpenMP threads per MPI rank: $OMP_NUM_THREADS"

# Change to job directory
cd $SLURM_SUBMIT_DIR

# Create results directory if it doesn't exist
mkdir -p results

# Show cluster information
echo ""
echo "Cluster information:"
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo "Working directory: $(pwd)"

# Test data file
TEST_FILE="test_data/test1M_64B.bin"
OUTPUT_PREFIX="results/sorted_mpi"

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
echo "MPI ranks: $SLURM_NTASKS"
echo "OpenMP threads per rank: $OMP_NUM_THREADS"

# Run MPI tests with different rank configurations
echo ""
echo "=== Starting MPI+OpenMP Tests ==="

for ranks in 1 2 4 8; do
    if [ $ranks -le $SLURM_NTASKS ]; then
        output_file="${OUTPUT_PREFIX}_${ranks}ranks.bin"
        log_file="results/mpi_${ranks}ranks_${SLURM_JOB_ID}.log"
        
        echo ""
        echo "--- Testing with $ranks MPI ranks ---"
        echo "Output: $output_file"
        echo "Log: $log_file"
        
        # Run the test
        echo "Command: mpirun -np $ranks ./hybrid_sort_main $TEST_FILE $output_file"
        
        time mpirun -np $ranks ./hybrid_sort_main $TEST_FILE $output_file > $log_file 2>&1
        
        if [ $? -eq 0 ]; then
            echo "✅ Test with $ranks ranks completed successfully"
            
            # Verify output if verification script exists
            if [ -f "verify_output.py" ]; then
                echo "   Verifying output..."
                if python3 verify_output.py $output_file >> $log_file 2>&1; then
                    echo "   ✅ Output verification passed"
                else
                    echo "   ❌ Output verification failed"
                fi
            fi
            
            # Show performance info
            if grep -q "total sort time" $log_file; then
                echo "   Performance: $(grep 'total sort time' $log_file | tail -1)"
            fi
        else
            echo "❌ Test with $ranks ranks failed"
        fi
    fi
done

echo ""
echo "=== Performance Summary ==="
echo "Results saved in: results/"
echo "Job logs: results/mpi_*_${SLURM_JOB_ID}.log"

# Generate summary report
summary_file="results/performance_summary_${SLURM_JOB_ID}.txt"
echo "Performance Summary - Job $SLURM_JOB_ID" > $summary_file
echo "Generated: $(date)" >> $summary_file
echo "Test file: $TEST_FILE" >> $summary_file
echo "========================================" >> $summary_file

for log in results/mpi_*_${SLURM_JOB_ID}.log; do
    if [ -f "$log" ]; then
        ranks=$(echo $log | sed 's/.*mpi_\([0-9]*\)ranks.*/\1/')
        if grep -q "total sort time" $log; then
            time_info=$(grep "total sort time" $log | tail -1)
            echo "MPI Ranks $ranks: $time_info" >> $summary_file
        fi
    fi
done

echo ""
echo "Summary report: $summary_file"
cat $summary_file

echo ""
echo "=== Job Complete ==="
echo "Job ID: $SLURM_JOB_ID"
echo "End time: $(date)"
