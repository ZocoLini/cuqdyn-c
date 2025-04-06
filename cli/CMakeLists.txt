file(GLOB CLI_SRC CONFIGURE_DEPENDS src/*.c)

add_executable(
        cli
        ${CLI_SRC}
)

target_link_libraries(
        cli
        PRIVATE lib
)
