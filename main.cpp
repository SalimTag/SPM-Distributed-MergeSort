#include <iostream>
#include <string>
#include <stdexcept>
#include "mpi_openmp_sort.hpp"

int main(int argc, char* argv[]) {
    if (argc != 4) {
        std::cerr << "Usage: " << argv[0] << " <input_file> <output_file> <threads_per_process>\n";
        return 1;
    }

    int provided;
    MPI_Init_thread(&argc, &argv, MPI_THREAD_FUNNELED, &provided);

    int rank;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);

    try {
        {  // Scope for HybridOpenMPSort
            int num_threads = std::stoi(argv[3]);
            HybridOpenMPSort sorter(num_threads);
            sorter.sort(argv[1], argv[2]);
        }  // sorter is destroyed here, before MPI_Finalize

        // Sync point before finalizing
        MPI_Barrier(MPI_COMM_WORLD);
    } catch (const std::exception& e) {
        std::cerr << "Rank " << rank << " Error: " << e.what() << std::endl;
        MPI_Abort(MPI_COMM_WORLD, 1);
        return 1;
    }

    MPI_Finalize();
    return 0;
}
