#pragma once

#include <mpi.h>
#include <fstream>
#include <vector>
#include <string>
#include <iostream>
#include <sstream>
#include <filesystem>
#include "omp_mergesort.hpp"
#include "record_structure.hpp"

namespace fs = std::filesystem;

class MPIOpenMPSort {
public:
    void sort(const std::string& inputFile, const std::string& outputFile, int threadsPerProcess) {
        int rank, size;
        MPI_Comm_rank(MPI_COMM_WORLD, &rank);
        MPI_Comm_size(MPI_COMM_WORLD, &size);

        if (rank == 0) {
            std::cout << "MPI processes: " << size << ", Threads per process: " << threadsPerProcess << std::endl;
        }

        Timer timer("Distributed Sort");

        std::ifstream in(inputFile, std::ios::binary | std::ios::ate);
        if (!in.is_open()) {
            throw std::runtime_error("Unable to open input file: " + inputFile);
        }

        size_t fileSize = in.tellg();
        in.seekg(0, std::ios::beg);

        size_t chunkSize = fileSize / size;
        size_t start = rank * chunkSize;
        size_t end = (rank == size - 1) ? fileSize : (rank + 1) * chunkSize;

        if (rank > 0) {
            in.seekg(start);
            uint64_t dummyKey;
            uint32_t len;
            in.read(reinterpret_cast<char*>(&dummyKey), sizeof(uint64_t));
            in.read(reinterpret_cast<char*>(&len), sizeof(uint32_t));
            // Skip the payload to get to the start of the next record
            in.seekg(len, std::ios::cur);
            start = in.tellg();
        }

        in.seekg(start);
        std::vector<RecordPtr> localRecords;

        while (in.tellg() < end && in.peek() != EOF) {
            RecordPtr record = readRecord(in);
            if (record.get() == nullptr) break;
            localRecords.push_back(std::move(record));
        }

        in.close();

        OpenMPMergeSort ompSorter(threadsPerProcess);
        ompSorter.sortRecords(localRecords);

        std::string tempFile = "temp_sorted_" + std::to_string(rank) + ".bin";
        std::ofstream tempOut(tempFile, std::ios::binary);
        for (const auto& r : localRecords) {
            writeRecord(tempOut, r);
        }
        tempOut.close();

        MPI_Barrier(MPI_COMM_WORLD);

        if (rank == 0) {
            std::vector<std::string> tempFiles;
            for (int i = 0; i < size; ++i) {
                tempFiles.push_back("temp_sorted_" + std::to_string(i) + ".bin");
            }
            ompSorter.kWayMerge(tempFiles, outputFile);
        }

        MPI_Barrier(MPI_COMM_WORLD);

        fs::remove("temp_sorted_" + std::to_string(rank) + ".bin");
    }
};
