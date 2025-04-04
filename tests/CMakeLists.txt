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
        test_matlab
        test_matlab.c
        ../src/matlab.c
)

target_link_libraries(
        test_matlab
        sundials_cvode
        sundials_nvecserial
        sundials_core
        m
)

add_test(NAME test_matlab COMMAND test_stack)
