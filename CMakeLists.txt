cmake_minimum_required(VERSION 3.30)
project(conformal_prediction_dbs C)

set(SUNDIALS_DIR "/home/borja/sundials/instdir/lib/cmake/sundials")

find_package(SUNDIALS REQUIRED)

set(CMAKE_C_STANDARD 11)

link_directories(${SUNDIALS_LIB_DIR})

include_directories(
        include
        /home/borja/sundials/instdir/include
)

add_executable(
        conformal_prediction_dbs
        src/lib.c
        src/main.c
        src/lotka_volterra.c
        src/math.c
        src/matlab.c
)

target_link_libraries(conformal_prediction_dbs ${SUNDIALS_LIBRARIES} -lm)
