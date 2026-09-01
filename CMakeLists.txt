cmake_minimum_required(VERSION 3.26)
project(cuqdyn LANGUAGES C Fortran CXX)
set(CMAKE_C_STANDARD 11)

include(deps.cmake)

# Only our own code, never the FetchContent dependencies above: hdf5 generates
# H5Tinit.c by running H5detect, which probes the platform with deliberately
# misaligned stores and so aborts under UBSan. Placing this after deps.cmake and
# before the modules is what draws that line.
if(CUQDYN_SANITIZE)
    add_compile_options(
        -fsanitize=address,undefined
        -fno-omit-frame-pointer
        -fno-sanitize-recover=all
    )
    add_link_options(-fsanitize=address,undefined)
endif()

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY .)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY .)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY .)

add_subdirectory(modules/sacess)
add_subdirectory(modules/cuqdyn-c)
add_subdirectory(modules/cli)

add_subdirectory(benches)

enable_testing()

add_subdirectory(tests)
