#ifndef MPI_OPENMP_SORT_HPP
#define MPI_OPENMP_SORT_HPP

#include "record_structure.hpp"  // Include this first for constants
#include "omp_mergesort.hpp"
#include "openmp_sort.hpp"
#include <mpi.h>
#include <vector>
#include <string>
#include <fstream>
#include <iostream>
#include <filesystem>
#include <numeric>
#include <algorithm>
#include <cmath>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <cstdlib>
#include <stdexcept>
#include <omp.h>
#include <cstring>  // For memcpy

namespace fs = std::filesystem;

// Large file threshold for scatter vs broadcast (100M records)
constexpr uint64_t LARGE_FILE_THRESHOLD = 100000000ULL;

// Record view for efficient sorting without copying payloads
struct RecordView {
    uint64_t key;
    const char* payload;  // points into mmap buffer
    uint32_t len;
    
    RecordView(uint64_t k, const char* p, uint32_t l) : key(k), payload(p), len(l) {}
    
    bool operator<(const RecordView& other) const {
        return key < other.key;
    }
};

class HybridOpenMPSort {
private:
    int world_size_;
    int rank_;
    OpenMPMergeSort omp_sorter_;
    std::string temp_dir_;
    int file_id_;
    static constexpr size_t MAX_BUFFER_SIZE = 128 * 1024 * 1024; // Increased to 128MB
    
    // Record boundary handling
    std::vector<uint64_t> record_offsets_;
    uint64_t total_records_;

    // Parallel quicksort for record views
    void parallelQuickSort(std::vector<RecordView>& arr, size_t low, size_t high) {
        if (low < high) {
            size_t pi = partition(arr, low, high);
            
            const size_t threshold = 10000;  // Switch to sequential below this size
            if ((pi - low > threshold) && (high - pi > threshold)) {
                #pragma omp task shared(arr) if(pi - low > threshold)
                parallelQuickSort(arr, low, pi - 1);
                
                #pragma omp task shared(arr) if(high - pi > threshold)
                parallelQuickSort(arr, pi + 1, high);
                
                #pragma omp taskwait
            } else {
                // Sequential sort for small partitions
                if (pi > low) {
                    std::sort(arr.begin() + low, arr.begin() + pi);
                }
                if (pi < high) {
                    std::sort(arr.begin() + pi + 1, arr.begin() + high + 1);
                }
            }
        }
    }

    size_t partition(std::vector<RecordView>& arr, size_t low, size_t high) {
        uint64_t pivot = arr[high].key;
        size_t i = low;
        
        for (size_t j = low; j < high; j++) {
            if (arr[j].key < pivot) {
                std::swap(arr[i], arr[j]);
                i++;
            }
        }
        std::swap(arr[i], arr[high]);
        return i;
    }

    std::string getNextTempFileName() {
        return temp_dir_ + "/chunk_" + std::to_string(rank_) + "_" + std::to_string(file_id_++) + ".tmp";
    }

    // Scan file to find record boundaries - only done by rank 0
    void scanRecordBoundaries(const std::string& input_file) {
        if (rank_ != 0) return;
        
        std::ifstream file(input_file, std::ios::binary | std::ios::ate);
        if (!file) {
            throw std::runtime_error("Cannot open input file for boundary scan: " + input_file);
        }
        
        uint64_t file_size = file.tellg();
        file.seekg(0);
        
        record_offsets_.clear();
        record_offsets_.push_back(0); // First record starts at offset 0
        
        uint64_t offset = 0;
        while (offset < file_size) {
            file.seekg(offset);
            
            // Read record header
            uint64_t key;
            uint32_t len;
            
            if (!file.read(reinterpret_cast<char*>(&key), sizeof(uint64_t)) ||
                !file.read(reinterpret_cast<char*>(&len), sizeof(uint32_t))) {
                break; // End of file or corrupted
            }
            
            // Validate payload length
            if (len < PAYLOAD_MIN || len > PAYLOAD_MAX) {
                std::cerr << "Invalid payload length " << len << " at offset " << offset << std::endl;
                break;
            }
            
            // Move to next record
            offset += HEADER_SIZE + len;
            if (offset < file_size) {
                record_offsets_.push_back(offset);
            }
        }
        
        total_records_ = record_offsets_.size();
        std::cout << "Rank 0: Found " << total_records_ << " records in file" << std::endl;
    }

