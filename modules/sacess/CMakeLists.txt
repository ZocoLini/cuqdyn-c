execute_process(
        COMMAND bash ${CMAKE_SOURCE_DIR}/scripts/get_module_version.sh sacess
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_VERSION
        RESULT_VARIABLE TAG_RESULT
        OUTPUT_STRIP_TRAILING_WHITESPACE
)

if (NOT TAG_RESULT EQUAL 0 OR GIT_VERSION STREQUAL "")
    set(GIT_VERSION "dev")
endif ()

configure_file(
        include/sacess_version.in.h
        ${PROJECT_SOURCE_DIR}/modules/sacess/generated/sacess_version.h
)

message(STATUS "SACESS_C_VERSION: ${GIT_VERSION}")
add_definitions(-DSACESS_C_VERSION=\"${GIT_VERSION}\")

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
        src/method_module_fortran/eSS/localsolvers/nl2sol/src_nl2sol/*.f
)

add_library(sacess
        ${SRC_C}
        ${SRC_FORTRAN}
)

target_include_directories(sacess
        PUBLIC
        generated
        include
        benchmarks
        libAMIGO/include

        include/method_module_fortran

        ${GSL_INCLUDE_DIR}

        ${hdf5_SOURCE_DIR}/src
        ${hdf5_BINARY_DIR}

        ${PROJECT_SOURCE_DIR}/deps/xml2-2.9.1/include
)

target_link_directories(sacess
        PUBLIC
        ${PROJECT_SOURCE_DIR}/deps/xml2-2.9.1/lib
        ${MISQP_LIBRARY_DIR}
)

target_link_libraries(sacess
        PUBLIC
        cvodes_old
        xml2

        # Needed by modules/sacess/src/method_module_fortran/eSS/localsolvers/misqp/misqp_interface.f90
        misqp

        ${GSL_LIBRARY}
        hdf5

        ${LIBRARIES}
)
