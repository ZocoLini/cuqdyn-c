foreach(
    test_name
    test_matlab
    test_ode_solver
    test_matrix_array_get_median
    test_get_matrix_cols_median
    test_ess_solver
    test_ess_obj_function
    test_cuqdyn_algo
    test_context_and_config
)
    add_executable(${test_name} ${test_name}.c)
    target_link_libraries(${test_name} cuqdyn-c)
    target_compile_options(${test_name} PRIVATE -O0 -g -UNDEBUG)
    target_compile_definitions(
        ${test_name}
        PRIVATE EXAMPLES_DIR="${CMAKE_SOURCE_DIR}/example-files"
    )
    add_test(NAME ${test_name} COMMAND ${test_name})
endforeach()

add_test(
    NAME test_module_version
    COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/test_module_version.sh
)
