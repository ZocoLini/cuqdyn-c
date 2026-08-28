file(COPY ${CMAKE_CURRENT_SOURCE_DIR}/golden DESTINATION ${CMAKE_CURRENT_BINARY_DIR})

add_executable(test_golden test_golden.c)
target_link_libraries(test_golden cuqdyn-c)
# -O0 keeps the comparison free of any fast-math style reassociation.
target_compile_options(test_golden PRIVATE -O0 -g -UNDEBUG)

add_test(NAME validation_golden
         COMMAND test_golden ${CMAKE_CURRENT_BINARY_DIR}/golden 1e-9)

# MATLAB-baseline comparison (layers 3 and 4). Its tests SKIP while the
# MATLAB exports under baseline/matlab/ are absent.
add_subdirectory(baseline)
