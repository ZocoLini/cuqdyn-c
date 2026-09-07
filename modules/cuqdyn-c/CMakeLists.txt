cuqdyn_module_version(cuqdyn-c)

file(GLOB LIB_SRC CONFIGURE_DEPENDS src/*.c)

add_library(cuqdyn-c ${LIB_SRC})
add_dependencies(cuqdyn-c rust_lib cuqdyn_c_version)

target_include_directories(
    cuqdyn-c
    PUBLIC
        include
        generated
        ${cvodes_BINARY_DIR}/include
        ${muparser_SOURCE_DIR}/include
        ${RUST_LIB_DIR}/include
)

target_link_directories(cuqdyn-c PUBLIC ${RUST_TARGET_DIR})

target_link_libraries(cuqdyn-c PUBLIC sacess cuqdyn_rs SUNDIALS::core)
