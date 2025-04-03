cmake_minimum_required(VERSION 3.30)
project(conformal_prediction_dbs_2 C)

set(CMAKE_C_STANDARD 11)

include_directories(includes)

add_executable(
        conformal_prediction_dbs_2
        src/main.c)
