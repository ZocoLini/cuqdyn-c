execute_process(
        COMMAND bash ${CMAKE_SOURCE_DIR}/scripts/get_module_version.sh cuqdyn-c
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_VERSION
        RESULT_VARIABLE TAG_RESULT
        OUTPUT_STRIP_TRAILING_WHITESPACE
)

if (NOT TAG_RESULT EQUAL 0 OR GIT_VERSION STREQUAL "")
    set(GIT_VERSION "dev")
endif ()

configure_file(
        include/cuqdyn_version.in.h
        ${PROJECT_SOURCE_DIR}/modules/cuqdyn-c/generated/cuqdyn_version.h
)

message(STATUS "CUQDYN_C_VERSION: ${GIT_VERSION}")
target_compile_definitions(sacess PUBLIC SACESS_C_VERSION="${GIT_VERSION}")

file(GLOB LIB_SRC CONFIGURE_DEPENDS src/*.c)

add_library(cuqdyn-c
        ${LIB_SRC}
)
add_dependencies(cuqdyn-c rust_lib)

target_include_directories(cuqdyn-c
        PUBLIC
        include
        generated
        ${cvodes_BINARY_DIR}/include
        ${matio_SOURCE_DIR}/src
        ${muparser_SOURCE_DIR}/include
        ${RUST_LIB_DIR}/include
)

target_link_directories(cuqdyn-c PUBLIC ${RUST_TARGET_DIR})

target_link_libraries(cuqdyn-c
        PUBLIC
        sacess
        matio
        mexpreval
        SUNDIALS::core
)
