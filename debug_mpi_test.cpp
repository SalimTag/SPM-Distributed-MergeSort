// Debug test for MPI+OpenMP with detailed logging
#include <iostream>
#include <fstream>
#include <vector>
#include <random>
#include <mpi.h>
#include "record_structure.hpp"

// Generate minimal test data
void generateTestData(const std::string& filename, size_t num_records) {
    std::ofstream file(filename, std::ios::binary);
    if (!file) {
        throw std::runtime_error("Cannot create test file: " + filename);
    }
    
    std::random_device rd;
    std::mt19937 gen(42); // Fixed seed for reproducibility
    std::uniform_int_distribution<uint64_t> key_dist(1, 1000);
    std::uniform_int_distribution<uint32_t> len_dist(PAYLOAD_MIN, PAYLOAD_MIN + 10); // Small payloads
    
    for (size_t i = 0; i < num_records; ++i) {
        uint64_t key = key_dist(gen);
        uint32_t len = len_dist(gen);
        
        // Write header
        file.write(reinterpret_cast<const char*>(&key), sizeof(uint64_t));
        file.write(reinterpret_cast<const char*>(&len), sizeof(uint32_t));
        
        // Write payload
        for (uint32_t j = 0; j < len; ++j) {
            char c = 'A' + (j % 26);
            file.write(&c, 1);
        }
    }
    
    file.close();
    std::cout << "Rank 0: Generated " << num_records << " test records" << std::endl;
}

int main(int argc, char* argv[]) {
    int provided;
    MPI_Init_thread(&argc, &argv, MPI_THREAD_FUNNELED, &provided);
    
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    
    std::cout << "Rank " << rank << "/" << size << " started" << std::endl;
    
    try {
        const size_t num_records = 100;  // Very small test
        const std::string input_file = "debug_input.bin";
        
        if (rank == 0) {
            std::cout << "=== Debug MPI Test ===" << std::endl;
            generateTestData(input_file, num_records);
        }
        
        std::cout << "Rank " << rank << " reaching first barrier" << std::endl;
        MPI_Barrier(MPI_COMM_WORLD);
        std::cout << "Rank " << rank << " passed first barrier" << std::endl;
        
        // Test simple broadcast
        uint64_t test_value = 0;
        if (rank == 0) {
            test_value = 12345;
            std::cout << "Rank 0: Broadcasting value " << test_value << std::endl;
        }
        
        MPI_Bcast(&test_value, 1, MPI_UINT64_T, 0, MPI_COMM_WORLD);
        std::cout << "Rank " << rank << " received broadcast value: " << test_value << std::endl;
        
        std::cout << "Rank " << rank << " reaching final barrier" << std::endl;
        MPI_Barrier(MPI_COMM_WORLD);
        std::cout << "Rank " << rank << " passed final barrier" << std::endl;
        
        if (rank == 0) {
            std::cout << " Debug test completed successfully!" << std::endl;
            std::remove(input_file.c_str());
        }
        
    } catch (const std::exception& e) {
        std::cerr << "Rank " << rank << " Error: " << e.what() << std::endl;
        MPI_Abort(MPI_COMM_WORLD, 1);
    }
    
    std::cout << "Rank " << rank << " calling MPI_Finalize" << std::endl;
    MPI_Finalize();
    std::cout << "Rank " << rank << " finished" << std::endl;
    return 0;
}
