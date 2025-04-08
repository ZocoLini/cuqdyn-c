foreach(test_name
        test_matlab
        test_ode_solver
        test_matrix_array_get_median
        test_get_matrix_cols_median
)
    add_executable(${test_name} ${test_name}.c)
    target_link_libraries(${test_name} PRIVATE lib)
    add_test(NAME ${test_name} COMMAND ${test_name})
endforeach()

