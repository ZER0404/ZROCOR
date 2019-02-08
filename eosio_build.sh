#!/bin/bash
##########################################################################
# This is the EOSIO automated install script for Linux and Mac OS.
# This file was downloaded from https://github.com/EOSIO/eos
#
# Copyright (c) 2017, Respective Authors all rights reserved.
#
# After June 1, 2018 this software is available under the following terms:
#
# The MIT License
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# https://github.com/EOSIO/eos/blob/master/LICENSE
##########################################################################

VERSION=2.0 # Build script version
CMAKE_BUILD_TYPE=Release
export DISK_MIN=20
DOXYGEN=false
ENABLE_COVERAGE_TESTING=false
CORE_SYMBOL_NAME="SYS"
START_MAKE=true

TIME_BEGIN=$( date -u +%s )
txtbld=$(tput bold)
bldred=${txtbld}$(tput setaf 1)
txtrst=$(tput sgr0)

export SRC_LOCATION=${HOME}/src
export OPT_LOCATION=${HOME}/opt
export VAR_LOCATION=${HOME}/var
export ETC_LOCATION=${HOME}/etc
export BIN_LOCATION=${HOME}/bin
export DATA_LOCATION=${HOME}/data
export CMAKE_VERSION_MAJOR=3
export CMAKE_VERSION_MINOR=13
export CMAKE_VERSION_PATCH=2
export CMAKE_VERSION=${CMAKE_VERSION_MAJOR}.${CMAKE_VERSION_MINOR}.${CMAKE_VERSION_PATCH}
export MONGODB_VERSION=3.6.3
export MONGODB_ROOT=${OPT_LOCATION}/mongodb-${MONGODB_VERSION}
export MONGODB_CONF=${ETC_LOCATION}/mongod.conf
export MONGODB_LOG_LOCATION=${VAR_LOCATION}/log/mongodb
export MONGODB_LINK_LOCATION=${OPT_LOCATION}/mongodb
export MONGODB_DATA_LOCATION=${DATA_LOCATION}/mongodb
export MONGO_C_DRIVER_VERSION=1.13.0
export MONGO_C_DRIVER_ROOT=${SRC_LOCATION}/mongo-c-driver-${MONGO_C_DRIVER_VERSION}
export MONGO_CXX_DRIVER_VERSION=3.4.0
export MONGO_CXX_DRIVER_ROOT=${SRC_LOCATION}/mongo-cxx-driver-r${MONGO_CXX_DRIVER_VERSION}
export BOOST_VERSION_MAJOR=1
export BOOST_VERSION_MINOR=67
export BOOST_VERSION_PATCH=0
export BOOST_VERSION=${BOOST_VERSION_MAJOR}_${BOOST_VERSION_MINOR}_${BOOST_VERSION_PATCH}
export BOOST_ROOT=${SRC_LOCATION}/boost_${BOOST_VERSION}
export BOOST_LINK_LOCATION=${OPT_LOCATION}/boost
export LLVM_VERSION=release_40
export LLVM_ROOT=${OPT_LOCATION}/llvm
export LLVM_DIR=${LLVM_ROOT}/lib/cmake/llvm
export DOXYGEN_VERSION=1_8_14
export DOXYGEN_ROOT=${SRC_LOCATION}/doxygen-${DOXYGEN_VERSION}
export TINI_VERSION=0.18.0

# Setup directories
mkdir -p $SRC_LOCATION
mkdir -p $OPT_LOCATION
mkdir -p $VAR_LOCATION
mkdir -p $BIN_LOCATION
mkdir -p $VAR_LOCATION/log
mkdir -p $ETC_LOCATION
mkdir -p $MONGODB_LOG_LOCATION
mkdir -p $MONGODB_DATA_LOCATION

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ "${CURRENT_DIR}" == "${PWD}" ]; then
   BUILD_DIR="${PWD}/build"
else
   BUILD_DIR="${PWD}"
fi

