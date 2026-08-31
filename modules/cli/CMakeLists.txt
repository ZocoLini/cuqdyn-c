cuqdyn_module_version(cli cli_version)

file(GLOB CLI_SRC CONFIGURE_DEPENDS src/*.c src/handlers/*.c)

include_directories(cli include generated)

add_executable(cli ${CLI_SRC})
add_dependencies(cli cli_version)

target_link_libraries(cli PRIVATE cuqdyn-c)
