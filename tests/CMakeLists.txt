add_executable(test_matlab
        test_matlab.c
)

target_link_libraries(test_matlab
        PRIVATE lib
)

add_test(NAME test_matlab COMMAND test_matlab)