    // Broadcast or scatter record boundaries to all ranks
    void broadcastRecordBoundaries() {
        // First broadcast the number of records
        MPI_Bcast(&total_records_, 1, MPI_UINT64_T, 0, MPI_COMM_WORLD);
        
        if (total_records_ > LARGE_FILE_THRESHOLD) {
            // For very large files, use scatter to distribute only relevant boundaries
            scatterRecordBoundaries();
        } else {
            // For smaller files, broadcast entire offset vector
            if (rank_ != 0) {
                record_offsets_.resize(total_records_);
            }
            MPI_Bcast(record_offsets_.data(), total_records_, MPI_UINT64_T, 0, MPI_COMM_WORLD);
        }
    }

    // Scatter boundaries for large files to reduce memory usage
    void scatterRecordBoundaries() {
        // Calculate how many records each rank will get
        std::vector<int> send_counts(world_size_);
        std::vector<int> displacements(world_size_);
        
        for (int i = 0; i < world_size_; ++i) {
            uint64_t records_per_rank = total_records_ / world_size_;
            uint64_t remainder = total_records_ % world_size_;
            uint64_t start_record = i * records_per_rank + std::min(static_cast<uint64_t>(i), remainder);
            uint64_t end_record = start_record + records_per_rank + (i < remainder ? 1 : 0);
            
            // Each rank needs start and end boundaries
            send_counts[i] = 2;  // start_offset and end_offset
            displacements[i] = i * 2;
        }
        
        std::vector<uint64_t> scattered_boundaries(2);  // [start_offset, end_offset]
        
        if (rank_ == 0) {
            // Prepare boundaries for all ranks
            std::vector<uint64_t> all_boundaries(world_size_ * 2);
            for (int i = 0; i < world_size_; ++i) {
                uint64_t records_per_rank = total_records_ / world_size_;
                uint64_t remainder = total_records_ % world_size_;
                uint64_t start_record = i * records_per_rank + std::min(static_cast<uint64_t>(i), remainder);
                uint64_t end_record = start_record + records_per_rank + (i < remainder ? 1 : 0);
                
                all_boundaries[i * 2] = record_offsets_[start_record];
                all_boundaries[i * 2 + 1] = (end_record < total_records_) ? record_offsets_[end_record] : UINT64_MAX;
            }
            
            MPI_Scatterv(all_boundaries.data(), send_counts.data(), displacements.data(), MPI_UINT64_T,
                        scattered_boundaries.data(), 2, MPI_UINT64_T, 0, MPI_COMM_WORLD);
        } else {
            MPI_Scatterv(nullptr, nullptr, nullptr, MPI_UINT64_T,
                        scattered_boundaries.data(), 2, MPI_UINT64_T, 0, MPI_COMM_WORLD);
        }
        
        // Store only the boundaries we need
        record_offsets_.clear();
        record_offsets_.push_back(scattered_boundaries[0]);  // start
        if (scattered_boundaries[1] != UINT64_MAX) {
            record_offsets_.push_back(scattered_boundaries[1]);  // end
        }
    }

