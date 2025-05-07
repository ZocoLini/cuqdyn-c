# TODO: If the packages are not found, build them from source
find_package(HDF5 REQUIRED)
find_package(GSL REQUIRED)

set(HDF5_INCLUDE_DIR "/usr/include/hdf5/serial" CACHE PATH "Path to the dir that contains hdf5.h")
if(EXISTS "${HDF5_INCLUDE_DIR}/hdf5.h")
    include_directories(${HDF5_INCLUDE_DIR})
else()
    message(FATAL_ERROR "hdf5.h not found in ${HDF5_INCLUDE_DIR}")
endif()

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
        include
        benchmarks
        libAMIGO/include

        include/method_module_fortran

        ${HDF5_INCLUDE_DIR}
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
        misqp # Needed by modules/sacess/src/method_module_fortran/eSS/localsolvers/misqp/misqp_interface.f90

        GSL::gsl
        hdf5::hdf5

        ${LIBRARIES}
)