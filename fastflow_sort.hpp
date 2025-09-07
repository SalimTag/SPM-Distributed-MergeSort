// fastflow_sort.hpp
#ifndef FASTFLOW_SORT_HPP
#define FASTFLOW_SORT_HPP

#include "record_structure.hpp"
#include <ff/ff.hpp>
#include <ff/farm.hpp>
#include <ff/pipeline.hpp>
#include <mutex>
#include <vector>
#include <string>
#include <fstream>
#include <iostream>
#include <algorithm>
#include <queue>
#include <memory>
#include <filesystem>
#include <utility>
#include <cmath>
#include <functional>

namespace fs = std::filesystem;

/**
 * FastFlowMergeSort - Out-of-core parallel merge sort implementation using FastFlow
 */
class FastFlowMergeSort {
private:
    unsigned num_workers_;              // Number of FastFlow workers
    std::string temp_dir_;              // Directory for temporary files
    int file_id_;                       // Counter for generating unique file names
    size_t memory_limit_;               // Memory limit per worker

    /**
     * Generates a unique temporary file name
     * @return Unique temporary file path
     */
    std::string getNextTempFileName() {
        return temp_dir_ + "/chunk_" + std::to_string(file_id_++) + ".tmp";
    }

    /**
     * Sorts records in memory using std::sort
     * @param records Vector of record pointers
     */
    void inMemorySort(std::vector<RecordPtr>& records) {
        Timer timer("In-memory sort");
        std::sort(records.begin(), records.end(), 
                  [](const RecordPtr& a, const RecordPtr& b) {
                      return a.get()->key < b.get()->key;
                  });
    }

    /**
     * FastFlow Emitter for reading and distributing chunks of data to workers
     */
    class ReaderEmitter : public ff::ff_node {
    private:
        std::ifstream& inFile_;
        size_t memory_limit_;
        std::atomic<bool>& eof_reached_;
        std::mutex file_mutex_;

    public:
        ReaderEmitter(std::ifstream& inFile, size_t memory_limit, std::atomic<bool>& eof_reached)
            : inFile_(inFile), memory_limit_(memory_limit), eof_reached_(eof_reached) {}

        void* svc(void*) override {
            if (eof_reached_) {
                return nullptr; // End of stream
            }

            std::vector<RecordPtr>* records = new std::vector<RecordPtr>();
            size_t memory_used = 0;
            bool continue_reading = true;

            while (continue_reading) {
                RecordPtr record;
                bool read_success = false;

                {
                    std::lock_guard<std::mutex> lock(file_mutex_);
                    try {
                        if (!inFile_.eof()) {
                            record = readRecord(inFile_);
                            read_success = record.get() != nullptr;
                        }

                        if (inFile_.eof() || !read_success) {
                            eof_reached_ = true;
                            continue_reading = false;
                        }
                    } catch (const std::exception& e) {
                        if (inFile_.eof()) {
                            eof_reached_ = true;
                            continue_reading = false;
                        } else {
                            std::cerr << "Error reading record: " << e.what() << std::endl;
                            // Try to recover by seeking one byte forward
                            inFile_.clear();
                            inFile_.seekg(1, std::ios::cur);
                        }
                    }
                }

                if (read_success) {
                    size_t record_size = record.size();

                    // Check if adding this record would exceed memory limit
                    if (memory_used + record_size > memory_limit_) {
                        continue_reading = false;
                    } else {
                        records->push_back(std::move(record));
                        memory_used += record_size;
                    }
                }
            }

            // If we have no records but EOF is not reached, try again
            if (records->empty() && !eof_reached_) {
                delete records;
                return GO_ON;
            }

            // If we have no records and EOF is reached, end the stream
            if (records->empty()) {
                delete records;
                return nullptr;
            }

            return records;
        }
    };

    /**
     * FastFlow Worker for sorting chunks of data
     */
    class SorterWorker : public ff::ff_node {
    private:
        std::function<std::string()> getTempFileName_;

    public:
        SorterWorker(std::function<std::string()> getTempFileName) : getTempFileName_(getTempFileName) {}

