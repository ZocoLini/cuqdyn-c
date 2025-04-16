file(GLOB SRC_C CONFIGURE_DEPENDS
        src/input_module/*.c
        src/output/*.c
        src/structure_data/*.c
        src/method_module/*.c
        src/method_module/DE/*.c
        src/method_module/eSS/*.c
        src/*.c

        benchmarks/bbob/*.c
        benchmarks/customized/*.c

        libAMIGO/src/src_amigo/*.c
        libAMIGO/src/src_de/*.c
        libAMIGO/src/src_fullC/*.c
        libAMIGO/src/src_julia/*.c
        libAMIGO/src/src_SRES/*.c
)

file(GLOB SRC_FORTRAN CONFIGURE_DEPENDS
        src/method_module_fortran/eSS/*.f90
        src/method_module_fortran/eSS/localsolvers/*.f90
        src/method_module_fortran/eSS/localsolvers/dhc/*.f90
        src/method_module_fortran/eSS/localsolvers/misqp/*.f90
        src/method_module_fortran/eSS/localsolvers/nl2sol/*.f90
)

add_library(sacess
        ${SRC_C}
        ${SRC_FORTRAN}
)

target_include_directories(sacess
        PUBLIC
        include
        benchmarks

        PRIVATE
        libAMIGO/include

        include/method_module_fortran

        ${PROJECT_SOURCE_DIR}/deps/gsl-1.14/include
        ${PROJECT_SOURCE_DIR}/deps/libxml2/include
        ${PROJECT_SOURCE_DIR}/deps/hdf5-1.8.12/include
)

target_link_directories(sacess
        PRIVATE
        ${PROJECT_SOURCE_DIR}/deps/gsl-1.14/lib
        ${PROJECT_SOURCE_DIR}/deps/libxml2/lib
        ${PROJECT_SOURCE_DIR}/deps/hdf5-1.8.12/lib
)

target_link_libraries(sacess
        # ${LIBS}
        # ${CLIBS}
        # ${FLIBS}
        cvodes_old
)