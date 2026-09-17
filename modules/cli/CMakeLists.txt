cuqdyn_module_version(cli)

file(GLOB CLI_SRC CONFIGURE_DEPENDS src/*.c src/handlers/*.c)

add_executable(cli ${CLI_SRC})
add_dependencies(cli cli_version)

target_include_directories(cli PRIVATE include generated)

target_link_libraries(cli PRIVATE cuqdyn-c)
