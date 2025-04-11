## CUQDyn v2 - last revised Sept-2024
## Author: Alberto Portela, Computational Biology Lab, MBG-CSIC, Pontevedra (Spain)
## Email:  <albertoportela99@gmail.com>

## Description
R software to reproduce the results in:
Portela, A., J.R. Banga, M. Matabuena (2024) Conformal Prediction in Dynamic Biological Systems. arXiv 2409.02644.

## Installation

Requirements:
This software requieres R (tested with version 4.2.2), plus the following list of packages that can be installed
using "intall.packages("name_of_the_package")" and then loaded using "library(name_of_the_package).

-StanHeaders
-rstan
-dplyr
-tidyr
-ggplot2
-R.matlab
-bayesplot
-deSolve

This software has only been tested using RStudio under Windows 11. Other OS might require changes in the code.
Instructions on how to install the toolbox:
1. Download the latest version from https://zenodo.org/doi/10.5281/zenodo.13644869
2. Unzip the downloaded file in a directory of your choice
3. Add the toolbox folder to the R path.

## Usage

Every case study has a folder with a .R and a .stan files. The resulting regions obtained by using STAN can be visualized
using the code at the last 30 lines of the corresponding .R file.

In every case study folder there is a dataset for testing the results.
For the NFKB case study, despite testing different priors, the parameter estimation for the dynamic system was unsatisfactory,
likely due to the lack of model identifiability.

## License
GPL-3.0 license

## Disclaimer
Disclaimer
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3 of the License.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/. 
 


