cmake_minimum_required(VERSION 3.30)
project(conformal_prediction_dbs C)

set(CMAKE_C_STANDARD 11)

include_directories(include)
include_directories(
        /home/borja/sundials/instdir/include
)

add_executable(
        conformal_prediction_dbs
        src/main.c
        src/lib.c
        src/math.c
        src/lotka_volterra.c
        src/matlab.c)
