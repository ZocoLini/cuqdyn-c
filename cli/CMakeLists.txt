file(GLOB CLI_SRC CONFIGURE_DEPENDS src/*.c src/handlers/*.c)
file(GLOB CLI_HEADERS CONFIGURE_DEPENDS include include/handlers)

include_directories(cli
        ${CLI_HEADERS}
)

add_executable(cli
        ${CLI_SRC}
)

target_link_libraries(cli
        PRIVATE
        cli-lib
)
