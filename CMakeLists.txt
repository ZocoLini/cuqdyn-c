cmake_minimum_required(VERSION 3.15)
project(cuqdyn LANGUAGES C Fortran CXX)
set(CMAKE_C_STANDARD 11)

include(deps.cmake)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY .)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY .)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY .)

add_subdirectory(modules/cvodes_old)
add_subdirectory(modules/sacess)
add_subdirectory(modules/cuqdyn-c)
add_subdirectory(modules/cli)
add_subdirectory(modules/dotmat-introspector)

enable_testing()

add_subdirectory(tests)
