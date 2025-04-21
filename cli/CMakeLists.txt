file(GLOB CLI_SRC CONFIGURE_DEPENDS src/*.c src/handlers/*.c)

include_directories(cli
        include
)

add_executable(cli
        ${CLI_SRC}
)

target_link_libraries(cli
        PRIVATE
        cli-lib
)
