#!/bin/bash -x

cmake -H. -Bb -DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_PREFIX=$PWD/o \
	-DBUILD_SHARED_LIBS="$BUILD_SHARED_LIBS"
cmake --build b --target install --config Debug
cmake b -DCMAKE_BUILD_TYPE=Release
cmake --build b --target install --config Release --clean-first
cd b
ctest -V


