file(GLOB LIB_SRC CONFIGURE_DEPENDS src/*.c src/functions/*.c)

add_library(cuqdyn-c
        ${LIB_SRC}
)

target_include_directories(cuqdyn-c
        PUBLIC
        include
)

target_link_libraries(cuqdyn-c
        sacess
)
