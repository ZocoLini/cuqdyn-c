cmake_minimum_required(VERSION 3.22.1)
project(conformal_prediction_dbs C)

set(CMAKE_C_STANDARD 11)
set(SUNDIALS_DIR "${PROJECT_SOURCE_DIR}/sundials/instdir/lib/cmake/sundials")

find_package(SUNDIALS REQUIRED)

enable_testing()

add_subdirectory(cli)
add_subdirectory(lib)
add_subdirectory(tests)