    // Calculate record-aligned chunk boundaries for each rank
    std::pair<uint64_t, uint64_t> getRecordAlignedChunk() {
        if (total_records_ > LARGE_FILE_THRESHOLD) {
            // For large files, boundaries were scattered
            uint64_t start_offset = record_offsets_[0];
            uint64_t end_offset = (record_offsets_.size() > 1) ? record_offsets_[1] : UINT64_MAX;
            return {start_offset, end_offset};
        } else {
            // For smaller files, calculate from full offset vector
            uint64_t records_per_rank = total_records_ / world_size_;
            uint64_t remainder = total_records_ % world_size_;
            
            uint64_t start_record = rank_ * records_per_rank + std::min(static_cast<uint64_t>(rank_), remainder);
            uint64_t end_record = start_record + records_per_rank + (rank_ < remainder ? 1 : 0);
            
            uint64_t start_offset = record_offsets_[start_record];
            uint64_t end_offset = (end_record < total_records_) ? record_offsets_[end_record] : UINT64_MAX;
            
            return {start_offset, end_offset};
        }
    }

    // Memory-mapped file processing with record view indexing
    void sortChunkWithMmap(const std::string& input_file, uint64_t start_offset, 
                          uint64_t end_offset, const std::string& output_file) {
        // Open file for memory mapping
        int fd = open(input_file.c_str(), O_RDONLY);
        if (fd == -1) {
            throw std::runtime_error("Cannot open file for mmap: " + input_file);
        }
        
        // Get actual file size for mmap
        struct stat file_stat;
        if (fstat(fd, &file_stat) == -1) {
            close(fd);
            throw std::runtime_error("Cannot stat file: " + input_file);
        }
        
        // Map the entire file read-only
        const char* mapped_data = static_cast<const char*>(
            mmap(nullptr, file_stat.st_size, PROT_READ, MAP_PRIVATE, fd, 0));
        
        if (mapped_data == MAP_FAILED) {
            close(fd);
            throw std::runtime_error("Memory mapping failed for: " + input_file);
        }
        
        // Advise kernel about access pattern
        madvise(const_cast<char*>(mapped_data), file_stat.st_size, MADV_SEQUENTIAL);
        
        // Build record index for our chunk
        std::vector<RecordView> record_index;
        uint64_t current_offset = start_offset;
        
        while (current_offset < end_offset && current_offset < static_cast<uint64_t>(file_stat.st_size)) {
            // Read record header from mapped memory with alignment handling
            const char* record_start = mapped_data + current_offset;
            
            if (current_offset + HEADER_SIZE > static_cast<uint64_t>(file_stat.st_size)) {
                break; // Not enough space for header
            }
            
            // Use memcpy for unaligned loads to avoid UB
            uint64_t key;
            uint32_t len;
            std::memcpy(&key, record_start, sizeof(uint64_t));
            std::memcpy(&len, record_start + sizeof(uint64_t), sizeof(uint32_t));
            
            // Validate payload length
            if (len < PAYLOAD_MIN || len > PAYLOAD_MAX) {
                std::cerr << "Rank " << rank_ << ": Invalid payload length " << len 
                         << " at offset " << current_offset << std::endl;
                break;
            }
            
            if (current_offset + HEADER_SIZE + len > static_cast<uint64_t>(file_stat.st_size)) {
                break; // Not enough space for payload
            }
            
            // Add to index (payload points directly into mapped memory)
            const char* payload_start = record_start + HEADER_SIZE;
            record_index.emplace_back(key, payload_start, len);
            
            current_offset += HEADER_SIZE + len;
        }
        
        std::cout << "Rank " << rank_ << ": Indexed " << record_index.size() 
                 << " records from offset " << start_offset << " to " << current_offset << std::endl;
        
        // Parallel sort by key using OpenMP
        if (record_index.size() > 1000) {
            // Use OpenMP parallel sort for larger datasets
            const size_t num_threads = omp_get_max_threads();
            if (num_threads > 1 && record_index.size() > num_threads * 100) {
                // Parallel quicksort implementation
                #pragma omp parallel
                {
                    #pragma omp single nowait
                    {
                        parallelQuickSort(record_index, 0, record_index.size() - 1);
                    }
                }
            } else {
                std::sort(record_index.begin(), record_index.end());
            }
        } else {
            // Sequential sort for small datasets
            std::sort(record_index.begin(), record_index.end());
        }
        
        // Write sorted records to output file
        std::ofstream out(output_file, std::ios::binary);
        if (!out) {
            munmap(const_cast<char*>(mapped_data), file_stat.st_size);
            close(fd);
            throw std::runtime_error("Cannot create output file: " + output_file);
        }
        
        for (const auto& record : record_index) {
            // Write header
            out.write(reinterpret_cast<const char*>(&record.key), sizeof(uint64_t));
            out.write(reinterpret_cast<const char*>(&record.len), sizeof(uint32_t));
            // Write payload
            out.write(record.payload, record.len);
        }
        
        // Cleanup
        munmap(const_cast<char*>(mapped_data), file_stat.st_size);
        close(fd);
        
        // Flush output and close
        out.flush();
        out.close();
    }

