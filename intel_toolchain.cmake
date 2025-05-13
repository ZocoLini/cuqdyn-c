set(CMAKE_C_COMPILER icc)
set(CMAKE_Fortran_COMPILER ifort)
set(CMAKE_C_FLAGS "-O3 -ipo -xHost -DINTEL -diag-disable=10441")
set(CMAKE_Fortran_FLAGS "-O3 -ipo -xHost -fpp -DEXPORT -DINTEL")

set(MISQP_LIBRARY_DIR "${PROJECT_SOURCE_DIR}/deps/misqp/intel")
set(LIBRARIES ifcore)