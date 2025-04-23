file(GLOB LIB_SRC CONFIGURE_DEPENDS src/*.c)

add_library(cli-lib
        ${LIB_SRC}
)

target_include_directories(cli-lib
        PUBLIC include
)

target_link_libraries(cli-lib
        PUBLIC
        cuqdyn-c
        PRIVATE
        matio
)
