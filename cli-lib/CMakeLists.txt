file(GLOB LIB_SRC CONFIGURE_DEPENDS src/*.c)
file(GLOB LIB_HEADERS CONFIGURE_DEPENDS include)

add_library(cli-lib
        ${LIB_SRC}
)

target_include_directories(cli-lib
        PUBLIC ${LIB_HEADERS}
)

target_link_libraries(cli-lib
        PUBLIC
        lib
        matio
)
