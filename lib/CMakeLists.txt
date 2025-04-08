file(GLOB LIB_SRC CONFIGURE_DEPENDS src/*.c)

add_library(
        lib
        ${LIB_SRC}
)

target_include_directories(lib
        PUBLIC
        include
        ${PROJECT_SOURCE_DIR}/deps/cvode-7.2.1/include
)

target_link_directories(lib
        PUBLIC ${PROJECT_SOURCE_DIR}/deps/cvode-7.2.1/lib
)

target_link_libraries(
        lib
        sundials_cvode
        sundials_nvecserial
        sundials_core
)
