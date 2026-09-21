set(CUQDYN_TEST_SANITIZER_ENV
    "ASAN_OPTIONS=detect_stack_use_after_return=1:strict_string_checks=1:detect_leaks=1:intercept_strndup=0"
    "LSAN_OPTIONS=suppressions=${CMAKE_CURRENT_SOURCE_DIR}/lsan-mpi.supp"
    "UBSAN_OPTIONS=print_stacktrace=1"
)

set(CUQDYN_MPI_TESTS test_ess_solver test_cuqdyn_algo)
set(CUQDYN_MPI_NPROCS 1 3 17 32)

if(CUQDYN_MPI)
    find_package(MPI REQUIRED COMPONENTS C)
endif()

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

    set(registered)

    if(CUQDYN_MPI AND test_name IN_LIST CUQDYN_MPI_TESTS)
        foreach(np ${CUQDYN_MPI_NPROCS})
            # --oversubscribe: Open MPI refuses more ranks than cores, and
            # CI runners are small.
            add_test(
                NAME ${test_name}_np${np}
                COMMAND
                    ${MPIEXEC_EXECUTABLE} ${MPIEXEC_NUMPROC_FLAG} ${np}
                    --oversubscribe $<TARGET_FILE:${test_name}>
            )
            list(APPEND registered ${test_name}_np${np})
        endforeach()
    else()
        add_test(NAME ${test_name} COMMAND ${test_name})
        list(APPEND registered ${test_name})
    endif()

    if(CUQDYN_SANITIZE)
        set_tests_properties(
            ${registered}
            PROPERTIES ENVIRONMENT "${CUQDYN_TEST_SANITIZER_ENV}"
        )
    endif()
endforeach()

add_test(
    NAME test_module_version
    COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/test_module_version.sh
)
