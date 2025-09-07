#include "fastflow_sort.hpp"
#include <iostream>
#include <string>

int main(int argc, char* argv[]) {
    if (argc < 4) {
        std::cerr << "Usage: ./fastflow_sort <input_file> <output_file> <num_threads>" << std::endl;
        return 1;
    }

    std::string input_file = argv[1];
    std::string output_file = argv[2];
    int num_threads = std::stoi(argv[3]);

    try {
        FastFlowMergeSort sorter(num_threads);
        sorter.sort(input_file, output_file);
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
