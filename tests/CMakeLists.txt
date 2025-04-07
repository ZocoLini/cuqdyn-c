add_executable(test_matlab
        test_matlab.c
)

target_link_libraries(test_matlab
        PRIVATE lib
)

add_executable(test_sundials_ode
        test_sundials_ode.c
)

target_link_libraries(test_sundials_ode
        PRIVATE lib
)

add_test(NAME test_matlab COMMAND test_matlab)
add_test(NAME test_sundials_ode COMMAND test_sundials_ode)
