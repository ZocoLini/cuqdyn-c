link_directories(
        ${PROJECT_SOURCE_DIR}/sundials/instdir/lib
)

include_directories(
        ../include
        ${PROJECT_SOURCE_DIR}/sundials/instdir/include
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
