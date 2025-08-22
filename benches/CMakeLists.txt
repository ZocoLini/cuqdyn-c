find_library(PAPI_LIB papi)

if(NOT PAPI_LIB)
    message(WARNING "⚠️  PAPI library not found, benchmarks will be skipped")
    return()
endif()

FetchContent_Declare(
    nanobench
    GIT_REPOSITORY https://github.com/martinus/nanobench.git
    GIT_TAG v4.1.0
    GIT_SHALLOW TRUE
)

FetchContent_MakeAvailable(nanobench)

add_library(bench_options bench_options.c)

add_library(bench_wrapper bench_wrapper.cpp)
target_link_libraries(bench_wrapper PUBLIC bench_options PRIVATE nanobench ${PAPI_LIB})

foreach(bench_name
    bench_transform_states
    bench_solve_ode
)
    add_executable(${bench_name} ${bench_name}.c)
    target_link_libraries(${bench_name} PRIVATE cuqdyn-c bench_wrapper)
endforeach()
