cmake_minimum_required(VERSION 3.20)
project(rawimg-core VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find LibRaw
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBRAW REQUIRED libraw)

add_library(rawimg-core STATIC
    src/main.cpp
    src/image.cpp
    src/stb_impl.cpp
    src/libraw_loader.cpp
)

target_include_directories(rawimg-core PUBLIC
    ${PROJECT_SOURCE_DIR}/include
    ${PROJECT_SOURCE_DIR}/vendor
    ${LIBRAW_INCLUDE_DIRS}
)

target_link_libraries(rawimg-core PUBLIC ${LIBRAW_LIBRARIES})
target_link_directories(rawimg-core PUBLIC ${LIBRAW_LIBRARY_DIRS})

# Tests
add_executable(rawimg-tests tests/test_core.cpp)
target_link_libraries(rawimg-tests PRIVATE rawimg-core)
