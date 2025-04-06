cmake_minimum_required(VERSION 3.22.1)
project(conformal_prediction_dbs C)

set(SUNDIALS_DIR "${PROJECT_SOURCE_DIR}/sundials/instdir/lib/cmake/sundials")
set(CMAKE_C_STANDARD 11)

find_package(SUNDIALS REQUIRED)

enable_testing()

add_subdirectory(src)
add_subdirectory(tests)
