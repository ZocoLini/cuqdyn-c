add_executable(test_matlab
        test_matlab.c
)

target_link_libraries(test_matlab
        PRIVATE lib
)

add_executable(test_ode_solver
        test_ode_solver.c
)

target_link_libraries(test_ode_solver
        PRIVATE lib
)

add_executable(test_matrix_array_get_median
        test_matrix_array_get_median.c
)

target_link_libraries(test_matrix_array_get_median
        PRIVATE lib
)

add_test(NAME test_matlab COMMAND test_matlab)
add_test(NAME test_ode_solver COMMAND test_ode_solver)
add_test(NAME test_matrix_array_get_median COMMAND test_matrix_array_get_median)