    // Improved large file transfer with proper MPI datatypes
    void sendLargeFile(const std::string& file_path, int dest_rank) {
        std::ifstream inFile(file_path, std::ios::binary | std::ios::ate);
        if (!inFile) {
            uint64_t size = 0;
            MPI_Send(&size, 1, MPI_UINT64_T, dest_rank, 0, MPI_COMM_WORLD);
            return;
        }

        uint64_t file_size = inFile.tellg();
        inFile.seekg(0, std::ios::beg);

        // Send file size using portable MPI datatype
        MPI_Send(&file_size, 1, MPI_UINT64_T, dest_rank, 0, MPI_COMM_WORLD);

        if (file_size > 0) {
            std::vector<char> buffer(std::min(MAX_BUFFER_SIZE, static_cast<size_t>(file_size)));
            uint64_t remaining = file_size;

            while (remaining > 0) {
                size_t chunk_size = std::min(buffer.size(), static_cast<size_t>(remaining));
                inFile.read(buffer.data(), chunk_size);
                
                // Use non-blocking send to avoid potential deadlocks
                MPI_Request request;
                MPI_Isend(buffer.data(), chunk_size, MPI_BYTE, dest_rank, 1, MPI_COMM_WORLD, &request);
                MPI_Wait(&request, MPI_STATUS_IGNORE);
                
                remaining -= chunk_size;
            }
        }
        inFile.close();
    }

