## CUQDyn v2 - last revised Sept-2024
## Author: Alberto Portela, Computational Biology Lab, MBG-CSIC, Pontevedra (Spain)
## Email:  <albertoportela99@gmail.com>

## Description
Matlab software to reproduce the results in:
Portela, A., J.R. Banga, M. Matabuena (2024) Conformal Prediction in Dynamic Biological Systems. arXiv 2409.02644.

## Installation

Requirements:
This software requires Matlab (tested with R2020), plus the Optimization and Parallel Computing Toolboxes.
It also requires the MEIGO toolbox, which is distributed with this software (folder MEIGO64-master).

This software has only been tested using Matlab under Windows 11. Other OS might require changes in the code.
Instructions on how to install the toolbox:
1. Download the latest version from https://zenodo.org/doi/10.5281/zenodo.13644869
2. Unzip the downloaded file in a directory of your choice
3. Add the toolbox folder to the MATLAB path.

## Usage

Below are the instructions to reproduce the results for the different case studies considered in the paper:

- Logistic

The folder "Data_Logistic" contains four different datasets of varying sizes (10, 20, 50, and 100) for testing the algorithms.
A file describing the dataset generation procedure is also provided ("data_generation_log.m") so the user can easily create new
datasets.

The file "CUQDyn1.m" contains the first algorithm, and "CUQDyn2.m" contains the second one. To change the dataset being used,
it is only necessary to adjust the variables "ns" (noise) and "sz" (size of the dataset) to match those of the specific dataset.

There is also a file called "Visualization.m" that allows the user to plot the resulting regions, as well as the true model
and the observed data.

- Lotka-Volterra

The folder "Data_LV" contains three different datasets of varying sizes (30, 60, and 120) for testing the algorithms.
A file describing the dataset generation procedure is also provided ("data_generation_lotka_volterra.m") so the user can easily
create new datasets.

The file "CUQDyn1.m" contains the first algorithm, and "CUQDyn2.m" contains the second one. To change the dataset being used,
it is only necessary to adjust the variables "ns" (noise) and "sz" (size of the dataset) to match those of the specific dataset.

There is also a file called "Visualization.m" that allows the user to plot the resulting regions, as well as the true model
and the observed data.

- Alpha-pinene

The folder "Data_AP" contains a real 9-point dataset for testing the algorithms. 

The file "CUQDyn1.m" contains the first algorithm, and "CUQDyn2.m" contains the second one.

There is also a file called "Visualization.m" that allows the user to plot the resulting regions, as well as the observed data.

- NFKB

The folder "Data_NFKB" contains the dataset used in the paper for testing the algorithms. A file describing the dataset generation
procedure is also provided ("data_generation_NFKB_PE.m") so the user can easily create new datasets.

The file "CUQDyn1.m" contains the first algorithm, and "CUQDyn2.m" contains the second one. To change the dataset being used,
it is only necessary to adjust the variable "ns" (noise) to match the one of the specific dataset.

There is also a file called "Visualization.m" that allows the user to plot the resulting regions, as well as the true model
and the observed data.

## License
GPL-3.0 license

## Disclaimer
Disclaimer
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3 of the License.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/. 
 