        void* svc(void* task) override {
            std::vector<RecordPtr>* records = static_cast<std::vector<RecordPtr>*>(task);
            
            // Sort the chunk in memory
            if (!records->empty()) {
                Timer timer("Worker in-memory sort");
                std::sort(records->begin(), records->end(), 
                          [](const RecordPtr& a, const RecordPtr& b) {
                              return a.get()->key < b.get()->key;
                          });
                
                // Write sorted chunk to a temporary file
                std::string chunk_file = getTempFileName_();
                std::ofstream outFile(chunk_file, std::ios::binary);
                
                if (!outFile) {
                    std::cerr << "Cannot create temp file: " << chunk_file << std::endl;
                    delete records;
                    return nullptr;
                }
                
                for (const auto& record : *records) {
                    writeRecord(outFile, record);
                }
                
                outFile.close();
                
                // Return the chunk file name
                delete records;
                return new std::string(chunk_file);
            }
            
            delete records;
            return nullptr;
        }
    };
    /**
     * FastFlow Collector for gathering sorted chunk filenames
     */
    class FilenameCollector : public ff::ff_node {
    private:
        std::vector<std::string>& chunk_files_;

    public:
        FilenameCollector(std::vector<std::string>& chunk_files) : chunk_files_(chunk_files) {}

        void* svc(void* task) override {
            std::string* filename = static_cast<std::string*>(task);
            if (filename) {
                chunk_files_.push_back(*filename);
                delete filename;
            }
            return GO_ON;
        }
    };

    /**
     * Partitions the input file into sorted chunks that fit in memory using FastFlow farm
     * @param input_file Input file path
     * @return Vector of paths to sorted chunk files
     */
    std::vector<std::string> partitionIntoSortedChunks(const std::string& input_file) {
        Timer timer("FastFlow partitioning into sorted chunks");
        
        std::vector<std::string> chunk_files;
        
        // Calculate maximum records per chunk based on memory limit
        size_t avg_record_size = sizeof(Record) + 128; // Assume average payload of 128 bytes initially
        size_t max_records_per_chunk = memory_limit_ / avg_record_size / 2; // Conservative allocation
        
        // Open input file
        std::ifstream inFile(input_file, std::ios::binary);
        if (!inFile) {
            throw std::runtime_error("Cannot open input file: " + input_file);
        }
        
        // Set up FastFlow farm
        std::atomic<bool> eof_reached(false);
        
        // Use a lambda to capture this pointer for getNextTempFileName
        auto getTempFileNameWrapper = [this]() { return this->getNextTempFileName(); };
        
        ReaderEmitter emitter(inFile, memory_limit_, eof_reached);
        FilenameCollector collector(chunk_files);
        
        std::vector<ff::ff_node*> workers;
        for (unsigned i = 0; i < num_workers_; ++i) {
            workers.push_back(new SorterWorker(getTempFileNameWrapper));
        }
        
        ff::ff_farm farm;
        farm.add_emitter(&emitter);
        farm.add_workers(workers);
        farm.add_collector(&collector);
        
        if (farm.run_and_wait_end() < 0) {
            throw std::runtime_error("FastFlow farm execution failed");
        }
        
        // Cleanup workers
        for (auto worker : workers) {
            delete worker;
        }
        
        inFile.close();
        return chunk_files;
    }

