# Changelog

All notable changes to the Distributed Out-of-Core MergeSort project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-06-05

### Added

#### Core Implementations
- OpenMP Task-Based Implementation: Recursive divide-and-conquer with dynamic load balancing
- FastFlow Pattern-Based Implementation: Farm and pipeline patterns for structured parallelism  
- MPI+OpenMP Hybrid Implementation: Two-level parallelization for distributed systems

#### Data Handling
- Variable Record Support: Handles records with 8-4096 byte payloads
- Out-of-Core Processing: Memory-bounded chunked processing for large datasets
- RAII Memory Management: Smart pointer-based automatic memory management
- Record Boundary Detection: Safe partitioning for distributed processing

#### Testing and Verification  
- Comprehensive Output Verification: Python-based verification with sorting validation
- Cross-Implementation Validation: Bitwise-identical output verification
- Performance Benchmarking: Automated timing and scalability testing
- Test Data Generation: Configurable record generator for various payload sizes

#### Development Infrastructure
- Comprehensive Makefile: Multi-target build system with testing integration
- Automated Build Script: Complete build, test, and benchmark automation
- SLURM Integration: Cluster job script generation for HPC environments
- Documentation: Detailed README with usage examples and performance analysis

### Performance Results

#### Single-Node Performance (1M Records, 64B Payloads)
- MPI+OpenMP (1 rank): 2,040ms (Best performance)
- OpenMP: 3,349ms (Good shared-memory performance)  
- FastFlow: 4,364ms (Stable pattern-based performance)

#### Multi-Node Analysis (1M Records, 64B Payloads)
- 1 MPI Rank: 2,040ms baseline
- 2-8 MPI Ranks: 2,431-2,463ms (Communication overhead dominates)
- Key Finding: Single-node optimal for datasets of this size

#### Large Payload Performance (1M Records, 1024B Payloads)  
- OpenMP: 9,233ms (Memory bandwidth impact)
- MPI+OpenMP: 9,715ms (Consistent scaling behavior)

### Technical Contributions

#### Algorithm Optimizations
- Cache-Efficient Merging: Blocked algorithms for optimal cache utilization
- Threshold-Based Task Creation: Minimizes parallelization overhead for small arrays
- NUMA-Aware Processing: Memory allocation optimized for multi-socket systems
- Stable Sorting: Consistent output across all implementations

#### Distributed Computing
- Record Boundary Alignment: Prevents data corruption in distributed processing  
- Communication Overhead Analysis: Detailed bottleneck identification
- Load Balancing: Dynamic work distribution strategies
- Fault-Tolerant I/O: Robust file handling with error recovery

### Known Limitations

- Small Dataset Overhead: Communication costs exceed benefits for datasets < 10M records
- Memory Bandwidth: Large payloads limited by memory subsystem performance
- Sequential Merge Bottleneck: Final merge phase not fully parallelized
- MPI Startup Cost: Fixed overhead impacts small to medium datasets

### Future Enhancements

#### Planned Features
- Parallel I/O: MPI-IO implementation for distributed file access
- Dynamic Load Balancing: Runtime work redistribution
- Compression Support: On-the-fly payload compression
- GPU Acceleration: CUDA/OpenCL hybrid processing
- Fault Tolerance: Checkpointing and recovery mechanisms

#### Research Directions
- Stream Processing: Real-time sorting for streaming data
- Heterogeneous Computing: CPU-GPU-FPGA hybrid algorithms
- Network-Aware Optimization: Topology-aware communication patterns
- Energy Efficiency: Power-aware algorithm selection

### Build System

#### Supported Targets
- `make all` - Build all implementations
- `make test-basic` - Run functionality verification
- `make benchmark` - Performance evaluation  
- `make prepare-cluster` - HPC deployment preparation

#### Dependencies
- C++17 compatible compiler (GCC 8+ recommended)
- OpenMP 4.5+ for shared-memory parallelism
- OpenMPI 3.0+ for distributed computing
- Python 3.6+ for verification scripts
- FastFlow library (included)

### Academic Context

This implementation was developed as part of the Structured Parallel Programming Models (SPM) course at the University of Pisa under Prof. Massimo Torquati.

#### Research Contributions
- Comparative Parallel Programming Analysis: Systematic evaluation of OpenMP, FastFlow, and MPI approaches
- Out-of-Core Algorithm Optimization: Memory-efficient processing for constrained environments  
- Distributed System Performance Analysis: Scalability characterization on HPC clusters
- Pattern-Based Programming Evaluation: FastFlow structured patterns for computational problems

### Verification and Testing

#### Output Validation
- Sorting Correctness: All implementations produce correctly sorted output
- Cross-Implementation Consistency: Bitwise-identical results verified
- Large Dataset Handling: Tested with datasets exceeding available RAM
- Edge Case Robustness: Various payload sizes and record counts validated

#### Performance Validation  
- Single-Node Efficiency: Optimal resource utilization measured
- Multi-Node Scaling: Communication overhead quantified
- Memory Usage: Out-of-core processing verified under memory constraints
- Thread Scaling: OpenMP performance characterized across thread counts

---

For detailed technical information, see [README.md](README.md).  
For build instructions, see the included [Makefile](Makefile).  
For automated testing, use [build_and_test.sh](build_and_test.sh).