    void receiveLargeFile(int source_rank, std::ofstream& outFile) {
        uint64_t file_size = 0;
        MPI_Status status;
        
        // Receive file size using portable MPI datatype
        MPI_Recv(&file_size, 1, MPI_UINT64_T, source_rank, 0, MPI_COMM_WORLD, &status);

        if (file_size > 0) {
            std::vector<char> buffer(std::min(MAX_BUFFER_SIZE, static_cast<size_t>(file_size)));
            uint64_t remaining = file_size;

            while (remaining > 0) {
                size_t chunk_size = std::min(buffer.size(), static_cast<size_t>(remaining));
                MPI_Recv(buffer.data(), chunk_size, MPI_BYTE, source_rank, 1, MPI_COMM_WORLD, &status);
                outFile.write(buffer.data(), chunk_size);
                remaining -= chunk_size;
            }
        }
    }
    // Tree-based merge to reduce root bottleneck with fixed barrier logic
    void treeMerge(const std::string& local_sorted_file, const std::string& final_output) {
        // Simple binary tree merge - can be extended to k-ary tree
        int step = 1;
        std::string current_file = local_sorted_file;
        bool active = true;  // Track if this rank is still participating
        
        while (step < world_size_) {
            if (active && rank_ % (2 * step) == 0) {
                int partner = rank_ + step;
                if (partner < world_size_) {
                    // Receive partner's sorted data
                    std::string received_file = getNextTempFileName();
                    std::ofstream temp_out(received_file, std::ios::binary);
                    receiveLargeFile(partner, temp_out);
                    temp_out.close();
                    
                    // Merge current file with received file
                    std::string merged_file = getNextTempFileName();
                    std::vector<std::string> files_to_merge = {current_file, received_file};
                    omp_sorter_.kWayMerge(files_to_merge, merged_file);
                    
                    // Clean up old files
                    if (current_file != local_sorted_file) {
                        fs::remove(current_file);
                    }
                    fs::remove(received_file);
                    
                    current_file = merged_file;
                }
            } else if (active && rank_ % step == 0) {
                // Send our data to our partner
                int partner = rank_ - step;
                sendLargeFile(current_file, partner);
                active = false;  // This rank is done participating
            }
            step *= 2; 
            // Only active ranks participate in barrier
            // Use a global barrier to ensure all ranks synchronize
            MPI_Barrier(MPI_COMM_WORLD);
        }
        
        // Rank 0 has the final result
        if (rank_ == 0) {
            if (current_file != final_output) {
                // Move final result to output location
                fs::copy_file(current_file, final_output, fs::copy_options::overwrite_existing);
                if (current_file != local_sorted_file) {
                    fs::remove(current_file);
                }
            }
        }
        
        // Clean up local sorted file (all ranks can do this)
        if (rank_ != 0 || current_file == local_sorted_file) {
            if (fs::exists(local_sorted_file)) {
                fs::remove(local_sorted_file);
            }
        }
    }

public:
    HybridOpenMPSort(int threads)
        : omp_sorter_(threads), file_id_(0), total_records_(0)
    {
        MPI_Comm_size(MPI_COMM_WORLD, &world_size_);
        MPI_Comm_rank(MPI_COMM_WORLD, &rank_);
        
        // Create unique temp directory for this rank (configurable via TMPDIR)
        const char* tmpdir = std::getenv("TMPDIR");
        std::string base_dir = tmpdir ? tmpdir : ".";
        temp_dir_ = base_dir + "/mpi_tmp_" + std::to_string(rank_);
        fs::create_directories(temp_dir_);
        
        // Set OpenMP thread affinity for NUMA locality
        if (std::getenv("OMP_PROC_BIND") == nullptr) {
            // Use environment variable since omp_set_proc_bind may not be available
            setenv("OMP_PROC_BIND", "close", 0);
            setenv("OMP_PLACES", "cores", 0);
        }
    }

    ~HybridOpenMPSort() {
        try {
            fs::remove_all(temp_dir_);
        } catch (const std::exception& e) {
            std::cerr << "Error cleaning up temporary directory: " << e.what() << std::endl;
        }
    }

    void sort(const std::string& input_file, const std::string& output_file) {
        Timer timer("MPI + OpenMP total sort time");
        
        try {
            // Phase 1: Record boundary detection (rank 0 only)
            scanRecordBoundaries(input_file);
            
            // Phase 2: Broadcast boundaries to all ranks
            broadcastRecordBoundaries();
            
            // Phase 3: Calculate record-aligned chunk for this rank
            auto [start_offset, end_offset] = getRecordAlignedChunk();
            
            std::cout << "Rank " << rank_ << " processing record-aligned chunk: bytes " 
                     << start_offset << " to " << end_offset << std::endl;
            
            // Phase 4: Sort local chunk using memory mapping and record views
            std::string sorted_local = getNextTempFileName();
            sortChunkWithMmap(input_file, start_offset, end_offset, sorted_local);
            
            // Sync point after local sorting
            MPI_Barrier(MPI_COMM_WORLD);
            
            // Phase 5: Tree-based merge to avoid root bottleneck
            treeMerge(sorted_local, output_file);
            
            if (rank_ == 0) {
                std::cout << "MPI+OpenMP sort completed successfully with " 
                         << world_size_ << " processes" << std::endl;
            }
            
        } catch (const std::exception& e) {
            std::cerr << "Rank " << rank_ << " error: " << e.what() << std::endl;
            MPI_Abort(MPI_COMM_WORLD, 1);
        }
        
        // Final sync to ensure all processes complete
        MPI_Barrier(MPI_COMM_WORLD);
    }
};

#endif // MPI_OPENMP_SORT_HPP
