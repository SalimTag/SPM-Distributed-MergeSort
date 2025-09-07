#include <iostream>
#include <mpi.h>
#include "mpi_openmp_sort.hpp"

int main(int argc, char* argv[]) {
    if (argc != 3) {
        std::cerr << "Usage: " << argv[0] << " <input_file> <output_file>" << std::endl;
        return 1;
    }

    int provided;
    MPI_Init_thread(&argc, &argv, MPI_THREAD_FUNNELED, &provided);
    
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    
    try {
        std::string input_file = argv[1];
        std::string output_file = argv[2];
        
        if (rank == 0) {
            std::cout << "=== MPI+OpenMP Hybrid Sort ===" << std::endl;
            std::cout << "MPI Ranks: " << size << std::endl;
            std::cout << "Input: " << input_file << std::endl;
            std::cout << "Output: " << output_file << std::endl;
        }
        
        // Use fewer OpenMP threads for large MPI jobs to avoid oversubscription
        int num_threads = (size >= 8) ? 2 : (size >= 4) ? 3 : 4;
        
        HybridOpenMPSort sorter(num_threads);
        sorter.sort(input_file, output_file);
        
        if (rank == 0) {
            std::cout << "Hybrid sort completed successfully!" << std::endl;
        }
        
    } catch (const std::exception& e) {
        std::cerr << "Rank " << rank << " error: " << e.what() << std::endl;
        MPI_Abort(MPI_COMM_WORLD, 1);
    }
    
    MPI_Finalize();
    return 0;
}
