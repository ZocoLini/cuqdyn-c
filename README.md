# Uncertainty Quantification in Dynamic Models of Biological Systems Using Conformal Prediction

## Prerequisites
- matio and openmpi
```bash
  sudo apt-get install -y libmatio-dev
  sudo apt install -y openmpi-bin libopenmpi-dev
```

## Modifications to the original sacess-library code
### Projects struture
- The original code was modified to use the CMake build system.
- cvodes was extracted and used as a submodule.
- All the includes were modified to be relative to the include directory they are in.
- The dependencies were moved into the deps directory.

### Memory leaks
#### File: sacess/src/method_module/evaluationinterface.c
- Lines 134-135: Unnecesary allocation of memory
- Line 74: Unnecesary allocation of memory
- Line 236: Unnecesary allocation of memory

### Obtaining the xbest values
#### File: sacess/src/method_module_fortran/eSS/scattersearch.f90
- Line 438: Commented so the xbest is not freed
#### File: sacess/src/method_module_fortran/eSS/acessdist.f90
- Line 590: Commented so the xbest is not freed
#### File: sacess/src/method_module_fortran/eSS/cess.f90
- Line 690: Commented so the xbest is not freed
#### File: sacess/src/method_module_fortran/eSS/essm.f90
- Line 575: Commented so the xbest is not freed
#### File: sacess/src/method_module_fortran/eSS/sacess.f90
- Line 652: Commented so the xbest is not freed

#### File: sacess/src/output/output.c
- Line 2312: Added result->bestx_value = xbest; to return the xbest values that are printed
