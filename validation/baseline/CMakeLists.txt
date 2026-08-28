# MATLAB-baseline comparison harness (layers 3 and 4), registered from
# validation/CMakeLists.txt. The tests SKIP - not fail - while the MATLAB
# exports under matlab/ are absent, so builds without the baseline stay green.

add_executable(test_baseline test_baseline.c)
target_link_libraries(test_baseline cuqdyn-c)
# -O0: the comparison must be free of fast-math style reassociation.
target_compile_options(test_baseline PRIVATE -O0 -g -UNDEBUG)

set(BASELINE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/matlab)
set(EXAMPLES ${PROJECT_SOURCE_DIR}/example-files)

add_test(NAME baseline_lv2
         COMMAND test_baseline ${BASELINE_DIR}/lv2
                 ${EXAMPLES}/lv2_partobs_cuqdyn_config.xml
                 ${EXAMPLES}/lv2_partobs_paper_data.txt)

# The full-sigma copy lives here so this branch touches nothing outside
# validation/: example-files/nfkb_cuqdyn_config.xml carries the same values
# truncated to fewer digits, which fails the 1e-9 sigma cross-check.
add_test(NAME baseline_nfkb
         COMMAND test_baseline ${BASELINE_DIR}/nfkb
                 ${CMAKE_CURRENT_SOURCE_DIR}/nfkb_cuqdyn_fullsigma.xml
                 ${EXAMPLES}/nfkb_paper_data.txt)

# The AP partially-observed example has no example-files/ counterpart yet, so
# its data and configs live in this directory (mirrors the MATLAB runner
# EXAMPLES/AP/run_AP_CUQDyn1Plus_partobs_example.m).
add_test(NAME baseline_ap
         COMMAND test_baseline ${BASELINE_DIR}/ap
                 ${CMAKE_CURRENT_SOURCE_DIR}/ap_partobs_cuqdyn_config.xml
                 ${CMAKE_CURRENT_SOURCE_DIR}/ap_partobs_paper_data.txt)

add_test(NAME baseline_sir
         COMMAND test_baseline ${BASELINE_DIR}/sir
                 ${EXAMPLES}/sir_cuqdyn_config.xml
                 ${EXAMPLES}/sir_paper_data.txt)

set_tests_properties(baseline_lv2 baseline_nfkb baseline_ap baseline_sir
                     PROPERTIES SKIP_RETURN_CODE 77)

# Layer 2.5: the C cost function replayed over a recorded MATLAB eSS search.
# All randomness lives on the MATLAB side (the frozen evaluation sequence);
# the replay itself is fully deterministic.
add_executable(test_cost_replay cost_replay/test_cost_replay.c)
target_link_libraries(test_cost_replay cuqdyn-c)
target_compile_options(test_cost_replay PRIVATE -O0 -g -UNDEBUG)

add_test(NAME cost_replay_lv2
         COMMAND test_cost_replay ${CMAKE_CURRENT_SOURCE_DIR}/cost_replay/lv2_evals.txt
                 ${EXAMPLES}/lv2_partobs_cuqdyn_config.xml
                 ${EXAMPLES}/lv2_partobs_paper_data.txt)
set_tests_properties(cost_replay_lv2 PROPERTIES SKIP_RETURN_CODE 77)
