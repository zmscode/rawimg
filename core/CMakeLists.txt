cmake_minimum_required(VERSION 3.20)
project(rawimg-core VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(rawimg-core STATIC
    src/main.cpp
    src/image.cpp
    src/stb_impl.cpp
)

target_include_directories(rawimg-core PUBLIC
    ${PROJECT_SOURCE_DIR}/include
    ${PROJECT_SOURCE_DIR}/vendor
)

# Tests
add_executable(rawimg-tests tests/test_core.cpp)
target_link_libraries(rawimg-tests PRIVATE rawimg-core)
