cmake_minimum_required(VERSION 3.22.1)
project(conformal_prediction_dbs C)

set(CMAKE_C_STANDARD 11)
set(SUNDIALS_DIR "${PROJECT_SOURCE_DIR}/deps/cvode-7.2.1/lib/cmake/sundials")

find_package(SUNDIALS REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(MATIO REQUIRED matio)

enable_testing()

add_subdirectory(cli)
add_subdirectory(dotmat-introspector)
add_subdirectory(lib)
add_subdirectory(tests)
