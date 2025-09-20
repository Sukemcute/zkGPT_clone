#!/bin/bash

# Simple build script for zkGPT shared library
set -e

echo "Building zkGPT shared library..."

# Create build directory
mkdir -p build_shared
cd build_shared

# Copy source files
cp -r ../src/* .
cp ../CMakeLists_shared.txt ./CMakeLists.txt

# Create a simple Makefile for shared library
cat > Makefile << 'EOF'
CXX = g++
CXXFLAGS = -std=c++14 -fPIC -O3 -mcmodel=large -lpthread -pthread
INCLUDES = -I. -I../3rd -I../3rd/mcl/include
LDFLAGS = -shared -lpthread

# Source files (excluding main files)
SOURCES = $(wildcard *.cpp)
SOURCES := $(filter-out main_%, $(SOURCES))

# Object files
OBJECTS = $(SOURCES:.cpp=.o)

# Target libraries
TARGET_LIB = libzkgpt.so
TARGET_WRAPPER = libzkgpt_wrapper.so

all: $(TARGET_LIB) $(TARGET_WRAPPER)

$(TARGET_LIB): $(OBJECTS)
	$(CXX) $(LDFLAGS) -o $@ $^

$(TARGET_WRAPPER): wrapper.o
	$(CXX) $(LDFLAGS) -o $@ $< -L. -lzkgpt

%.o: %.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c $< -o $@

clean:
	rm -f *.o *.so

.PHONY: all clean
EOF

# Build
echo "Building shared library..."
make -j$(nproc)

# Create output directory
mkdir -p ../dist/lib
mkdir -p ../dist/include

# Copy shared libraries
echo "Installing shared libraries..."
cp *.so ../dist/lib/
cp wrapper.h ../dist/include/

# Create example
echo "Creating example..."
cat > ../dist/example_simple.c << 'EOF'
#include <stdio.h>
#include <dlfcn.h>

int main() {
    printf("zkgpt shared library built successfully!\n");
    printf("Libraries available in dist/lib/\n");
    printf("Headers available in dist/include/\n");
    return 0;
}
EOF

cd ..

echo ""
echo "Build completed successfully!"
echo "Shared libraries are in: dist/lib/"
echo "Headers are in: dist/include/"
echo ""
echo "Files created:"
echo "  - dist/lib/libzkgpt.so"
echo "  - dist/lib/libzkgpt_wrapper.so"
echo "  - dist/include/wrapper.h"
echo ""
echo "To use in your project:"
echo "  gcc -I./dist/include -L./dist/lib -o your_program your_program.c -lzkgpt_wrapper -lzkgpt -lpthread"
