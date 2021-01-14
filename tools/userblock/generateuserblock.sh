#!/bin/bash
#************************************************************************************
#
# Author:       Thomas Bolemann
# Institution:  Inst. of Aero- and Gasdynamics, University of Stuttgart
# Date:         07.07.2016
#
# Description:  This script will generate a userblock file to be appended to
#               executables or simulation results enabling the exact rebuilding of
#               of the simulation code, which was used to generate those results.
#               A patch to the remote Git branch of the current code is generated
#               or to the master, if the branch does not exist on the remote.
# 
#************************************************************************************

# $1: CMAKE_RUNTIME_OUTPUT_DIRECTORY
# $2: CMAKE_CACHEFILE_DIR
# $3: CMAKE_CACHE_MAJOR_VERSION.CMAKE_CACHE_MINOR_VERSION.CMAKE_CACHE_PATCH_VERSION
# $4: .f90 file containing MajorVersion, MinorVersion and PatchVersion of PICLas

if [ ! -d "$1" ]; then
  exit 1;
fi
if [ ! -d "$2" ]; then
  exit 1;
fi

# get branch name (only info)
BRANCHNAME=$(git rev-parse --abbrev-ref HEAD)
PARENTNAME=$BRANCHNAME
PARENTCOMMIT=$(git show-ref | grep "origin/$BRANCHNAME$" | cut -b -40)

if [ -z "$PARENTCOMMIT" ]; then
  LOCBRANCHNAME=$BRANCHNAME
  # recursively search for parent branch
  FOUND=0
  while [ $FOUND -eq 0 ]; do
    # get commit on server, where branch started
    COLUMN=$((    $(git show-branch | grep '^[^\[]*\*'  | head -1 | cut -d* -f1 | wc -c) - 1 )) 
    START_ROW=$(( $(git show-branch | grep -n "^[\-]*$" | cut -d: -f1) + 1 )) 
    PARENTNAME=$(   git show-branch | tail -n +$START_ROW | grep -v "^[^\[]*\[$LOCBRANCHNAME" | grep "^.\{$COLUMN\}[^ ]" | head -n1 | sed 's/.*\[\(.*\)\].*/\1/' | sed 's/[\^~].*//')
    if [ -z "$PARENTNAME" ]; then
      break
    fi
  
    PARENTCOMMIT=$(git show-ref | grep "origin/$PARENTNAME$" | cut -b -40)
    if [ -z "$PARENTCOMMIT" ]; then
      LOCBRANCHNAME=$PARENTNAME 
    else
      FOUND=1
      break
    fi
  done

  if [ $FOUND -eq 0 ]; then
    PARENTNAME='master'
    PARENTCOMMIT=$(git rev-parse origin/master)
    echo "WARNING: Could not find parent commit, creating userblock diff to master."
  fi
fi

cd "$1"
echo "{[( CMAKE )]}"               >  userblock.txt
cat configuration.cmake            >> userblock.txt
echo "{[( GIT BRANCH )]}"          >> userblock.txt
echo "$BRANCHNAME"                 >> userblock.txt
GITCOMMIT=$(git rev-parse HEAD)
echo "$GITCOMMIT"                  >> userblock.txt

# Reference is the start commit, which is either identical to
# the branch, if it exists on the remote or points to the first
# real parent in branch history available on remote.
echo "{[( GIT REFERENCE )]}"       >> userblock.txt
echo "$PARENTNAME"                 >> userblock.txt
echo $PARENTCOMMIT                 >> userblock.txt

#echo "{[( GIT FORMAT-PATCH )]}"    >> userblock.txt
## create format patch containing log info for commit changes
## PARENT should be identical to origin
#git format-patch $PARENTCOMMIT..HEAD --minimal --stdout >> $1/userblock.txt

# Also store binary changes in diff
echo "{[( GIT DIFF )]}"            >> userblock.txt
# commited changes
git diff -p $PARENTCOMMIT..HEAD    >> userblock.txt
# uncommited changes
git diff -p                        >> userblock.txt

echo "{[( GIT URL )]}"             >> userblock.txt
git config --get remote.origin.url >> userblock.txt

# change directory to cmake cache dir
if [ -d "$2/CMakeFiles" ]; then
  cd "$2/CMakeFiles"
  # copy compile flags of the piclas(lib) to userblock
  echo "{[( libpiclasstatic.dir/flags.make )]}" >> $1/userblock.txt
  cat libpiclasstatic.dir/flags.make            >> $1/userblock.txt
  echo "{[( libpiclasshared.dir/flags.make )]}" >> $1/userblock.txt
  cat libpiclasshared.dir/flags.make            >> $1/userblock.txt
  echo "{[( piclas.dir/flags.make )]}"          >> $1/userblock.txt
  cat piclas.dir/flags.make                     >> $1/userblock.txt
fi

# change directory to actual cmake version
if [ -d "$3" ]; then
  cd "$3"
  # copy detection of compiler to userblock
  echo "{[( COMPILER VERSIONS )]}" >> $1/userblock.txt
  cat CMakeFortranCompiler.cmake   >> $1/userblock.txt
fi

# write PICLas version to userblock
if [ -f "$4" ]; then
  echo "{[( PICLAS VERSION )]}" >> $1/userblock.txt
  PICLAS_MAJOR_VERSION=$(grep "INTEGER.*PARAMETER.*MajorVersion.*\=" "$4" | cut -d "=" -f2 | cut -f1 -d! | sed 's/[[:space:]]//g')
  PICLAS_MINOR_VERSION=$(grep "INTEGER.*PARAMETER.*MinorVersion.*\=" "$4" | cut -d "=" -f2 | cut -f1 -d! | sed 's/[[:space:]]//g')
  PICLAS_MATCH_VERSION=$(grep "INTEGER.*PARAMETER.*PatchVersion.*\=" "$4" | cut -d "=" -f2 | cut -f1 -d! | sed 's/[[:space:]]//g')
  echo "$PICLAS_MAJOR_VERSION.$PICLAS_MINOR_VERSION.$PICLAS_MATCH_VERSION" >> $1/userblock.txt
fi

# write cpu info to userblock
if [ -f "/proc/cpuinfo" ]; then
  echo "{[( CPU INFO )]}" >> $1/userblock.txt
  THREADS=$(grep -c ^processor /proc/cpuinfo)
  echo "Total number of processors/threads given in /proc/cpuinfo: ${THREADS}" >> $1/userblock.txt
  sed '/^$/Q' /proc/cpuinfo | sed -e 's/\t//g' >> $1/userblock.txt
fi

cd "$1" # go back to the runtime output directory
# Compress the userblock
tar cJf userblock.tar.xz userblock.txt

# Build the module
objcopy -I binary -O elf64-x86-64 -B i386 --redefine-sym _binary_userblock_tar_xz_start=userblock_start --redefine-sym _binary_userblock_tar_xz_end=userblock_end --redefine-sym _binary_userblock_tar_xz_size=userblock_size userblock.tar.xz userblock.o
rm userblock.tar.xz
