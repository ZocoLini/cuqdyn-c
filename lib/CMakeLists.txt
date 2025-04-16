file(GLOB LIB_SRC CONFIGURE_DEPENDS src/*.c)

add_library(
        lib
        ${LIB_SRC}
)

target_include_directories(lib
        PUBLIC
        include
)

target_link_libraries(lib
        PUBLIC
        cvodes_old

        PRIVATE
        sacess
)
