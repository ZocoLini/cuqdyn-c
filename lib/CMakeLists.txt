file(GLOB LIB_SRC CONFIGURE_DEPENDS src/*.c)

add_library(
        lib
        ${LIB_SRC}
        src/edo_solver.c
)

target_include_directories(lib
        PUBLIC
        include
        ${PROJECT_SOURCE_DIR}/sundials/instdir/include
)

target_link_directories(lib
        PUBLIC ${PROJECT_SOURCE_DIR}/sundials/instdir/lib
)

target_link_libraries(
        lib
        sundials_cvode
        sundials_nvecserial
        sundials_core
)
