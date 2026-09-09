# Validation harness, one directory per layer. Every test SKIPs (return 77)
# rather than failing while its reference data is absent, so a checkout without
# the MATLAB exports still builds and runs green.

set(VALIDATION_DIR ${CMAKE_CURRENT_SOURCE_DIR})
set(EXAMPLES ${PROJECT_SOURCE_DIR}/example-files)
set(CONFIGS ${CMAKE_CURRENT_SOURCE_DIR}/common/configs)

# -O0 on every comparator: the diffs must be free of fast-math style
# reassociation, which is the whole point of comparing against MATLAB.

# --- layer 1: algebra kernels -------------------------------------------

add_executable(test_golden layer1/test_golden.c)
target_link_libraries(test_golden cuqdyn-c)
target_compile_options(test_golden PRIVATE -O0 -g -UNDEBUG)

add_test(NAME layer1_golden
         COMMAND test_golden ${VALIDATION_DIR}/layer1/cases 1e-9)

# --- layers 2 and 4: ODE + sensitivities, and the UQ replay --------------

add_executable(test_baseline test_baseline.c)
target_link_libraries(test_baseline cuqdyn-c)
target_compile_options(test_baseline PRIVATE -O0 -g -UNDEBUG)

add_test(NAME baseline_lv2
         COMMAND test_baseline ${VALIDATION_DIR} lv2
                 ${EXAMPLES}/lv2-partobs/cuqdyn-fim.xml
                 ${EXAMPLES}/lv2-partobs/data.txt)

# The full-sigma copy lives in common/configs: example-files/nfkb/cuqdyn-fim.xml
# carries the same values truncated to fewer digits, which fails the 1e-9 sigma
# cross-check.
add_test(NAME baseline_nfkb
         COMMAND test_baseline ${VALIDATION_DIR} nfkb
                 ${CONFIGS}/nfkb_cuqdyn_fullsigma.xml
                 ${EXAMPLES}/nfkb/data.txt)

# The AP partially-observed example has no example-files/ counterpart yet, so
# its data and configs live in common/configs (mirrors the MATLAB runner
# EXAMPLES/AP/run_AP_CUQDyn1Plus_partobs_example.m).
add_test(NAME baseline_ap
         COMMAND test_baseline ${VALIDATION_DIR} ap
                 ${CONFIGS}/ap_partobs_cuqdyn_config.xml
                 ${CONFIGS}/ap_partobs_paper_data.txt)

add_test(NAME baseline_sir
         COMMAND test_baseline ${VALIDATION_DIR} sir
                 ${EXAMPLES}/sir/cuqdyn-fim.xml
                 ${EXAMPLES}/sir/data.txt)

# --- layer 3: the cost function replayed over a recorded MATLAB search ---

add_executable(test_cost_replay layer3/test_cost_replay.c)
target_link_libraries(test_cost_replay cuqdyn-c)
target_compile_options(test_cost_replay PRIVATE -O0 -g -UNDEBUG)

add_test(NAME cost_replay_lv2
         COMMAND test_cost_replay ${VALIDATION_DIR}/layer3/lv2_evals.txt
                 ${EXAMPLES}/lv2-partobs/cuqdyn-fim.xml
                 ${EXAMPLES}/lv2-partobs/data.txt)

set_tests_properties(layer1_golden baseline_lv2 baseline_nfkb baseline_ap baseline_sir cost_replay_lv2
                     PROPERTIES SKIP_RETURN_CODE 77)

# --- layer 5: statistical end-to-end ------------------------------------
#
# Not a ctest. Both sides run the full pipeline N times and the comparison is a
# report to read, not a gate:
#
#   validation/layer5/run_c_seeds.sh lv2 10
#   python3 validation/layer5/compare_baseline.py lv2
#
# layer5/hybrid/cost_server is built here because MATLAB's MEIGO drives it over
# TCP; it is started by hand from hybrid_meigo_cvodes.m.

add_executable(cost_server layer5/hybrid/cost_server.c)
target_link_libraries(cost_server cuqdyn-c)
target_compile_options(cost_server PRIVATE -O0 -g -UNDEBUG)
