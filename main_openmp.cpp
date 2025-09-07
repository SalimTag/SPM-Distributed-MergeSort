#include "omp_mergesort.hpp"
#include <iostream>
#include <string>

void print_usage() {
    std::cout << "Usage: ./openmp_sort <input_file> <output_file> <num_threads>" << std::endl;
    std::cout << "  <input_file>: Path to input file to sort" << std::endl;
    std::cout << "  <output_file>: Path to output file for sorted data" << std::endl;
    std::cout << "  <num_threads>: Number of OpenMP threads to use" << std::endl;
}

int main(int argc, char* argv[]) {
    if (argc < 4) {
        std::cerr << "Error: Insufficient arguments" << std::endl;
        print_usage();
        return 1;
    }

    std::string input_file = argv[1];
    std::string output_file = argv[2];
    unsigned num_threads = std::stoi(argv[3]);

    try {
        // Create and run the OpenMP sorter
        OpenMPMergeSort sorter(num_threads);
        
        auto start_time = std::chrono::high_resolution_clock::now();
        
        sorter.sort(input_file, output_file);
        
        auto end_time = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
        
        std::cout << "OpenMP sorting completed in " << duration.count() << " ms" << std::endl;
        std::cout << "Used " << num_threads << " threads" << std::endl;
        
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}