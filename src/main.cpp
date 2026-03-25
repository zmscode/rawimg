#include <cstdlib>
#include <iostream>

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: rawimg <input_file>\n";
        return EXIT_FAILURE;
    }

    std::cout << "rawimg v0.1.0\n";
    std::cout << "Input: " << argv[1] << "\n";

    return EXIT_SUCCESS;
}
