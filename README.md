# Uncertainty Quantification in Dynamic Models of Biological Systems Using Conformal Prediction

This project is a transpilation of the Matlab project 
defined in this [paper](https://zenodo.org/records/13838652).

## Project Structure
The project is structured as follows:
 - `deps/`: Contains the dependencies of the project.
 - `modules/`: Contains the different modules of the project.
   - `cli/`: CLI that enables the use of the cuqdyn-c library.
   - `cuqdyn-c/`: The main library that implements the functionality of the paper project.
   - `cvodes_old/`: Old version of the cvodes library that was used in the sacess library.
   - `dotmat-introspector/`: Console app to introspect the contents of a .mat file.
   - `sacess/`: [External proyect](https://bitbucket.org/DavidPenas/sacess-library) adapted to enable the 
   use of the eSS in C.
 - `tests/`: Constains the tests of the cuqdyn-c library.
 - `CUQDyn/`: Contains the original Matlab project.

## Building the project

## Using the CLI
After building using the `build.sh` script, you can execute this command to run the CLI
with example config and data files like this:  

```bash
./build/cli solve \
    -c example-files/lotka_volterra_cuqdyn_config.xml \
    -s example-files/lotka_volterra_ess_config.xml \
    -d example-files/lotka_volterra_paper_data.txt \
    -o output \
    -f 0
```

## Limitations of the original sacess-library code
### Output path
- The output path should contain a '/' at some point or the code at
  modules/sacess/src/input_module/input_module.c line 696 will try to copy from a NULL

## Modifications to the original sacess-library code
### Projects struture
- The original code was modified to use the CMake build system.
- cvodes was extracted and used as a submodule.
- All the includes were modified to be relative to the include directory they are in.
- The dependencies were moved into the deps directory.

### Logic
- Function reorder_best() in modules/sacess/src/method_module/common_solver_operations.c*

### Memory leaks
#### File: modules/sacess/src/method_module/evaluationinterface.c
- Lines 134-135: Unnecesary memory allocation
- Line 74: Unnecesary memory allocation
- Line 236: Unnecesary memory allocation
#### File: modules/sacess/src/method_module/common_solver_operations.c
- Line 612: Unnecesary memory allocation
#### File: modules/sacess/src/input_module/input_AMIGO.c
- Line 521: Unnecesary memory allocation
#### File: modules/sacess/src/input_module/input_module.c
- Line 933: Unnecesary memory allocation
- Line 954: Unnecesary memory allocation
- Line 975: Unnecesary memory allocation
- Line 997: Unnecesary memory allocation 
- Line 61: Function returning after (possible) more than one allocation without freeing
- The whole file calls extract_element_uniq(...), function that allocates memory but this memory is never freed.

### Obtaining the xbest values
#### File: modules/sacess/src/output/output.c
- Line 2314: Added result->bestx_value[i] = xbest[i]; to return the xbest values that are printed