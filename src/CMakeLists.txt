set(SUNDIALS_DIR "/home/borja/sundials/instdir/lib/cmake/sundials")

find_package(SUNDIALS REQUIRED)

set(CMAKE_C_STANDARD 11)

link_directories(
        /home/borja/sundials/instdir/lib
)

include_directories(
        ../include
        /home/borja/sundials/instdir/include
)

add_executable(
        bin
        lib.c
        main.c
        lotka_volterra.c
        math.c
        matlab.c
)

target_link_libraries(
        bin
        sundials_cvode
        sundials_nvecserial
        sundials_core
        m
)
