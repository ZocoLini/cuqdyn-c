set(CMAKE_C_COMPILER mpicc)
set(CMAKE_CXX_COMPILER mpic++)
set(CMAKE_Fortran_COMPILER mpifort)
set(CMAKE_C_FLAGS "-O3 -cpp -DGNU -fPIC -no-pie -DOPENMP -DMPI2 -fopenmp")
set(CMAKE_Fortran_FLAGS "-O3 -cpp -DGNU  -fallow-argument-mismatch -std=gnu -DOPENMP -DMPI2 -DGNU -fopenmp")

set(MISQP_LIBRARY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/deps/misqp/gnu")
set(LIBRARIES mpi)