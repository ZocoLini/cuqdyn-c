# Uncertainty Quantification in Dynamic Models of Biological Systems Using Conformal Prediction

## Prerequisites
- matio:
```bash
  sudo apt-get install libmatio-dev
```

## Modifications to the original sacess-library code
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
