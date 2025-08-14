FetchContent_Declare(
    nanobench
    GIT_REPOSITORY https://github.com/martinus/nanobench.git
    GIT_TAG v4.1.0
    GIT_SHALLOW TRUE
)


FetchContent_MakeAvailable(nanobench)

add_library(bench_wrapper bench_wrapper.cpp)
TARGET_LINK_LIBRARIES(bench_wrapper PRIVATE nanobench)

foreach(bench_name
    bench_transform_states
)
    add_executable(${bench_name} ${bench_name}.c)
    target_link_libraries(${bench_name} PRIVATE cuqdyn-c bench_wrapper)
endforeach()
