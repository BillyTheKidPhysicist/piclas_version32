# Installation

The following chapter describes the installation procedure on a Linux machine requiring root access. This includes the installation
of required prerequisites, setting up MPI and HDF5. Please note that high-performance clusters usually have a module environment,
where you have to load the appropriate modules instead of compiling them yourself. The module configuration for some of the clusters
used by the research group are given in Chapter {ref}`userguide/cluster_guide:Cluster Guidelines`.
In that case, you can jump directly to the description of the download and installation procedure of PICLas in Section
{ref}`sec:optaining-the-source`.

## Prerequisites
**PICLas** has been used on various Linux distributions in the past. This includes Ubuntu 16.04 LTS and 18.04 LTS, 20.04 LTS
20.10 and 21.04, OpenSUSE 42.1 and CentOS 7.
For a list of tested library version combinations, see Section {ref}`sec:required-libs`.

The suggested packages in this section can be replaced by self compiled versions. The required packages for the Ubuntu Linux
distributions are listed in {numref}`tab:installation_prereqs_ubuntu` and for CentOS Linux in
{numref}`tab:installation_prereqs_centos`.
Under Ubuntu, they can be obtained using the apt environment:

    sudo apt-get install git cmake

```{table} Debian/Ubuntu packages. x: required, o: optional, -: not available
---
name: tab:installation_prereqs_ubuntu
---
|     Package      | Ubuntu 16.04/18.04 |   Ubuntu 20.04   |
| :--------------: | :----------------: | :--------------: |
|       git        |         x          |        x         |
|      cmake       |         x          |        x         |
| cmake-curses-gui |         o          |        o         |
|    liblapack3    |         x          |        x         |
|  liblapack-dev   |         x          |        x         |
|     gfortran     |         x          |        x         |
|       g++        |         x          |        x         |
| mpi-default-dev  |         x          |        x         |
|    zlib1g-dev    |         x          |        x         |
| exuberant-ctags  |         o          |        o         |
|   libmpfr-dev    |                    | x (GCC >= 9.3.0) |
|    libmpc-dev    |                    | x (GCC >= 9.3.0) |
```

and under CentOS via

    sudo yum install git

For extra packages install EPEL and SCL

    sudo yum install epel-release centos-release-scl

```{table} Centos packages. x: required, o: optional, -: not available
---
name: tab:installation_prereqs_centos
---
|     Package     | CentOS 7 |
| :-------------: | :------: |
|       git       |    x     |
|      cmake      |    x     |
|     cmake3      |    x     |
|     libtool     |    x     |
|  ncurses-devel  |    x     |
|  lapack-devel   |    x     |
| openblas-devel  |    x     |
|  devtoolset-9   |    x     |
|       gcc       |    x     |
|     gcc-c++     |    x     |
|     zlib1g      |    x     |
|  zlib1g-devel   |    o     |
| exuberant-ctags |    o     |
|  numactl-devel  |    x     |
| rdma-core-devel |    o     |
|    binutils     |    x     |
|       tar       |    x     |
```

On some systems it may be necessary to increase the size of the stack (part of the memory used to store information about active
subroutines) in order to execute **PICLas** correctly. This is done using the command

    ulimit -s unlimited

from the command line. For convenience, you can add this line to your `.bashrc`.

(sec:required-libs)=
## Required Libraries
The following list contains the **recommended library combinations** for the Intel and GNU compiler in combination with HDF5, OpenMPI, CMake etc.

| PICLas Version | Compiler  |  HDF5  |      MPI      | CMake  |
| :------------: | :-------: | :----: | :-----------: | :----: |
|     2.3.0      | gcc11.2.0 | 1.12.1 | openmpi-4.1.1 | 3.21.3 |
|     2.0.0      | intel19.1 |  1.10  |   impi2019    |  3.17  |

and the **minimum requirements**

| PICLas Version | Compiler  |  HDF5  |      MPI      | CMake |
| :------------: | :-------: | :----: | :-----------: | :---: |
|     2.3.0      | gnu9.2.0  | 1.10.6 | openmpi-3.1.6 | 3.17  |
|     2.0.0      | intel18.1 |  1.10  |   impi2018    | 3.17  |

A full list of all previously tested combinations is found in Chapter {ref}`userguide/appendix:Appendix`. Alternative combinations might work as well, however, have not been tested.

If you are setting-up a fresh system for the simulation with PICLas, we recommend using a Module environment, which can be setup with the provided shell scripts in `piclas/tools/Setup_ModuleEnv`. A description is available here: `piclas/tools/Setup_ModuleEnv/README.md`. This allows you to install and switch between different compiler, MPI and HDF5 versions.

