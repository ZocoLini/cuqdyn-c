file(COPY ${CMAKE_CURRENT_SOURCE_DIR}/data DESTINATION ${CMAKE_CURRENT_BINARY_DIR})

foreach(test_name
        test_matlab
        test_ode_solver
        test_matrix_array_get_median
        test_get_matrix_cols_median
        test_data_reader
        test_ess_solver
        test_parse_cuqdyn_conf
        test_ess_obj_function
        test_cuqdyn_algo
)
    add_executable(${test_name} ${test_name}.c)
    target_link_libraries(${test_name} cuqdyn-c)
    add_test(NAME ${test_name} COMMAND ${test_name})
endforeach()

