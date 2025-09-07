# Distributed Out-of-Core MergeSort

[![C++](https://img.shields.io/badge/language-C%2B%2B-blue.svg)](https://isocpp.org/)
[![OpenMP](https://img.shields.io/badge/parallel-OpenMP-green.svg)](https://www.openmp.org/)
[![FastFlow](https://img.shields.io/badge/framework-FastFlow-orange.svg)](https://github.com/fastflow/fastflow)
[![MPI](https://img.shields.io/badge/distributed-MPI-red.svg)](https://www.mpi-forum.org/)

A scalable, distributed, out-of-core MergeSort implementation for variable-sized records using multiple parallel programming paradigms: **OpenMP**, **FastFlow**, and **MPI+OpenMP hybrid**.

## 🎯 Project Overview

This project implements a high-performance external sorting algorithm capable of handling datasets that exceed available system memory. The implementation supports three different parallel programming approaches, each optimized for specific computational scenarios.

### Key Features

- **📊 Variable Record Support**: Handles records with payload sizes from 8 bytes to 4096 bytes
- **💾 Out-of-Core Processing**: Processes files larger than available RAM (tested up to 32GB datasets)
- **🔄 Three Parallel Implementations**: OpenMP, FastFlow, and MPI+OpenMP hybrid
- **✅ Output Verification**: Comprehensive testing with bitwise-identical output verification
- **🚀 High Performance**: Optimized for single-node and multi-node distributed systems
- **🛡️ Memory Safe**: RAII-based memory management with smart pointers

## 🏗️ Architecture

### Record Structure

```cpp
struct Record {
    uint64_t key;        // 8-byte sorting key
    uint32_t len;        // 4-byte payload length (8 ≤ len ≤ 4096)
    char payload[];      // Variable-length payload
};
```

### Implementation Approaches

1. **OpenMP Task-Based**: Recursive divide-and-conquer with dynamic load balancing
2. **FastFlow Pattern-Based**: Farm and pipeline patterns for structured parallelism
3. **MPI+OpenMP Hybrid**: Two-level parallelization for distributed systems

## 🚀 Quick Start

### Prerequisites

- **C++17 compatible compiler** (GCC 8+ recommended)
- **OpenMP 4.5+**
- **OpenMPI 3.0+**
- **FastFlow library** (included in `fastflow/` directory)
- **Python 3.6+** (for verification scripts)

### Compilation

#### OpenMP Version
```bash
g++ -std=c++17 -O3 -fopenmp main_openmp.cpp -o openmp_sort
```

#### FastFlow Version
```bash
g++ -std=c++17 -O3 -I./fastflow main_fastflow.cpp -pthread -o fastflow_sort
```

#### MPI+OpenMP Hybrid Version
```bash
mpicxx -std=c++17 -O3 -fopenmp main.cpp -o hybrid_sort
```

### Usage

#### Generate Test Data
```bash
g++ -O3 generate_records.cpp -o generate_records
./generate_records test_1M_64B.bin 1000000 64
```

#### Run Single-Node Versions
```bash
# OpenMP version
./openmp_sort input.bin output_openmp.bin 4

# FastFlow version  
./fastflow_sort input.bin output_fastflow.bin 4
```

#### Run Distributed Version
```bash
# Single node
mpirun -np 1 ./hybrid_sort input.bin output_hybrid.bin 4

# Multiple nodes (cluster)
mpirun -np 8 --map-by node:PE=4 ./hybrid_sort input.bin output_hybrid.bin 4
```

#### Verify Output
```bash
python3 verify_output.py output.bin
```

## 📊 Performance Results

### Single-Node Performance (1M Records, 64B Payloads)

| Implementation | Time (ms) | Threads/Workers | Efficiency |
|---|---|---|---|
| **MPI+OpenMP (1 rank)** | **2,040** | 4 | **Best** |
| **OpenMP** | 3,349 | 4 | Good |
| **FastFlow** | 4,364 | 4 | Stable |

### Multi-Node Scalability (1M Records, 64B Payloads)

| MPI Ranks | Time (ms) | Speedup | Efficiency |
|---|---|---|---|
| 1 | 2,040 | 1.00× | 100% |
| 2 | 2,463 | 0.83× | 41.6% |
| 4 | 2,431 | 0.84× | 21.0% |
| 8 | 2,437 | 0.84× | 10.5% |

**Note**: Multi-node performance is limited by communication overhead for datasets of this size. Optimal performance achieved with single-node configuration.

### Large Payload Performance (1M Records, 1024B Payloads)

| Implementation | Time (ms) | Memory Usage |
|---|---|---|
| OpenMP | 9,233 | ~1.2GB |
| MPI+OpenMP | 9,715 | ~1.2GB |

## 🔬 Technical Implementation Details

### Memory Management
- **RAII-based RecordPtr**: Automatic memory management with smart pointers
- **Chunked Processing**: Memory-bounded processing for out-of-core operations
- **NUMA-Aware Allocation**: Optimized for multi-socket systems

### Parallel Algorithms
- **OpenMP**: Task-based recursive mergesort with dynamic load balancing
- **FastFlow**: Farm pattern for sorting, pipeline pattern for merging
- **MPI**: Distributed sorting with careful record boundary alignment

### Key Optimizations
- **Record Boundary Detection**: Prevents data corruption in distributed processing
- **Cache-Efficient Merging**: Blocked algorithms for optimal cache utilization
- **Threshold-Based Task Creation**: Minimizes parallelization overhead
- **Stable Sorting**: Ensures consistent output across implementations

## 🗂️ Project Structure

```
SPM_P1/
├── README.md                   # This file
├── main.cpp                    # MPI+OpenMP hybrid main
├── main_openmp.cpp            # OpenMP version main
├── main_fastflow.cpp          # FastFlow version main
├── record_structure.hpp       # Core record definitions
├── mpi_openmp_sort.hpp        # MPI+OpenMP implementation
├── omp_mergesort.hpp          # OpenMP implementation
├── fastflow_sort.hpp          # FastFlow implementation
├── openmp_sort.hpp            # OpenMP utilities
├── generate_records.cpp       # Test data generator
├── verify_output.py           # Output verification script
├── verify_sort.cpp            # C++ verification utility
├── test_mpi_fixes.cpp         # MPI testing utilities
├── debug_mpi_test.cpp         # MPI debugging tools
├── hybrid_sort_main.cpp       # Alternative hybrid main
├── hybrid_sort_main_base.cpp  # Base hybrid implementation
└── fastflow/                  # FastFlow library directory
```

## 🧪 Testing and Verification

### Automated Testing
```bash
# Generate test data
./generate_records test_data/test1M_64B.bin 1000000 64
./generate_records test_data/test1M_1024B.bin 1000000 1024

# Run all implementations
./openmp_sort test_data/test1M_64B.bin output_omp.bin 4
./fastflow_sort test_data/test1M_64B.bin output_ff.bin 4
mpirun -np 1 ./hybrid_sort test_data/test1M_64B.bin output_hybrid.bin 4

# Verify outputs
python3 verify_output.py output_omp.bin
python3 verify_output.py output_ff.bin
python3 verify_output.py output_hybrid.bin

# Compare implementations (should be identical)
cmp output_omp.bin output_ff.bin
cmp output_omp.bin output_hybrid.bin
```

### Cluster Testing (SLURM)
```bash
# Example SLURM job script
#!/bin/bash
#SBATCH --nodes=8
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --time=00:30:00

module load openmpi gcc

mpirun ./hybrid_sort large_dataset.bin sorted_output.bin 4
```

## 📈 Performance Analysis

### Bottleneck Analysis
1. **Communication Overhead**: Dominates for small datasets in distributed settings
2. **Memory Bandwidth**: Limiting factor for large payloads (1024B+)
3. **Final Merge Phase**: Sequential bottleneck at master rank
4. **I/O Throughput**: Disk bandwidth limitations for very large files

### Optimization Strategies
- **Single-Node Preference**: Use single-node MPI for datasets < 10M records
- **Payload Size Tuning**: Balance between memory usage and cache efficiency
- **Thread Configuration**: Optimal thread count varies by hardware topology
- **Chunk Size Optimization**: Tune chunk sizes based on available memory

## 🔮 Future Enhancements

- [ ] **Parallel I/O**: MPI-IO implementation for distributed file access
- [ ] **Dynamic Load Balancing**: Adaptive work distribution for heterogeneous systems
- [ ] **Compression Support**: On-the-fly compression for large payloads
- [ ] **Fault Tolerance**: Checkpointing and recovery mechanisms
- [ ] **GPU Acceleration**: CUDA/OpenCL support for hybrid CPU-GPU sorting
- [ ] **Stream Processing**: Real-time sorting for streaming data

## 📄 Academic Context

This implementation was developed as part of the **Structured Parallel Programming Models (SPM)** course at the **University of Pisa** under the supervision of **Prof. Massimo Torquati**.

### Research Contributions
- Comparative analysis of parallel programming paradigms for external sorting
- Performance evaluation on distributed HPC systems
- Out-of-core algorithm optimization for memory-constrained environments
- Scalability analysis across multiple parallel programming models

## 📋 Citation

```bibtex
@misc{tagemouati2025mergesort,
  title={Distributed Out-of-Core MergeSort: A Comparative Study of OpenMP, FastFlow, and MPI Implementations},
  author={Tagemouati, Salim},
  year={2025},
  institution={University of Pisa},
  note={SPM Course Project}
}
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit pull requests, report bugs, or suggest improvements.

### Development Guidelines
- Follow C++17 standards
- Include comprehensive tests for new features
- Maintain backward compatibility
- Document performance implications

## 📞 Contact

**Salim Tagemouati**  
University of Pisa  
📧 [s.tagemouati@studenti.unipi.it](mailto:s.tagemouati@studenti.unipi.it)

## 📜 License

This project is available under the MIT License. See the LICENSE file for details.

---

⭐ **If this project helped you, please consider giving it a star!** ⭐
