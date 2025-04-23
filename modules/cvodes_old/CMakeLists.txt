FILE(GLOB SRC_C CONFIGURE_DEPENDS src/*.c)

add_library(cvodes_old
        ${SRC_C}
)

target_include_directories(cvodes_old
        PUBLIC
        include
        PRIVATE
        src
)