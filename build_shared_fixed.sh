#!/bin/bash

# Build script for zkGPT shared library
set -e

# Default to Release mode if no argument provided
BUILD_TYPE=${1:-Release}
BUILD_DIR="cmake-build-shared-${BUILD_TYPE,,}"

echo "Building zkGPT shared library in ${BUILD_TYPE} mode..."

# Clean previous build
if [ -d "${BUILD_DIR}" ]; then
    echo "Cleaning previous build..."
    rm -rf "${BUILD_DIR}"
fi

# Create build directory
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Copy CMakeLists_shared.txt to current directory
cp ../CMakeLists_shared.txt ./CMakeLists.txt

# Configure with CMake
echo "Configuring with CMake..."
cmake -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_CXX_FLAGS="-fPIC" \
      -G "CodeBlocks - Unix Makefiles" \
      .

# Build
echo "Building shared library..."
make -j$(nproc)

# Create output directory
mkdir -p ../dist/lib
mkdir -p ../dist/include

# Copy shared libraries
echo "Installing shared libraries..."
cp libzkgpt.so* ../dist/lib/
cp libzkgpt_wrapper.so* ../dist/lib/
cp ../src/wrapper.h ../dist/include/

# Create pkg-config file
echo "Creating pkg-config file..."
mkdir -p ../dist/lib/pkgconfig
cat > ../dist/lib/pkgconfig/zkgpt.pc << EOF
prefix=/usr/local
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: zkgpt
Description: zkGPT - Zero-Knowledge Proofs for LLM Inference
Version: 1.0.0
Libs: -L\${libdir} -lzkgpt -lzkgpt_wrapper -lmcl
Cflags: -I\${includedir}
EOF

# Create example usage
echo "Creating example usage..."
cat > ../dist/example_usage.c << 'EOF'
#include "wrapper.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    // Initialize configuration
    zkgpt_config_t config = {
        .num_layers = 12,
        .num_heads = 12,
        .head_dim = 64,
        .attn_dim = 768,
        .linear_dim = 2304,
        .seq_len = 30,
        .num_threads = 4,
        .model_path = NULL
    };
    
    // Initialize context
    zkgpt_context_t* ctx = zkgpt_init(&config);
    if (!ctx) {
        printf("Failed to initialize zkGPT: %s\n", zkgpt_get_last_error());
        return 1;
    }
    
    // Example input data
    const char* input_text = "Hello, world!";
    const char* session_id = "session_123";
    const char* nonce = "nonce_456";
    const char* model_id = "gpt2_model";
    
    // Generate proof
    zkgpt_proof_t* proof = zkgpt_prove(
        ctx,
        (const unsigned char*)input_text,
        strlen(input_text),
        session_id,
        nonce,
        model_id
    );
    
    if (!proof) {
        printf("Failed to generate proof: %s\n", zkgpt_get_last_error());
        zkgpt_free_context(ctx);
        return 1;
    }
    
    printf("Proof generated successfully!\n");
    printf("Proof size: %zu bytes\n", zkgpt_get_proof_size(proof));
    printf("Output size: %zu bytes\n", zkgpt_get_output_size(proof));
    
    // Verify proof
    zkgpt_error_t verify_result = zkgpt_verify(proof, session_id, nonce, model_id);
    if (verify_result == ZKGPT_SUCCESS) {
        printf("Proof verification successful!\n");
    } else {
        printf("Proof verification failed: %s\n", zkgpt_get_last_error());
    }
    
    // Cleanup
    zkgpt_free_proof(proof);
    zkgpt_free_context(ctx);
    
    return 0;
}
EOF

# Create Makefile for example
cat > ../dist/Makefile << 'EOF'
CC = gcc
CFLAGS = -Wall -Wextra -std=c99
LDFLAGS = -L./lib -lzkgpt_wrapper -lzkgpt -lmcl -lpthread

example: example_usage.c
	$(CC) $(CFLAGS) -I./include -o example example_usage.c $(LDFLAGS)

clean:
	rm -f example

.PHONY: clean
EOF

cd ..

echo ""
echo "Build completed successfully!"
echo "Shared libraries are in: dist/lib/"
echo "Headers are in: dist/include/"
echo ""
echo "To test the library:"
echo "  cd dist"
echo "  make example"
echo "  ./example"
echo ""
echo "To use in your project:"
echo "  - Link with: -lzkgpt_wrapper -lzkgpt -lmcl -lpthread"
echo "  - Include: #include \"wrapper.h\""
echo "  - Add library path: -L/path/to/dist/lib"
echo "  - Add include path: -I/path/to/dist/include"