    /**
     * Merge k sorted files using a priority queue
     * @param input_files Vector of paths to sorted input files
     * @param output_file Path to the output file to write merged results
     */
    void kWayMerge(const std::vector<std::string>& input_files, const std::string& output_file) {
        if (input_files.empty()) {
            std::ofstream empty_out(output_file, std::ios::binary);
            return;
        }
        
        if (input_files.size() == 1) {
            // If only one file, just copy it
            fs::copy_file(input_files[0], output_file, fs::copy_options::overwrite_existing);
            return;
        }
        
        Timer timer("K-way merge of " + std::to_string(input_files.size()) + " files");
        
        // Structure to keep track of records from different files
 struct FileRecord {
    RecordPtr record;
    size_t file_index;

    // Constructor for inserting into the priority queue
    FileRecord(RecordPtr rec, size_t idx) : record(std::move(rec)), file_index(idx) {}

    bool operator>(const FileRecord& other) const {
        return record.get()->key > other.record.get()->key;
    }

    FileRecord(const FileRecord&) = default;
    FileRecord(FileRecord&&) = default;
    FileRecord& operator=(const FileRecord&) = default;
    FileRecord& operator=(FileRecord&&) = default;
};

        // Priority queue for merging
        std::priority_queue<FileRecord, std::vector<FileRecord>, std::greater<FileRecord>> pq;
        
        // Open all input files
        std::vector<std::unique_ptr<std::ifstream>> input_streams;
        for (const auto& file : input_files) {
            auto stream = std::make_unique<std::ifstream>(file, std::ios::binary);
            if (!*stream) {
                throw std::runtime_error("Cannot open input file for merging: " + file);
            }
            input_streams.push_back(std::move(stream));
        }
        
        // Initialize priority queue with first record from each file
        for (size_t i = 0; i < input_streams.size(); ++i) {
            try {
                RecordPtr record = readRecord(*input_streams[i]);
                if (record.get() != nullptr) {
                    pq.push(FileRecord(std::move(record), i));
                }
            } catch (const std::exception& e) {
                std::cerr << "Error reading initial record from file " << i << ": " << e.what() << std::endl;
            }
        }
        
        // Open output file
        std::ofstream outFile(output_file, std::ios::binary);
        if (!outFile) {
            throw std::runtime_error("Cannot create output file for merging: " + output_file);
        }
        
        // Merge records
        while (!pq.empty()) {
            FileRecord fr = std::move(const_cast<FileRecord&>(pq.top()));
            pq.pop();
            
            // Write the smallest record to output
            writeRecord(outFile, fr.record);
            
            // Read next record from the same file
            try {
                RecordPtr next_record = readRecord(*input_streams[fr.file_index]);
                if (next_record.get() != nullptr) {
                    pq.push(FileRecord(std::move(next_record), fr.file_index));
                }
            } catch (const std::exception& e) {
                if (!input_streams[fr.file_index]->eof()) {
                    std::cerr << "Error reading next record: " << e.what() << std::endl;
                }
            }
        }
        
        outFile.close();
    }

    /**
     * FastFlow Worker for chunk merging tasks
     */
    class MergeWorker : public ff::ff_node {
    private:
        std::function<std::string()> getTempFileName_;
        FastFlowMergeSort* sorter_;

    public:
        MergeWorker(std::function<std::string()> getTempFileName, FastFlowMergeSort* sorter) 
            : getTempFileName_(getTempFileName), sorter_(sorter) {}

        void* svc(void* task) override {
            auto* chunk_group = static_cast<std::vector<std::string>*>(task);
            std::string merged_file = getTempFileName_();
            
            // Merge the chunk group
            sorter_->kWayMerge(*chunk_group, merged_file);
            
            // Return the merged file name
            delete chunk_group;
            return new std::string(merged_file);
        }
    };