### Installing/setting up GCC

You can install a specific version of the GCC compiler from scratch, if for example the compiler provided by the repositories of your operating systems is too old. If you already have a compiler installed, make sure the environment variables are set correctly as shown at the end of this section. For this purpose, download the GCC source code directly using a mirror website (detailed information and different mirrors can be found here: [GCC mirror sites](https://gcc.gnu.org/mirrors.html))

    wget "ftp://ftp.fu-berlin.de/unix/languages/gcc/releases/gcc-11.2.0/gcc-11.2.0.tar.gz"

After a successful download, make sure to unpack the archive

    tar -xzf gcc-11.2.0.tar.gz

Now you can enter the folder, create a build folder within and enter it

    cd gcc-11.2.0 && mkdir build && cd build

Here, you can configure the installation and create the Makefile. Make sure to adapt your installation path (`--prefix=/home/user/gcc/11.2.0`) before continuing with the following command

    ../configure -v \
    --prefix=/home/user/gcc/11.2.0 \
    --enable-languages=c,c++,objc,obj-c++,fortran \
    --enable-shared \
    --disable-multilib \
    --disable-bootstrap \
    --enable-checking=release \
    --with-sysroot=/ \
    --with-system-zlib

After the Makefile has been generated, you can compile the compiler in parallel, e.g. with 4 cores

    make -j4 2>&1 | tee make.out

and finally install it by

    make install 2>&1 | tee install.out

If you encounter any difficulties, you can submit an issue on GitHub attaching the `make.out` and/or `install.out` files, where the console output is stored. To make sure that the installed compiler is also utilized by CMake, you have to set the environment variables, again making sure to use your installation folder and the correct version

    export CC = /home/user/gcc/11.2.0/bin/gcc
    export CXX = /home/user/gcc/11.2.0/bin/g++
    export FC = /home/user/gcc/11.2.0/bin/gfortran
    export PATH="/home/user/gcc/11.2.0/include/c++/11.2.0:$PATH"
    export PATH="/home/user/gcc/11.2.0/bin:$PATH"
    export LD_LIBRARY_PATH="/home/user/gcc/11.2.0/lib64:$LD_LIBRARY_PATH"

For convenience, you can add these lines to your `.bashrc`.

(sec:installing-mpi)=
### Installing/setting up OpenMPI

You can install a specific version of OpenMPI from scratch, using the same compiler that will be used for the code installation. If you already have OpenMPI installed, make sure the environment variables are set correctly as shown at the end of this section. First, download the OpenMPI source code either from the website [https://www.open-mpi.org/](https://www.open-mpi.org/) or directly using the following command:

    wget "https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-4.1.1.tar.gz"

Unpack it, enter the folder, create a build folder and enter it (procedure analogous to the GCC installation). For the configuration, utilize the following command, which specifies the compiler to use and the installation directory with `--prefix=/home/user/openmpi/4.1.1`

    ../configure --prefix=/home/user/openmpi/4.1.1 CC=$(which gcc) CXX=$(which g++) FC=$(which gfortran)

After the Makefile has been generated, you can compile OpenMPI in parallel, e.g. with 4 cores

    make -j4 2>&1 | tee make.out

and finally install it by

    make install 2>&1 | tee install.out

If you encounter any difficulties, you can submit an issue on GitHub attaching the `make.out` and/or `install.out` files, where the console output is stored. To make sure that the installed OpenMPI is also utilized by CMake, you have to set the environment variables, again making sure to use your installation folder and the correct version

    export MPI_DIR=/home/user/openmpi/4.1.1
    export PATH="/home/user/openmpi/4.1.1/bin:$PATH"
    export LD_LIBRARY_PATH="/home/user/openmpi/4.1.1/lib:$LD_LIBRARY_PATH"

For convenience, you can add these lines to your `.bashrc`.

(sec:hdf5-installation)=
### Installing/setting up HDF5

An available installation of HDF5 can be utilized with PICLas. This requires properly setup environment variables and the compilation of HDF5 during the PICLas compilation has to be turned off (`LIBS_BUILD_HDF5 = OFF`, as per default). If this option is enabled, HDF5 will be downloaded and compiled. However, this means that every time a clean compilation of PICLas is performed, HDF5 will be recompiled. It is preferred to either install HDF5 on your system locally or utilize the packages provided on your cluster.

You can install a specific version of HDF5 from scratch, using the same compiler and MPI configuration that will be used for the code installation. If you already have HDF5 installed, make sure the environment variables are set correctly as shown at the end of this section. First, download HDF5 from [HDFGroup (external website)](https://portal.hdfgroup.org/display/support/Downloads) or download it directly 

    wget "https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-1.12/hdf5-1.12.1/src/hdf5-1.12.1.tar.gz"

and extract it, enter the folder, create a build folder and enter it

    tar -xvf hdf5-1.12.1.tar.gz && cd hdf5-1.12.1 && mkdir -p build && cd build

Afterwards, configure HDF5 and specify the installation directory with `--prefix=/home/user/hdf5/1.12.1`

    ../configure --prefix=/home/user/hdf5/1.12.1 --with-pic --enable-fortran --enable-fortran2003 --disable-shared --enable-parallel CC=$(which mpicc) CXX=$(which mpicxx) FC=$(which mpifort)

After the Makefile has been generated, you can compile HDF5 in parallel, e.g. with 4 cores

    make -j4 2>&1 | tee make.out

and finally install it by

    make install 2>&1 | tee install.out

If you encounter any difficulties, you can submit an issue on GitHub attaching the `make.out` and/or `install.out` files, where the console output is stored. To make sure that the installed HDF5 is also utilized by CMake, you have to set the environment variables, again making sure to use your installation folder and the correct version

    export HDF5_DIR = /home/user/hdf5/1.12.1
    export HDF5_ROOT = /home/user/hdf5/1.12.1
    export PATH="/home/user/hdf5/1.12.1/include:$PATH"
    export PATH="/home/user/hdf5/1.12.1/bin:$PATH"
    export LD_LIBRARY_PATH="/home/user/hdf5/1.12.1/lib:$LD_LIBRARY_PATH"

For convenience, you can add these lines to your `.bashrc`.

(sec:optaining-the-source)=
## Obtaining the source

The **PICLas** repository is available at GitHub. To obtain the most recent version you have two possibilities:

* Clone the **PICLas** repository from Github

    ````
    git clone https://github.com/piclas-framework/piclas.git
    ````

* Download **PICLas** from Github:

    ````
    wget https://github.com/piclas-framework/piclas/archive/master.tar.gz
    tar xzf master.tar.gz
    ````

Note that cloning **PICLas** from GitHub may not be possible on some machines, as e.g. the HLRS at the University of Stuttgart
restricts internet access. Please refer to section {ref}`sec:cloning-at-hlrs` of this user guide.

## Compiling the code

To compile the code, open a terminal, change into the **PICLas** directory and create a new subdirectory. Use the CMake curses interface (requires the `cmake-curses-gui` package on Ubuntu) to configure and generate the Makefile

    mkdir build && cd build
    ccmake ..

Here you will be presented with the graphical user interface, where you can navigate with the arrow keys. Before you can generate a Makefile, you will have to configure with `c`, until the generate option `g` appears at the bottom of the terminal. Alternatively, you can configure the code directly by supplying the compiler flags

    cmake -DPICLAS_TIMEDISCMETHOD=DSMC ..

For a list of all compiler options visit Section {ref}`sec:compiler-options`. After a successful generation of the Makefile, compile the code in parallel (e.g. with 4 cores) using

    make -j4 2>&1 | tee piclas_make.out

Finally, the executables **PICLas** and **piclas2vtk** are contained in your **PICLas** directory in `build/bin/`. If you encounter any difficulties, you can submit an issue on GitHub attaching the `piclas_make.out` file, where the console output is stored.

(sec:directory-paths)=
### Directory paths

In the following, we write `$PICLASROOT` as a substitute for the path to the **PICLas** repository. Please replace `$PICLASROOT`
in all following commands with the path to your **PICLas** repository *or* add an environment variable `$PICLASROOT`.

Furthermore, the path to executables is omitted in the following, so for example, we write `piclas` instead of
`$PICLASROOT/build/bin/piclas`.

In order to execute a file, you have to enter the full path to it in the terminal. There are two different ways to enable typing
`piclas` instead of the whole path (do not use both at the same time!)

1. You can add an alias for the path to your executable. Add a command of the form

~~~~~~~
alias piclas='$PICLASROOT/build/bin/piclas'
~~~~~~~

to the bottom of the file `~/.bashrc`. Source your `~/.bashrc` afterwards with

~~~~~~~
. ~/.bashrc
~~~~~~~

2. You can add the **PICLas** binary directory to your `$PATH` environment variable by adding

~~~~~~~
export PATH=$PATH:$PICLASROOT/build/bin
~~~~~~~

to the bottom of the file `~/.bashrc` and sourcing your `~/.bashrc` afterwards.

Now you are ready for the utilization of **PICLas**.