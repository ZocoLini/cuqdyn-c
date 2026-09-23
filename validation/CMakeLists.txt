# Validation harness, one directory per layer. Every test SKIPs (return 77)
# rather than failing while its reference data is absent, so a checkout without
# the MATLAB exports still builds and runs green.

# Registered either by add_subdirectory(validation) at the end of the top-level
# CMakeLists.txt or, without editing it, by cmake/register.cmake at project()
# time - hence testing and the sanitizer flags are set up here as well.
enable_testing()
if(CUQDYN_SANITIZE)
    add_compile_options(
        -fsanitize=address,undefined
        -fno-omit-frame-pointer
        -fno-sanitize-recover=all
    )
    add_link_options(-fsanitize=address,undefined)
endif()

# HDF5's build leaves its own output directory in the cache; the top-level
# file resets it only after register.cmake has run.
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})

set(VALIDATION_DIR ${CMAKE_CURRENT_SOURCE_DIR})
# One directory per problem: cuqdyn.xml, sacess.xml, data.txt, problem.conf.
set(INPUT ${CMAKE_CURRENT_SOURCE_DIR}/input_validation)

# -O0 on every comparator: the diffs must be free of fast-math style
# reassociation, which is the whole point of comparing against MATLAB.

# --- layer 1: algebra kernels -------------------------------------------

add_executable(test_golden c/test_golden.c)
target_link_libraries(test_golden cuqdyn-c)
target_compile_options(test_golden PRIVATE -O0 -g -UNDEBUG)

add_test(
    NAME layer1_golden
    COMMAND test_golden ${VALIDATION_DIR}/references/golden.txt 1e-9
)

# --- layers 2 and 4: ODE + sensitivities, and the UQ replay --------------

add_executable(test_baseline c/test_baseline.c)
target_link_libraries(test_baseline cuqdyn-c)
target_compile_options(test_baseline PRIVATE -O0 -g -UNDEBUG)

foreach(model lv2 nfkb ap sir)
    add_test(
        NAME layer2_4_${model}
        COMMAND
            test_baseline ${VALIDATION_DIR} ${model}
            ${INPUT}/${model}/cuqdyn.xml ${INPUT}/${model}/data.txt
    )
endforeach()

# --- layer 3: the cost function replayed over a recorded MATLAB search ---

add_executable(test_cost_replay c/test_cost_replay.c)
target_link_libraries(test_cost_replay cuqdyn-c)
target_compile_options(test_cost_replay PRIVATE -O0 -g -UNDEBUG)

add_test(
    NAME layer3_lv2
    COMMAND
        test_cost_replay ${VALIDATION_DIR}/references/lv2_evals.txt
        ${INPUT}/lv2/cuqdyn.xml ${INPUT}/lv2/data.txt
)

set_tests_properties(
    layer1_golden
    layer2_4_lv2
    layer2_4_nfkb
    layer2_4_ap
    layer2_4_sir
    layer3_lv2
    PROPERTIES SKIP_RETURN_CODE 77
)

# --- layer 5: the C pipeline driven by MATLAB's MEIGO --------------------
#
# The CLI's own sources are compiled into pipeline_meigo together with
# c/pipeline_meigo.c, which defines execute_ess_solver(); the linker then
# takes that definition and never pulls ess_solver.o out of libcuqdyn-c.a, so
# the binary is the CLI with its optimiser replaced. The real run needs
# MATLAB (validation/run_validation.sh layer 5); the ctest is the loopback
# plumbing check.

file(
    GLOB CLI_SOURCES
    CONFIGURE_DEPENDS
    ${PROJECT_SOURCE_DIR}/modules/cli/src/*.c
    ${PROJECT_SOURCE_DIR}/modules/cli/src/handlers/*.c
)
add_executable(pipeline_meigo c/pipeline_meigo.c ${CLI_SOURCES})
add_dependencies(pipeline_meigo cli_version)
target_include_directories(
    pipeline_meigo
    PRIVATE
        ${PROJECT_SOURCE_DIR}/modules/cli/include
        ${PROJECT_SOURCE_DIR}/modules/cli/generated
)
target_link_libraries(pipeline_meigo cuqdyn-c)
target_compile_options(pipeline_meigo PRIVATE -O0 -g -UNDEBUG)

add_test(
    NAME layer5_loopback_lv2
    COMMAND
        bash ${VALIDATION_DIR}/c/loopback_check.sh $<TARGET_FILE:pipeline_meigo>
        ${INPUT}/lv2/cuqdyn.xml ${INPUT}/lv2/sacess.xml ${INPUT}/lv2/data.txt
        ${CMAKE_CURRENT_BINARY_DIR}/loopback_lv2 "0.5 0.02 0.02 0.5"
)

# --- layer 6: statistical end-to-end ------------------------------------
#
# Not a ctest. Both sides run the full pipeline N times and the comparison is a
# report to read, not a gate:
#
#   validation/run_validation.sh layer 6 --problem=lv2 --seeds=10
#
# c/cost_server is built here because MATLAB's MEIGO drives it over
# TCP; it is started by hand from hybrid_meigo_cvodes.m.

add_executable(cost_server c/cost_server.c)
target_link_libraries(cost_server cuqdyn-c)
target_compile_options(cost_server PRIVATE -O0 -g -UNDEBUG)
