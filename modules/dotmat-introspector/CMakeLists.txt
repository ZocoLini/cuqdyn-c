file(GLOB CLI_SRC CONFIGURE_DEPENDS src/*.c)
file(GLOB CLI_HEADERS CONFIGURE_DEPENDS include)

include_directories(dotmat-introspector
        ${CLI_HEADERS}
)

add_executable(dotmat-introspector
        ${CLI_SRC}
)

target_link_libraries(dotmat-introspector
        PRIVATE
        cuqdyn-c
        matio
)