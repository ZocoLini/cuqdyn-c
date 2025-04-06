link_directories(
        ${PROJECT_SOURCE_DIR}/sundials/instdir/lib
)

include_directories(
        ../include
        ${PROJECT_SOURCE_DIR}/sundials/instdir/include
)

add_executable(
        bin
        lib.c
        main.c
        lotka_volterra.c
        math.c
        matlab.c
)

target_link_libraries(
        bin
        sundials_cvode
        sundials_nvecserial
        sundials_core
        m
)
