cmake_minimum_required(VERSION 3.22.1)
project(conformal_prediction_dbs C)

set(CMAKE_C_STANDARD 11)

enable_testing()

add_subdirectory(src)
add_subdirectory(tests)
