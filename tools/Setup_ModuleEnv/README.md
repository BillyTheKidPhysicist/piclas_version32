# About
These scripts help setting up a module environment for development with piclas, which is used via

    module load X

after everything has been installed (CMake, GCC, Open MPI, HDF and possibly ParaView) in the same way a HPC cluster may provide its pre-installed packages to the user.

# Installation

To execute all scripts as super user, run and/or change to the script files directory

    sudo -s
    cd /path/to/piclas/tools

Note that all scripts (5-8) can be re-run with the argument `-r` or `-rerun`.
This cleans the created module file and build directory of the version currently build and rebuilds it.

## 1. Install the basic packages depending on the OS (Ubuntu is assumed here)

       sudo ./InstallPackagesUbuntu16.sh
       sudo ./InstallPackagesUbuntu20.sh
       sudo ./InstallPackagesUbuntu21.sh

   and if you have a server that has been setup with only basic packages, the following might be required
   
       sudo ./InstallPackagesServer.sh

## 2. Module Environment from [https://sourceforge.net/projects/modules/files/](https://sourceforge.net/projects/modules/files/)

       sudo ./InstallModules.sh


   reboot and maybe second time `./InstallModules.sh` is needed if `module list` does not work and returns `command not found: module`.

## 3. CMake from [https://github.com/Kitware/CMake/releases/](https://github.com/Kitware/CMake/releases/)
       sudo ./InstallCMake.sh
   
## 4. GCC Compiler from [ftp://ftp.fu-berlin.de/unix/languages/gcc/releases](ftp://ftp.fu-berlin.de/unix/languages/gcc/releases)
       sudo ./InstallGCC.sh
   
## 5. Open MPI from [https://www.open-mpi.org/software/ompi/v4.1/](https://www.open-mpi.org/software/ompi/v4.1/)
       sudo ./InstallMPIallCOMPILERS.sh
   
## 6. HDF5 from [https://support.hdfgroup.org/ftp/HDF5/releases/](https://support.hdfgroup.org/ftp/HDF5/releases/)
       sudo ./InstallHDF5.sh

## 7. ParaViewfrom [https://www.paraview.org/download/](https://www.paraview.org/download/)
The installation of ParaView is not mandatory for piclas/hopr. The pre-requisites for Ubuntu are installed via

       sudo ./InstallPackagesParaView.sh

and Paraview itself is installed via

      sudo ./InstallParaview.sh

