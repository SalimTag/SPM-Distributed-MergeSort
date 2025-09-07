// Main program for MPI+OpenMP hybrid sort
#include <iostream>
#include <fstream>
#include <vector>
#include <random>
#include <mpi.h>
#include "record_structure.hpp"
#include "mpi_openmp_sort.hpp"

// Generate test data with variable-length records
void generateTestData(const std::string& filename, size_t num_records) {
    std::ofstream file(filename, std::ios::binary);
    if (!file) {
        throw std::runtime_error("Cannot create test file: " + filename);
    }
    
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<uint64_t> key_dist(1, 1000000);
    std::uniform_int_distribution<uint32_t> len_dist(PAYLOAD_MIN, PAYLOAD_MAX);
    std::uniform_int_distribution<char> payload_dist('A', 'Z');
    
    for (size_t i = 0; i < num_records; ++i) {
        uint64_t key = key_dist(gen);
        uint32_t len = len_dist(gen);
        
        // Write header
        file.write(reinterpret_cast<const char*>(&key), sizeof(uint64_t));
        file.write(reinterpret_cast<const char*>(&len), sizeof(uint32_t));
        
        // Write payload
        for (uint32_t j = 0; j < len; ++j) {
            char c = payload_dist(gen);
            file.write(&c, 1);
        }
    }
    
    file.close();
    std::cout << "Generated " << num_records << " test records in " << filename << std::endl;
}

// Verify that output is correctly sorted
bool verifySort(const std::string& filename) {
    std::ifstream file(filename, std::ios::binary);
    if (!file) {
        std::cerr << "Cannot open file for verification: " << filename << std::endl;
        return false;
    }
    
    uint64_t prev_key = 0;
    size_t record_count = 0;
    
    while (file.peek() != EOF) {
        uint64_t key;
        uint32_t len;
        
        if (!file.read(reinterpret_cast<char*>(&key), sizeof(uint64_t)) ||
            !file.read(reinterpret_cast<char*>(&len), sizeof(uint32_t))) {
            break;
        }
        
        if (len < PAYLOAD_MIN || len > PAYLOAD_MAX) {
            std::cerr << "Invalid payload length: " << len << std::endl;
            return false;
        }
        
        if (record_count > 0 && key < prev_key) {
            std::cerr << "Sort order violation: key " << key << " < " << prev_key << std::endl;
            return false;
        }
        
        // Skip payload
        file.seekg(len, std::ios::cur);
        
        prev_key = key;
        record_count++;
    }
    
    std::cout << "Verification successful: " << record_count << " records in correct order" << std::endl;
    return true;
}

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
            std::cout << "✅ Hybrid sort completed successfully!" << std::endl;
        }
        
    } catch (const std::exception& e) {
        std::cerr << "Rank " << rank << " error: " << e.what() << std::endl;
        MPI_Abort(MPI_COMM_WORLD, 1);
    }
    
    MPI_Finalize();
    return 0;
}
