# Uncertainty Quantification in Dynamic Models of Biological Systems Using Conformal Prediction

This project is a transpilation of the Matlab project 
defined in this [paper](https://zenodo.org/records/13838652).

## Index
  - [Project Structure](#project-structure)
  - [Dependencies](#dependencies)
  - [Building the project](#building-the-project)
  - [Using the CLI](#using-the-cli)
  - [Input files](#input-files)
  - [Dev container](#dev-container)

## Project Structure
The project is structured as follows:
 - `deps/`: Contains the dependencies of the project.
 - `modules/`: Contains the different modules of the project.
   - `cli/`: CLI that enables the use of the cuqdyn-c library.
   - `cuqdyn-c/`: The main library that implements the functionality of the paper project.
   - `cvodes_old/`: Old version of the cvodes library that was used in the sacess library.
   - `dotmat-introspector/`: Console app to introspect the contents of a .mat file.
   - `sacess/`: [External proyect](https://bitbucket.org/DavidPenas/sacess-library) adapted to enable the 
   use of eSS in C.
 - `tests/`: Constains the tests of the cuqdyn-c library.
 - `CUQDyn/`: Contains the original Matlab project.

## Dependencies
- xml2-2.9.1
- matio-2.9.1 (Builded by CMake)
- hdf5-1.8.12 (Builded by CMake)
- gsl-1.14 (Builded by CMake if not present)

## Building the project
The project has a `build.sh` script that builds the project using CMake.
A `build/` directory will be created and the project will be built inside it.
After this, running `test.sh` is a good way to know if the cuqdyn library works as expected.

As an alternative, you can build the project using the following commands:
```bash
mkdir build
cd build
cmake -DCMAKE_TOOLCHAIN_FILE=../toolchain.cmake ..
make -j $(nproc)
````

## Using the CLI
After building using the `build.sh` script, you can execute this command to run the CLI
with example config and data files like this:  

```bash
mkdir output
./build/cli solve \
    -c example-files/lotka_volterra_cuqdyn_config.xml \
    -s example-files/lotka_volterra_ess_config.xml \
    -d example-files/lotka_volterra_paper_data.txt \
    -o output/ \
    -f 0
```

Or, if you compilued using MPI
```bash
mkdir output
./build/cli solve \
    -c example-files/lotka_volterra_cuqdyn_config.xml \
    -s example-files/lotka_volterra_parallel_ess_config.xml \
    -d example-files/lotka_volterra_paper_data.txt \
    -o output/ \
    -f 0
```

After this, the file `output/cuqdyn-results.txt` contains the results of the 
algorithm but reading it as a plain text is not very useful. 
To fix this, you can run: (Needs python3 and matplotlib installed)
```bash
python3 plot.py output/cuqdyn-results.txt
```
This will save a graphic representation for each y(t) in different png files
inside the directory where the results are (output folder in this example).

To get information about all the options the cli supports, you can run the following command:

```bash
./build/cli help
```

Also, you can run 
```bash
./build/cli version
```
to get the version of the cuqdyn-c lib and cli you are using.

## Input files
There are three types of input files needed to run the cli:
  - **eSS Solver config xml:** 
    This file contains the configuration of the eSS solver used in the sacess library. 
    The specifications of this xml and how to build it are in this [link](https://bitbucket.org/DavidPenas/sacess-library/src/main/doc/manual/DOCUMENTATION_SACESS_SOFTWARE.pdf).
  - **cuqdyn config xml:**
    This file contains the configuration of the cuqdyn solver used in the cuqdyn-c library.
    Right now, this file is just needed to define the rtol and atol used by the cvodes library.
    ```xml
    <?xml version="1.0" encoding="UTF-8" ?>

    <cuqdyn-config>
        <tolerances>
            <rtol>1e-8</rtol> <!-- Just one number -->
            <atol>1e-9, 1e-10</atol> <!-- as many as y(x) present in the EDO -->
        </tolerances>
    </cuqdyn-config>
    ```
  - **Data file:**
    The data file containing a mtrix of observed data and the initial value
    needed to solve the ODE. The data file can be a .mat file where the first matrix
    found will be used (`test/data/lotka_volterra_data_homoc_noise_0.10_size_30_data_1.mat`)
    or a txt file written in the following format:
    ```
    # The first row is gonna be used as the initial condition
    31 3 # Matrix dimensions so the parsing is easier
    0 10 5 # Column 1: time, Column 2: y1(t), Column 3: y2(t)
    .
    .
    .
    30 1e1 5e1
    ```
    

## Dev container
There is a definition file for a singularity container + a `dev_container.sh`
script that builds a dev container with all the dependencies needed to build 
the project.
The container doesn't contain a valid python installation 
to use the plot.py script, so this step should be done from the host.