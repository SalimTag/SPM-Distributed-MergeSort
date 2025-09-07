#include <iostream>
#include <fstream>
#include <random>
#include <vector>
#include <cstdint>

constexpr uint32_t PAYLOAD_MIN = 8;
constexpr uint32_t PAYLOAD_MAX = 4096;

int main(int argc, char* argv[]) {
    if (argc < 3 || argc > 4) {
        std::cerr << "Usage: " << argv[0] << " <output_file> <num_records> [payload_size]\n";
        return 1;
    }

    std::string output_file = argv[1];
    size_t num_records = std::stoull(argv[2]);
    bool fixed_size = (argc == 4);
    uint32_t payload_size = fixed_size ? std::stoul(argv[3]) : 0;

    if (fixed_size && (payload_size < PAYLOAD_MIN || payload_size > PAYLOAD_MAX)) {
        std::cerr << "Payload size must be between " << PAYLOAD_MIN << " and " << PAYLOAD_MAX << ".\n";
        return 1;
    }

    std::ofstream out(output_file, std::ios::binary);
    if (!out) {
        std::cerr << "Failed to open output file: " << output_file << "\n";
        return 1;
    }

    std::mt19937_64 rng(42);  // fixed seed for reproducibility
    std::uniform_int_distribution<uint64_t> key_dist;
    std::uniform_int_distribution<uint32_t> len_dist(PAYLOAD_MIN, PAYLOAD_MAX);
    std::uniform_int_distribution<uint8_t> byte_dist(0, 255);

    for (size_t i = 0; i < num_records; ++i) {
        uint64_t key = key_dist(rng);
        uint32_t len = fixed_size ? payload_size : len_dist(rng);

        // Write key and length
        out.write(reinterpret_cast<const char*>(&key), sizeof(key));
        out.write(reinterpret_cast<const char*>(&len), sizeof(len));

        // Generate and write payload in a single call
        std::vector<uint8_t> payload(len);
        for (auto& byte : payload) {
            byte = byte_dist(rng);
        }
        out.write(reinterpret_cast<const char*>(payload.data()), len);
    }

    std::cout << " Generated " << num_records
              << " records with "
              << (fixed_size ? std::to_string(payload_size) + "B" : "random-sized")
              << " payloads.\n";

    return 0;
}