# Use current directory's tmp directory if noexec is enabled for /tmp
if (mount | grep "/tmp " | grep --quiet noexec); then
      mkdir -p $CURRENT_DIR/tmp
      TEMP_DIR="${CURRENT_DIR}/tmp"
      rm -rf $CURRENT_DIR/tmp/*
else # noexec wasn't found
      TEMP_DIR="/tmp"
fi

function usage()
{
   printf "Usage: %s \\n[Build Option -o <Debug|Release|RelWithDebInfo|MinSizeRel>] \\n[CodeCoverage -c] \\n[Doxygen -d] \\n[CoreSymbolName -s <1-7 characters>] \\n[Avoid Compiling -a]\\n\\n" "$0" 1>&2
   exit 1
}

if [[ $1 == "noninteractive" ]]; then
  NONINTERACTIVE=1
else
  NONINTERACTIVE=0
fi

if [ $# -ne 0 ]; then
   while getopts ":cdo:s:ah" opt; do
      case "${opt}" in
         o )
            options=( "Debug" "Release" "RelWithDebInfo" "MinSizeRel" )
            if [[ "${options[*]}" =~ "${OPTARG}" ]]; then
               CMAKE_BUILD_TYPE="${OPTARG}"
            else
               printf "\\nInvalid argument: %s\\n" "${OPTARG}" 1>&2
               usage
               exit 1
            fi
         ;;
         c )
            ENABLE_COVERAGE_TESTING=true
         ;;
         d )
            DOXYGEN=true
         ;;
         s)
            if [ "${#OPTARG}" -gt 7 ] || [ -z "${#OPTARG}" ]; then
               printf "\\nInvalid argument: %s\\n" "${OPTARG}" 1>&2
               usage
               exit 1
            else
               CORE_SYMBOL_NAME="${OPTARG}"
            fi
         ;;
         a)
            START_MAKE=false
         ;;
         h)
            usage
            exit 1
         ;;
         \? )
            printf "\\nInvalid Option: %s\\n" "-${OPTARG}" 1>&2
            usage
            exit 1
         ;;
         : )
            printf "\\nInvalid Option: %s requires an argument.\\n" "-${OPTARG}" 1>&2
            usage
            exit 1
         ;;
         * )
            usage
            exit 1
         ;;
      esac
   done
fi

if [ ! -d "${CURRENT_DIR}/.git" ]; then
   printf "\\nThis build script only works with sources cloned from git\\n"
   printf "Please clone a new eos directory with 'git clone https://github.com/EOSIO/eos --recursive'\\n"
   printf "See the wiki for instructions: https://github.com/EOSIO/eos/wiki\\n"
   exit 1
fi

pushd "${CURRENT_DIR}" &> /dev/null

STALE_SUBMODS=$(( $(git submodule status --recursive | grep -c "^[+\-]") ))
if [ $STALE_SUBMODS -gt 0 ]; then
   printf "\\ngit submodules are not up to date.\\n"
   printf "Please run the command 'git submodule update --init --recursive'.\\n"
   exit 1
fi

printf "\\nBeginning build version: %s\\n" "${VERSION}"
printf "%s\\n" "$( date -u )"
printf "User: %s\\n" "$( whoami )"
# printf "git head id: %s\\n" "$( cat .git/refs/heads/master )"
printf "Current branch: %s\\n" "$( git rev-parse --abbrev-ref HEAD )"

ARCH=$( uname )
printf "\\nARCHITECTURE: %s\\n" "${ARCH}"

popd &> /dev/null

export CPATH=$HOME/include:/usr/include/llvm4.0:$CPATH
export LD_LIBRARY_PATH=$HOME/lib:$HOME/lib64:$HOME/opt/llvm/lib:$LD_LIBRARY_PATH
export CMAKE_MODULE_PATH=$HOME/lib/cmake
if [ "$ARCH" == "Linux" ]; then
   export PATH=$HOME/bin:$PATH:$HOME/opt/mongodb/bin:$HOME/opt/llvm/bin
   export OS_NAME=$( cat /etc/os-release | grep ^NAME | cut -d'=' -f2 | sed 's/\"//gI' )
   OPENSSL_ROOT_DIR=/usr/include/openssl
   if [ ! -e /etc/os-release ]; then
      printf "\\nEOSIO currently supports Amazon, Centos, Fedora, Mint & Ubuntu Linux only.\\n"
      printf "Please install on the latest version of one of these Linux distributions.\\n"
      printf "https://aws.amazon.com/amazon-linux-ami/\\n"
      printf "https://www.centos.org/\\n"
      printf "https://start.fedoraproject.org/\\n"
      printf "https://linuxmint.com/\\n"
      printf "https://www.ubuntu.com/\\n"
      printf "Exiting now.\\n"
      exit 1
   fi
   case "$OS_NAME" in
      "Amazon Linux AMI"|"Amazon Linux")
         FILE="${CURRENT_DIR}/scripts/eosio_build_amazon.sh"
         CXX_COMPILER=g++
         C_COMPILER=gcc
      ;;
      "CentOS Linux")
         FILE="${CURRENT_DIR}/scripts/eosio_build_centos.sh"
         CXX_COMPILER=g++
         C_COMPILER=gcc
      ;;
      "elementary OS")
         FILE="${CURRENT_DIR}/scripts/eosio_build_ubuntu.sh"
         CXX_COMPILER=clang++-4.0
         C_COMPILER=clang-4.0
      ;;
      "Fedora")
         FILE="${CURRENT_DIR}/scripts/eosio_build_fedora.sh"
         CXX_COMPILER=g++
         C_COMPILER=gcc
      ;;
      "Linux Mint")
         FILE="${CURRENT_DIR}/scripts/eosio_build_ubuntu.sh"
         CXX_COMPILER=clang++-4.0
         C_COMPILER=clang-4.0
      ;;
      "Ubuntu")
         FILE="${CURRENT_DIR}/scripts/eosio_build_ubuntu.sh"
         CXX_COMPILER=clang++-4.0
         C_COMPILER=clang-4.0
      ;;
      "Debian GNU/Linux")
         FILE="${CURRENT_DIR}/scripts/eosio_build_ubuntu.sh"
         CXX_COMPILER=clang++-4.0
         C_COMPILER=clang-4.0
      ;;
      *)
         printf "\\nUnsupported Linux Distribution. Exiting now.\\n\\n"
         exit 1
   esac
fi

if [ "$ARCH" == "Darwin" ]; then
   export OS_NAME=MacOSX
	# HOME/bin first to load proper cmake version over the one in /usr/bin.
	# llvm/bin last to prevent llvm/bin/clang from being used over /usr/bin/clang
   export PATH=$HOME/bin:/usr/local/opt/python/libexec/bin:$PATH:$HOME/opt/mongodb/bin:/usr/local/opt/gettext/bin:$HOME/opt/llvm/bin
   LOCAL_CMAKE_FLAGS="-DCMAKE_PREFIX_PATH=/usr/local/opt/gettext ${LOCAL_CMAKE_FLAGS}" # cleos requires Intl, which requires gettext; it's keg only though and we don't want to force linking: https://github.com/EOSIO/eos/issues/2240#issuecomment-396309884
   FILE="${CURRENT_DIR}/scripts/eosio_build_darwin.sh"
   CXX_COMPILER=clang++
   C_COMPILER=clang
   OPENSSL_ROOT_DIR=/usr/local/opt/openssl
fi

# Cleanup old installation
(. ${CURRENT_DIR}/scripts/clean_old_install.sh)
if [ $? -ne 0 ]; then exit -1; fi # Stop if exit from script is not 0

pushd $SRC_LOCATION &> /dev/null
. "$FILE" $NONINTERACTIVE # Execute OS specific build file
popd &> /dev/null

printf "\\n========================================================================\\n"
printf "======================= Starting EOSIO Build =======================\\n"
printf "## CMAKE_BUILD_TYPE=%s\\n" "${CMAKE_BUILD_TYPE}"
printf "## ENABLE_COVERAGE_TESTING=%s\\n" "${ENABLE_COVERAGE_TESTING}"

mkdir -p $BUILD_DIR
pushd $BUILD_DIR &> /dev/null

if [ -z "${CMAKE}" ]; then
  CMAKE=$( command -v cmake 2>/dev/null )
fi

$CMAKE -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}" -DCMAKE_CXX_COMPILER="${CXX_COMPILER}" \
   -DCMAKE_C_COMPILER="${C_COMPILER}" -DCORE_SYMBOL_NAME="${CORE_SYMBOL_NAME}" \
   -DOPENSSL_ROOT_DIR="${OPENSSL_ROOT_DIR}" -DBUILD_MONGO_DB_PLUGIN=true \
   -DENABLE_COVERAGE_TESTING="${ENABLE_COVERAGE_TESTING}" -DBUILD_DOXYGEN="${DOXYGEN}" \
   -DCMAKE_INSTALL_PREFIX=$OPT_LOCATION/eosio $LOCAL_CMAKE_FLAGS "${CURRENT_DIR}"
if [ $? -ne 0 ]; then exit -1; fi
make -j"${JOBS}"
if [ $? -ne 0 ]; then exit -1; fi
popd &> /dev/null

TIME_END=$(( $(date -u +%s) - $TIME_BEGIN ))

printf "\n\n _______  _______  _______ _________ _______\n"
printf '(  ____ \(  ___  )(  ____ \\\\__   __/(  ___  )\n'
printf "| (    \/| (   ) || (    \/   ) (   | (   ) |\n"
printf "| (__    | |   | || (_____    | |   | |   | |\n"
printf "|  __)   | |   | |(_____  )   | |   | |   | |\n"
printf "| (      | |   | |      ) |   | |   | |   | |\n"
printf "| (____/\| (___) |/\____) |___) (___| (___) |\n"
printf "(_______/(_______)\_______)\_______/(_______)\n\n"

printf "\\nEOSIO has been successfully built. %02d:%02d:%02d\\n\\n" $(($TIME_END/3600)) $(($TIME_END%3600/60)) $(($TIME_END%60))
printf "==============================================================================================\\n"
printf "Please run the following commands:\\n${bldred}"
print_instructions
printf "${txtrst}==============================================================================================\\n"

printf "For more information:\\n"
printf "EOSIO website: https://eos.io\\n"
printf "EOSIO Telegram channel @ https://t.me/EOSProject\\n"
printf "EOSIO resources: https://eos.io/resources/\\n"
printf "EOSIO Stack Exchange: https://eosio.stackexchange.com\\n"
printf "EOSIO wiki: https://github.com/EOSIO/eos/wiki\\n\\n\\n"

