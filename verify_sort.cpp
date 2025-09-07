#include <iostream>
#include <fstream>
#include <cstdint>
#include "record_structure.hpp"

bool verifySort(const std::string& filename) {
    std::ifstream file(filename, std::ios::binary);
    if (!file) {
        std::cerr << " Cannot open file: " << filename << std::endl;
        return false;
    }
    
    uint64_t prev_key = 0;
    uint64_t record_count = 0;
    bool first_record = true;
    
    std::cout << "🔍 Verifying sort order..." << std::endl;
    
    while (file.peek() != EOF) {
        uint64_t key;
        uint32_t len;
        
        // Read header
        if (!file.read(reinterpret_cast<char*>(&key), sizeof(uint64_t)) ||
            !file.read(reinterpret_cast<char*>(&len), sizeof(uint32_t))) {
            break; // End of file or read error
        }
        
        // Validate payload length
        if (len < PAYLOAD_MIN || len > PAYLOAD_MAX) {
            std::cerr << " Invalid payload length " << len << " at record " << record_count << std::endl;
            return false;
        }
        
        // Check sort order
        if (!first_record && key < prev_key) {
            std::cerr << "  Sort order violation at record " << record_count << std::endl;
            std::cerr << "   Previous key: " << prev_key << std::endl;
            std::cerr << "   Current key: " << key << std::endl;
            return false;
        }
        
        // Skip payload
        file.seekg(len, std::ios::cur);
        if (file.fail()) {
            std::cerr << " Failed to skip payload at record " << record_count << std::endl;
            return false;
        }
        
        prev_key = key;
        record_count++;
        first_record = false;
        
        // Progress indicator for large files
        if (record_count % 1000000 == 0) {
            std::cout << " Verified " << record_count << " records..." << std::endl;
        }
    }
    
    std::cout << " Sort verification successful!" << std::endl;
    std::cout << " Total records verified: " << record_count << std::endl;
    std::cout << " All records in correct ascending order" << std::endl;
    
    return true;
}

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <sorted_file>" << std::endl;
        return 1;
    }
    
    std::string filename = argv[1];
    
    if (!verifySort(filename)) {
        std::cerr << "❌ Verification FAILED" << std::endl;
        return 1;
    }
    
    std::cout << "🎉 File is correctly sorted!" << std::endl;
    return 0;
}