    /**
     * Merges multiple sorted chunks using FastFlow
     * @param chunk_files Vector of paths to sorted chunk files
     * @param output_file Path to the output file for the merged result
     */
    void fastflowHierarchicalMerge(const std::vector<std::string>& chunk_files, const std::string& output_file) {
        Timer timer("FastFlow hierarchical merge");
        
        if (chunk_files.empty()) {
            std::ofstream empty_out(output_file, std::ios::binary);
            return;
        }
        
        if (chunk_files.size() == 1) {
            fs::copy_file(chunk_files[0], output_file, fs::copy_options::overwrite_existing);
            return;
        }
        
        // Calculate maximum number of files to merge at once
        const size_t K = 10; // Can be adjusted
        
        // If we have fewer chunks than K, merge them directly
        if (chunk_files.size() <= K) {
            kWayMerge(chunk_files, output_file);
            return;
        }
        
        // Create groups of at most K files
        size_t num_groups = std::ceil(static_cast<double>(chunk_files.size()) / K);
        std::vector<std::vector<std::string>*> chunk_groups;
        
        for (size_t i = 0; i < num_groups; ++i) {
            size_t start_idx = i * K;
            size_t end_idx = std::min((i + 1) * K, chunk_files.size());
            
            auto* group = new std::vector<std::string>(
                chunk_files.begin() + start_idx, 
                chunk_files.begin() + end_idx
            );
            
            chunk_groups.push_back(group);
        }
        
        // Set up FastFlow farm for parallel merging
        std::vector<std::string> intermediate_files;
        
        // Use a lambda to capture this pointer for getNextTempFileName
        auto getTempFileNameWrapper = [this]() { return this->getNextTempFileName(); };
        
        // Custom emitter to distribute chunk groups
        class GroupEmitter : public ff::ff_node {
        private:
            std::vector<std::vector<std::string>*>& groups_;
            size_t current_idx_ = 0;
            
        public:
            GroupEmitter(std::vector<std::vector<std::string>*>& groups) : groups_(groups) {}
            
            void* svc(void*) override {
                if (current_idx_ >= groups_.size()) {
                    return nullptr; // End of stream
                }
                return groups_[current_idx_++];
            }
        };
        
        // Set up FastFlow farm
        GroupEmitter emitter(chunk_groups);
        FilenameCollector collector(intermediate_files);
        
        std::vector<ff::ff_node*> workers;
        for (unsigned i = 0; i < std::min(num_workers_, (unsigned)num_groups); ++i) {
            workers.push_back(new MergeWorker(getTempFileNameWrapper, this));
        }
        
        ff::ff_farm farm;
        farm.add_emitter(&emitter);
        farm.add_workers(workers);
        farm.add_collector(&collector);
        
        if (farm.run_and_wait_end() < 0) {
            throw std::runtime_error("FastFlow merge farm execution failed");
        }
        
        // Cleanup workers
        for (auto worker : workers) {
            delete worker;
        }
        
        // Recursively merge the intermediate files
        fastflowHierarchicalMerge(intermediate_files, output_file);
        
        // Clean up intermediate files
        for (const auto& file : intermediate_files) {
            fs::remove(file);
        }
    }

public:
    /**
     * Constructor
     * @param num_workers Number of FastFlow workers to use
     */
    FastFlowMergeSort(unsigned num_workers)
        : num_workers_(num_workers), 
          temp_dir_("./ff_tmp"), 
          file_id_(0) {
        
        // Calculate memory limit per worker
        memory_limit_ = MAX_MEMORY_USAGE / num_workers_;
        
        // Create temporary directory
        fs::create_directories(temp_dir_);
    }
    
    /**
     * Destructor - Clean up temporary files
     */
    ~FastFlowMergeSort() {
        try {
            fs::remove_all(temp_dir_);
        } catch (const std::exception& e) {
            std::cerr << "Error cleaning up temporary directory: " << e.what() << std::endl;
        }
    }
    
    /**
     * Sort an input file using FastFlow parallelism
     * @param input_file Path to input file
     * @param output_file Path to output file where sorted data will be written
     */
    void sort(const std::string& input_file, const std::string& output_file) {
        Timer timer("FastFlow sort total time");
        
        // Partition the input file into sorted chunks
        std::vector<std::string> sorted_chunks = partitionIntoSortedChunks(input_file);
        
        // Merge all chunks into the final output
        mergeChunks(sorted_chunks, output_file);
        
        // Clean up sorted chunks
        for (const auto& chunk : sorted_chunks) {
            fs::remove(chunk);
        }
    }
    
    /**
     * Merge a set of pre-sorted chunks
     * @param chunk_files Vector of paths to pre-sorted chunk files
     * @param output_file Path to output file where merged data will be written
     */
    void mergeChunks(const std::vector<std::string>& chunk_files, const std::string& output_file) {
        Timer timer("Merging chunks");
        
        // Use hierarchical merging to handle large numbers of chunks efficiently
        fastflowHierarchicalMerge(chunk_files, output_file);
    }
};

#endif // FASTFLOW_SORT_HPP