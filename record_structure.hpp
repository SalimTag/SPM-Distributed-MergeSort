#ifndef RECORD_STRUCTURE_HPP
#define RECORD_STRUCTURE_HPP

#include <cstring>     
#include <chrono>
#include <cstdint>
#include <vector>
#include <memory>
#include <string>
#include <iostream>
#include <fstream>
#include <stdexcept>

// Payload size constraints
constexpr uint32_t PAYLOAD_MIN = 8;
constexpr uint32_t PAYLOAD_MAX = 4096;

// Header size (key + len, no padding)
constexpr size_t HEADER_SIZE = sizeof(uint64_t) + sizeof(uint32_t); // 12 bytes

// Record structure as defined in the specification
struct Record {
    uint64_t key;  // 8-byte sorting key (portable)
    uint32_t len;  // payload length (8 <= len <= PAYLOAD_MAX)
    char payload[];     // flexible array member (C99-style)
};

// Constants for chunk management
constexpr size_t MB = 1024 * 1024;
constexpr size_t BUFFER_SIZE = 64 * MB;               // 64MB buffer for I/O
constexpr size_t MAX_MEMORY_USAGE = 30UL * 1024 * MB; // 30GB memory cap

// RecordPtr for managing dynamic records
class RecordPtr {
private:
    std::unique_ptr<char[]> buffer;
    Record* record;

public:
    RecordPtr() : buffer(nullptr), record(nullptr) {}

    RecordPtr(char* data, size_t size)
        : buffer(new char[size]), record(reinterpret_cast<Record*>(buffer.get())) {
        ::memcpy(buffer.get(), data, size);
    }

    RecordPtr(RecordPtr&& other) noexcept
        : buffer(std::move(other.buffer)), record(other.record) {
        other.record = nullptr;
    }

    RecordPtr& operator=(RecordPtr&& other) noexcept {
        if (this != &other) {
            buffer = std::move(other.buffer);
            record = other.record;
            other.record = nullptr;
        }
        return *this;
    }

    RecordPtr(const RecordPtr&) = delete;
    RecordPtr& operator=(const RecordPtr&) = delete;

    void allocate(uint32_t payload_size) {
        size_t total_size = HEADER_SIZE + payload_size;
        buffer.reset(new char[total_size]);
        record = reinterpret_cast<Record*>(buffer.get());
        record->len = payload_size;
    }

    Record* get() const { return record; }
    
    const char* data() const { return buffer.get(); }
    
    size_t size() const { 
        return record ? HEADER_SIZE + record->len : 0; 
    }

    bool operator<(const RecordPtr& other) const {
        return record->key < other.record->key;
    }
};

// Calculate total record size
inline size_t calculateRecordSize(const Record* record) {
    return HEADER_SIZE + record->len;
}

// Read a record from file
inline RecordPtr readRecord(std::ifstream& inFile) {
    uint64_t key;
    uint32_t len;

    // Read key and length separately
    inFile.read(reinterpret_cast<char*>(&key), sizeof(uint64_t));
    inFile.read(reinterpret_cast<char*>(&len), sizeof(uint32_t));

    if (!inFile) return RecordPtr(); // EOF or bad read

    // Validate payload length
    if (len < PAYLOAD_MIN || len > PAYLOAD_MAX) {
        throw std::runtime_error("Invalid record length: " + std::to_string(len));
    }

    // Create RecordPtr and allocate buffer directly
    RecordPtr recordPtr;
    recordPtr.allocate(len);
    
    // Set the key
    recordPtr.get()->key = key;
    recordPtr.get()->len = len;

    // Read payload directly into the RecordPtr buffer
    inFile.read(recordPtr.get()->payload, len);
    if (!inFile) {
        throw std::runtime_error("Failed to read record payload");
    }

    return recordPtr;
}

// Write a record to file
inline void writeRecord(std::ofstream& outFile, const RecordPtr& rec) {
    outFile.write(rec.data(), rec.size());   // header (12 B) + payload
}

// Timing utility
class Timer {
private:
    std::chrono::high_resolution_clock::time_point start_time;
    std::string operation_name;

public:
    Timer(const std::string& name) : operation_name(name) {
        start_time = std::chrono::high_resolution_clock::now();
    }

    ~Timer() {
        auto end_time = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
        std::cout << operation_name << " took " << duration.count() << " ms" << std::endl;
    }
};

#endif // RECORD_STRUCTURE_HPP
