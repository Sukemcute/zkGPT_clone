#!/bin/bash

# Build script for zkGPT shared library integration with Llama3
# Optimized for Vast.ai deployment

set -e

echo "=== Building zkGPT Shared Library for Llama3 Integration ==="

# Configuration
BUILD_TYPE=${1:-Release}
BUILD_DIR="cmake-build-llama3-${BUILD_TYPE,,}"
DIST_DIR="dist_llama3"

# Clean previous builds
if [ -d "${BUILD_DIR}" ]; then
    echo "Cleaning previous build..."
    rm -rf "${BUILD_DIR}"
fi

if [ -d "${DIST_DIR}" ]; then
    echo "Cleaning previous distribution..."
    rm -rf "${DIST_DIR}"
fi

# Create directories
mkdir -p "${BUILD_DIR}"
mkdir -p "${DIST_DIR}/lib"
mkdir -p "${DIST_DIR}/include"
mkdir -p "${DIST_DIR}/python"
mkdir -p "${DIST_DIR}/examples"

echo "Building in ${BUILD_TYPE} mode..."

# Create optimized CMakeLists.txt for Llama3 integration
cat > "${BUILD_DIR}/CMakeLists.txt" << 'EOF'
cmake_minimum_required(VERSION 3.10)
project(zkGPT_Llama3)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_FLAGS "-mcmodel=large -O3 -lpthread -pthread -fPIC -DNDEBUG")
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Include directories
include_directories(src)
include_directories(3rd)
include_directories(3rd/mcl/include)
link_directories(3rd/mcl)

# Build mcl library first
add_subdirectory(3rd/mcl)

# Collect all source files except main files
aux_source_directory(src gpt_src)
list(FILTER gpt_src EXCLUDE REGEX "main.*\.cpp$")

# Create main shared library
add_library(zkGPT_core SHARED ${gpt_src})
target_link_libraries(zkGPT_core mcl)

# Set library properties
set_target_properties(zkGPT_core PROPERTIES
    VERSION 1.0.0
    SOVERSION 1
    OUTPUT_NAME "zkgpt_core"
)

# Create Llama3-specific wrapper
add_library(zkGPT_llama3 SHARED src/wrapper.cpp)
target_link_libraries(zkGPT_llama3 zkGPT_core mcl)

set_target_properties(zkGPT_llama3 PROPERTIES
    VERSION 1.0.0
    SOVERSION 1
    OUTPUT_NAME "zkgpt_llama3"
)

# Install targets
install(TARGETS zkGPT_core zkGPT_llama3
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(FILES src/wrapper.h
    DESTINATION include
)
EOF

cd "${BUILD_DIR}"

# Configure with CMake
echo "Configuring with CMake..."
cmake -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_CXX_FLAGS="-fPIC -O3" \
      -G "CodeBlocks - Unix Makefiles" \
      .

# Build
echo "Building shared libraries..."
make -j$(nproc)

cd ..

# Copy shared libraries
echo "Installing shared libraries..."
cp ${BUILD_DIR}/libzkgpt_core.so* ${DIST_DIR}/lib/
cp ${BUILD_DIR}/libzkgpt_llama3.so* ${DIST_DIR}/lib/
cp src/wrapper.h ${DIST_DIR}/include/

# Create Llama3-specific header
cat > ${DIST_DIR}/include/zkgpt_llama3.h << 'EOF'
#ifndef ZKGPT_LLAMA3_H
#define ZKGPT_LLAMA3_H

#ifdef __cplusplus
extern "C" {
#endif

// Error codes
typedef enum {
    ZKGPT_SUCCESS = 0,
    ZKGPT_ERROR_INVALID_PARAMS = -1,
    ZKGPT_ERROR_MEMORY_ALLOC = -2,
    ZKGPT_ERROR_PROOF_GENERATION = -3,
    ZKGPT_ERROR_VERIFICATION = -4,
    ZKGPT_ERROR_INITIALIZATION = -5,
    ZKGPT_ERROR_MODEL_LOADING = -6
} zkgpt_error_t;

// Llama3 model configurations
typedef enum {
    LLAMA3_8B = 0,
    LLAMA3_70B = 1,
    LLAMA3_405B = 2
} llama3_model_t;

// Configuration structure for Llama3
typedef struct {
    llama3_model_t model_type;
    int num_layers;
    int num_heads;
    int head_dim;
    int attn_dim;
    int linear_dim;
    int seq_len;
    int num_threads;
    const char* model_path;
    const char* tokenizer_path;
    int max_tokens;
    float temperature;
} zkgpt_llama3_config_t;

// Context and proof types
typedef void* zkgpt_llama3_context_t;
typedef void* zkgpt_llama3_proof_t;

// Llama3-specific API Functions
zkgpt_llama3_context_t* zkgpt_llama3_init(const zkgpt_llama3_config_t* config);
zkgpt_llama3_proof_t* zkgpt_llama3_prove_prompt(
    zkgpt_llama3_context_t* ctx, 
    const char* prompt, 
    const char* session_id, 
    const char* nonce
);
zkgpt_error_t zkgpt_llama3_verify_prompt(
    const zkgpt_llama3_proof_t* proof, 
    const char* session_id, 
    const char* nonce
);
zkgpt_llama3_proof_t* zkgpt_llama3_prove_response(
    zkgpt_llama3_context_t* ctx,
    const char* response,
    const char* session_id,
    const char* nonce
);
zkgpt_error_t zkgpt_llama3_verify_response(
    const zkgpt_llama3_proof_t* proof,
    const char* session_id,
    const char* nonce
);
void zkgpt_llama3_free_proof(zkgpt_llama3_proof_t* proof);
void zkgpt_llama3_free_context(zkgpt_llama3_context_t* ctx);
const char* zkgpt_llama3_get_last_error(void);
void zkgpt_llama3_set_log_level(int level);

// Utility functions
size_t zkgpt_llama3_get_proof_size(const zkgpt_llama3_proof_t* proof);
size_t zkgpt_llama3_get_output_size(const zkgpt_llama3_proof_t* proof);
const char* zkgpt_llama3_get_model_name(llama3_model_t model_type);

#ifdef __cplusplus
}
#endif

#endif // ZKGPT_LLAMA3_H
EOF

# Create Python wrapper for Llama3
cat > ${DIST_DIR}/python/zkgpt_llama3.py << 'EOF'
import ctypes
import ctypes.util
import os
import json
from typing import Optional, Dict, Any

class ZKGPTLlama3:
    def __init__(self, lib_path="./lib/libzkgpt_llama3.so"):
        """Initialize zkGPT wrapper for Llama3 integration."""
        self.lib = ctypes.CDLL(lib_path)
        self._setup_functions()
        self._context = None
    
    def _setup_functions(self):
        """Setup function signatures for the C library."""
        # Configuration structure
        self.lib.zkgpt_llama3_init.argtypes = [ctypes.POINTER(ctypes.c_int * 12)]
        self.lib.zkgpt_llama3_init.restype = ctypes.c_void_p
        
        # Proof generation
        self.lib.zkgpt_llama3_prove_prompt.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_char_p,
            ctypes.c_char_p
        ]
        self.lib.zkgpt_llama3_prove_prompt.restype = ctypes.c_void_p
        
        # Proof verification
        self.lib.zkgpt_llama3_verify_prompt.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_char_p
        ]
        self.lib.zkgpt_llama3_verify_prompt.restype = ctypes.c_int
        
        # Response proof generation
        self.lib.zkgpt_llama3_prove_response.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_char_p,
            ctypes.c_char_p
        ]
        self.lib.zkgpt_llama3_prove_response.restype = ctypes.c_void_p
        
        # Response proof verification
        self.lib.zkgpt_llama3_verify_response.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_char_p
        ]
        self.lib.zkgpt_llama3_verify_response.restype = ctypes.c_int
        
        # Utility functions
        self.lib.zkgpt_llama3_get_last_error.restype = ctypes.c_char_p
        self.lib.zkgpt_llama3_free_proof.argtypes = [ctypes.c_void_p]
        self.lib.zkgpt_llama3_free_context.argtypes = [ctypes.c_void_p]
        self.lib.zkgpt_llama3_get_proof_size.argtypes = [ctypes.c_void_p]
        self.lib.zkgpt_llama3_get_proof_size.restype = ctypes.c_size_t
        self.lib.zkgpt_llama3_get_output_size.argtypes = [ctypes.c_void_p]
        self.lib.zkgpt_llama3_get_output_size.restype = ctypes.c_size_t
    
    def init(self, config: Dict[str, Any]) -> bool:
        """Initialize zkGPT context with Llama3 configuration."""
        # Default configuration
        default_config = {
            'model_type': 0,  # LLAMA3_8B
            'num_layers': 32,
            'num_heads': 32,
            'head_dim': 128,
            'attn_dim': 4096,
            'linear_dim': 14336,
            'seq_len': 2048,
            'num_threads': 4,
            'model_path': None,
            'tokenizer_path': None,
            'max_tokens': 512,
            'temperature': 0.7
        }
        
        # Merge with provided config
        config = {**default_config, **config}
        
        # Convert to C array
        config_array = (ctypes.c_int * 12)(
            config['model_type'],
            config['num_layers'],
            config['num_heads'],
            config['head_dim'],
            config['attn_dim'],
            config['linear_dim'],
            config['seq_len'],
            config['num_threads'],
            0,  # model_path (not used in C array)
            0,  # tokenizer_path (not used in C array)
            config['max_tokens'],
            int(config['temperature'] * 100)  # Convert to int
        )
        
        self._context = self.lib.zkgpt_llama3_init(
            ctypes.cast(config_array, ctypes.POINTER(ctypes.c_int * 12))
        )
        
        return self._context is not None
    
    def prove_prompt(self, prompt: str, session_id: str, nonce: str) -> Optional[ctypes.c_void_p]:
        """Generate proof for a confidential prompt."""
        if not self._context:
            raise RuntimeError("Context not initialized. Call init() first.")
        
        return self.lib.zkgpt_llama3_prove_prompt(
            self._context,
            prompt.encode('utf-8'),
            session_id.encode('utf-8'),
            nonce.encode('utf-8')
        )
    
    def verify_prompt(self, proof: ctypes.c_void_p, session_id: str, nonce: str) -> bool:
        """Verify proof for a confidential prompt."""
        result = self.lib.zkgpt_llama3_verify_prompt(
            proof,
            session_id.encode('utf-8'),
            nonce.encode('utf-8')
        )
        return result == 0
    
    def prove_response(self, response: str, session_id: str, nonce: str) -> Optional[ctypes.c_void_p]:
        """Generate proof for a response."""
        if not self._context:
            raise RuntimeError("Context not initialized. Call init() first.")
        
        return self.lib.zkgpt_llama3_prove_response(
            self._context,
            response.encode('utf-8'),
            session_id.encode('utf-8'),
            nonce.encode('utf-8')
        )
    
    def verify_response(self, proof: ctypes.c_void_p, session_id: str, nonce: str) -> bool:
        """Verify proof for a response."""
        result = self.lib.zkgpt_llama3_verify_response(
            proof,
            session_id.encode('utf-8'),
            nonce.encode('utf-8')
        )
        return result == 0
    
    def get_proof_size(self, proof: ctypes.c_void_p) -> int:
        """Get the size of a proof in bytes."""
        return self.lib.zkgpt_llama3_get_proof_size(proof)
    
    def get_output_size(self, proof: ctypes.c_void_p) -> int:
        """Get the size of the output in bytes."""
        return self.lib.zkgpt_llama3_get_output_size(proof)
    
    def get_last_error(self) -> str:
        """Get the last error message."""
        return self.lib.zkgpt_llama3_get_last_error().decode('utf-8')
    
    def free_proof(self, proof: ctypes.c_void_p):
        """Free a proof from memory."""
        if proof:
            self.lib.zkgpt_llama3_free_proof(proof)
    
    def free_context(self):
        """Free the context from memory."""
        if self._context:
            self.lib.zkgpt_llama3_free_context(self._context)
            self._context = None
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.free_context()

# Example usage
if __name__ == "__main__":
    print("=== zkGPT Llama3 Integration Test ===")
    
    # Initialize zkGPT
    zkgpt = ZKGPTLlama3()
    
    # Configuration for Llama3-8B
    config = {
        'model_type': 0,  # LLAMA3_8B
        'num_layers': 32,
        'num_heads': 32,
        'head_dim': 128,
        'attn_dim': 4096,
        'linear_dim': 14336,
        'seq_len': 2048,
        'num_threads': 4,
        'max_tokens': 512,
        'temperature': 0.7
    }
    
    if zkgpt.init(config):
        print("✓ zkGPT Llama3 context initialized")
        
        # Test confidential prompt
        prompt = "What is the capital of France?"
        session_id = "confidential_session_123"
        nonce = "nonce_456"
        
        print(f"Testing confidential prompt: {prompt}")
        
        # Generate proof for prompt
        prompt_proof = zkgpt.prove_prompt(prompt, session_id, nonce)
        if prompt_proof:
            print("✓ Proof generated for confidential prompt")
            
            # Verify prompt proof
            if zkgpt.verify_prompt(prompt_proof, session_id, nonce):
                print("✓ Prompt proof verification successful")
                print("✓ Confidential prompting integrity verified")
            else:
                print("✗ Prompt proof verification failed")
            
            zkgpt.free_proof(prompt_proof)
        
        # Test response proof
        response = "The capital of France is Paris."
        print(f"Testing response proof: {response}")
        
        response_proof = zkgpt.prove_response(response, session_id, nonce)
        if response_proof:
            print("✓ Proof generated for response")
            
            # Verify response proof
            if zkgpt.verify_response(response_proof, session_id, nonce):
                print("✓ Response proof verification successful")
                print("✓ Response integrity verified")
            else:
                print("✗ Response proof verification failed")
            
            zkgpt.free_proof(response_proof)
        
        zkgpt.free_context()
        print("✓ Ready for Llama3 confidential prompting integration!")
    else:
        print("✗ Failed to initialize zkGPT Llama3")
        print(f"Error: {zkgpt.get_last_error()}")
EOF

# Create example integration
cat > ${DIST_DIR}/examples/llama3_integration_example.py << 'EOF'
#!/usr/bin/env python3
"""
Example integration of zkGPT with Llama3 for confidential prompting.
This demonstrates how to use zkGPT to verify the integrity of prompts
and responses in a confidential prompting system.
"""

import sys
import os
import time
import hashlib
import json
from typing import Dict, Any, Optional

# Add the python directory to the path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'python'))

from zkgpt_llama3 import ZKGPTLlama3

class ConfidentialPromptingSystem:
    def __init__(self, zkgpt_lib_path: str = "./lib/libzkgpt_llama3.so"):
        """Initialize the confidential prompting system."""
        self.zkgpt = ZKGPTLlama3(zkgpt_lib_path)
        self.session_data = {}
        
        # Initialize zkGPT with Llama3-8B configuration
        config = {
            'model_type': 0,  # LLAMA3_8B
            'num_layers': 32,
            'num_heads': 32,
            'head_dim': 128,
            'attn_dim': 4096,
            'linear_dim': 14336,
            'seq_len': 2048,
            'num_threads': 4,
            'max_tokens': 512,
            'temperature': 0.7
        }
        
        if not self.zkgpt.init(config):
            raise RuntimeError(f"Failed to initialize zkGPT: {self.zkgpt.get_last_error()}")
        
        print("✓ Confidential Prompting System initialized")
    
    def create_session(self, user_id: str) -> str:
        """Create a new confidential session."""
        session_id = f"session_{user_id}_{int(time.time())}"
        self.session_data[session_id] = {
            'user_id': user_id,
            'created_at': time.time(),
            'prompts': [],
            'responses': []
        }
        return session_id
    
    def generate_nonce(self, session_id: str, prompt: str) -> str:
        """Generate a nonce for the given session and prompt."""
        data = f"{session_id}:{prompt}:{time.time()}"
        return hashlib.sha256(data.encode()).hexdigest()[:16]
    
    def process_confidential_prompt(self, session_id: str, prompt: str) -> Dict[str, Any]:
        """Process a confidential prompt with integrity verification."""
        if session_id not in self.session_data:
            raise ValueError("Invalid session ID")
        
        # Generate nonce
        nonce = self.generate_nonce(session_id, prompt)
        
        # Generate proof for the prompt
        print(f"Generating proof for prompt: {prompt[:50]}...")
        prompt_proof = self.zkgpt.prove_prompt(prompt, session_id, nonce)
        
        if not prompt_proof:
            raise RuntimeError(f"Failed to generate prompt proof: {self.zkgpt.get_last_error()}")
        
        # Verify the prompt proof
        if not self.zkgpt.verify_prompt(prompt_proof, session_id, nonce):
            self.zkgpt.free_proof(prompt_proof)
            raise RuntimeError("Prompt proof verification failed")
        
        print("✓ Prompt integrity verified")
        
        # Store prompt data
        prompt_data = {
            'prompt': prompt,
            'nonce': nonce,
            'proof_size': self.zkgpt.get_proof_size(prompt_proof),
            'timestamp': time.time()
        }
        self.session_data[session_id]['prompts'].append(prompt_data)
        
        # Simulate Llama3 processing (in real implementation, this would call Llama3)
        response = self._simulate_llama3_response(prompt)
        
        # Generate proof for the response
        print(f"Generating proof for response: {response[:50]}...")
        response_proof = self.zkgpt.prove_response(response, session_id, nonce)
        
        if not response_proof:
            self.zkgpt.free_proof(prompt_proof)
            raise RuntimeError(f"Failed to generate response proof: {self.zkgpt.get_last_error()}")
        
        # Verify the response proof
        if not self.zkgpt.verify_response(response_proof, session_id, nonce):
            self.zkgpt.free_proof(prompt_proof)
            self.zkgpt.free_proof(response_proof)
            raise RuntimeError("Response proof verification failed")
        
        print("✓ Response integrity verified")
        
        # Store response data
        response_data = {
            'response': response,
            'nonce': nonce,
            'proof_size': self.zkgpt.get_proof_size(response_proof),
            'timestamp': time.time()
        }
        self.session_data[session_id]['responses'].append(response_data)
        
        # Cleanup
        self.zkgpt.free_proof(prompt_proof)
        self.zkgpt.free_proof(response_proof)
        
        return {
            'session_id': session_id,
            'prompt': prompt,
            'response': response,
            'nonce': nonce,
            'integrity_verified': True,
            'timestamp': time.time()
        }
    
    def _simulate_llama3_response(self, prompt: str) -> str:
        """Simulate Llama3 response generation."""
        # In a real implementation, this would call the actual Llama3 model
        responses = {
            "What is the capital of France?": "The capital of France is Paris.",
            "Hello, how are you?": "Hello! I'm doing well, thank you for asking. How can I help you today?",
            "What is artificial intelligence?": "Artificial Intelligence (AI) is a branch of computer science that aims to create machines capable of intelligent behavior.",
            "Tell me a joke": "Why don't scientists trust atoms? Because they make up everything!",
            "What is the meaning of life?": "The meaning of life is a philosophical question that has been pondered for centuries. Many believe it's about finding purpose, happiness, and making meaningful connections."
        }
        
        # Return a response based on the prompt
        for key, value in responses.items():
            if key.lower() in prompt.lower():
                return value
        
        return f"I understand you're asking about: {prompt}. This is a simulated response from Llama3."
    
    def get_session_summary(self, session_id: str) -> Dict[str, Any]:
        """Get a summary of the session."""
        if session_id not in self.session_data:
            raise ValueError("Invalid session ID")
        
        session = self.session_data[session_id]
        return {
            'session_id': session_id,
            'user_id': session['user_id'],
            'created_at': session['created_at'],
            'num_prompts': len(session['prompts']),
            'num_responses': len(session['responses']),
            'total_proof_size': sum(p['proof_size'] for p in session['prompts'] + session['responses']),
            'duration': time.time() - session['created_at']
        }
    
    def cleanup(self):
        """Cleanup resources."""
        self.zkgpt.free_context()

def main():
    """Main function demonstrating confidential prompting."""
    print("=== zkGPT Llama3 Confidential Prompting Demo ===\n")
    
    try:
        # Initialize the system
        system = ConfidentialPromptingSystem()
        
        # Create a session
        user_id = "user_123"
        session_id = system.create_session(user_id)
        print(f"Created session: {session_id}\n")
        
        # Test prompts
        test_prompts = [
            "What is the capital of France?",
            "Hello, how are you?",
            "What is artificial intelligence?",
            "Tell me a joke",
            "What is the meaning of life?"
        ]
        
        for i, prompt in enumerate(test_prompts, 1):
            print(f"--- Test {i} ---")
            try:
                result = system.process_confidential_prompt(session_id, prompt)
                print(f"✓ Processed: {prompt}")
                print(f"✓ Response: {result['response']}")
                print(f"✓ Nonce: {result['nonce']}")
                print(f"✓ Integrity verified: {result['integrity_verified']}")
                print()
            except Exception as e:
                print(f"✗ Error processing prompt: {e}")
                print()
        
        # Get session summary
        summary = system.get_session_summary(session_id)
        print("=== Session Summary ===")
        print(f"Session ID: {summary['session_id']}")
        print(f"User ID: {summary['user_id']}")
        print(f"Duration: {summary['duration']:.2f} seconds")
        print(f"Prompts processed: {summary['num_prompts']}")
        print(f"Responses generated: {summary['num_responses']}")
        print(f"Total proof size: {summary['total_proof_size']} bytes")
        
        # Cleanup
        system.cleanup()
        print("\n✓ Demo completed successfully!")
        
    except Exception as e:
        print(f"✗ Demo failed: {e}")
        return 1
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
EOF

# Create Makefile for examples
cat > ${DIST_DIR}/Makefile << 'EOF'
CC = gcc
CXX = g++
CFLAGS = -Wall -Wextra -std=c99 -O2
CXXFLAGS = -Wall -Wextra -std=c++14 -O2
LDFLAGS = -L./lib -lzkgpt_llama3 -lzkgpt_core -lmcl -lpthread

# Python examples
python_example:
	cd python && python3 zkgpt_llama3.py

integration_example:
	cd examples && python3 llama3_integration_example.py

# C++ example
cpp_example: examples/cpp_example.cpp
	$(CXX) $(CXXFLAGS) -I./include -o examples/cpp_example examples/cpp_example.cpp $(LDFLAGS)

# Clean
clean:
	rm -f examples/cpp_example

# Test all
test: python_example integration_example

.PHONY: python_example integration_example cpp_example clean test
EOF

# Create C++ example
cat > ${DIST_DIR}/examples/cpp_example.cpp << 'EOF'
#include "zkgpt_llama3.h"
#include <iostream>
#include <string>
#include <cstring>

int main() {
    std::cout << "=== zkGPT Llama3 C++ Integration Example ===" << std::endl;
    
    // Initialize configuration
    zkgpt_llama3_config_t config = {
        .model_type = LLAMA3_8B,
        .num_layers = 32,
        .num_heads = 32,
        .head_dim = 128,
        .attn_dim = 4096,
        .linear_dim = 14336,
        .seq_len = 2048,
        .num_threads = 4,
        .model_path = nullptr,
        .tokenizer_path = nullptr,
        .max_tokens = 512,
        .temperature = 0.7f
    };
    
    // Initialize context
    zkgpt_llama3_context_t* ctx = zkgpt_llama3_init(&config);
    if (!ctx) {
        std::cerr << "Failed to initialize zkGPT: " << zkgpt_llama3_get_last_error() << std::endl;
        return 1;
    }
    
    std::cout << "✓ zkGPT Llama3 context initialized" << std::endl;
    
    // Test confidential prompt
    const char* prompt = "What is the capital of France?";
    const char* session_id = "confidential_session_123";
    const char* nonce = "nonce_456";
    
    std::cout << "Testing confidential prompt: " << prompt << std::endl;
    
    // Generate proof for prompt
    zkgpt_llama3_proof_t* prompt_proof = zkgpt_llama3_prove_prompt(ctx, prompt, session_id, nonce);
    if (!prompt_proof) {
        std::cerr << "Failed to generate prompt proof: " << zkgpt_llama3_get_last_error() << std::endl;
        zkgpt_llama3_free_context(ctx);
        return 1;
    }
    
    std::cout << "✓ Proof generated for confidential prompt" << std::endl;
    std::cout << "Proof size: " << zkgpt_llama3_get_proof_size(prompt_proof) << " bytes" << std::endl;
    
    // Verify prompt proof
    zkgpt_error_t verify_result = zkgpt_llama3_verify_prompt(prompt_proof, session_id, nonce);
    if (verify_result == ZKGPT_SUCCESS) {
        std::cout << "✓ Prompt proof verification successful" << std::endl;
        std::cout << "✓ Confidential prompting integrity verified" << std::endl;
    } else {
        std::cerr << "✗ Prompt proof verification failed: " << zkgpt_llama3_get_last_error() << std::endl;
    }
    
    // Test response proof
    const char* response = "The capital of France is Paris.";
    std::cout << "Testing response proof: " << response << std::endl;
    
    zkgpt_llama3_proof_t* response_proof = zkgpt_llama3_prove_response(ctx, response, session_id, nonce);
    if (!response_proof) {
        std::cerr << "Failed to generate response proof: " << zkgpt_llama3_get_last_error() << std::endl;
        zkgpt_llama3_free_proof(prompt_proof);
        zkgpt_llama3_free_context(ctx);
        return 1;
    }
    
    std::cout << "✓ Proof generated for response" << std::endl;
    std::cout << "Response proof size: " << zkgpt_llama3_get_proof_size(response_proof) << " bytes" << std::endl;
    
    // Verify response proof
    verify_result = zkgpt_llama3_verify_response(response_proof, session_id, nonce);
    if (verify_result == ZKGPT_SUCCESS) {
        std::cout << "✓ Response proof verification successful" << std::endl;
        std::cout << "✓ Response integrity verified" << std::endl;
    } else {
        std::cerr << "✗ Response proof verification failed: " << zkgpt_llama3_get_last_error() << std::endl;
    }
    
    // Cleanup
    zkgpt_llama3_free_proof(prompt_proof);
    zkgpt_llama3_free_proof(response_proof);
    zkgpt_llama3_free_context(ctx);
    
    std::cout << "=== Example completed successfully ===" << std::endl;
    std::cout << "Ready for Llama3 confidential prompting integration!" << std::endl;
    
    return 0;
}
EOF

# Create README for the distribution
cat > ${DIST_DIR}/README.md << 'EOF'
# zkGPT Llama3 Integration

This distribution contains the zkGPT shared library optimized for Llama3 confidential prompting integration.

## Files

- `lib/` - Shared libraries
  - `libzkgpt_core.so` - Core zkGPT library
  - `libzkgpt_llama3.so` - Llama3-specific wrapper
- `include/` - Header files
  - `zkgpt_llama3.h` - C/C++ API header
  - `wrapper.h` - Low-level wrapper header
- `python/` - Python integration
  - `zkgpt_llama3.py` - Python wrapper class
- `examples/` - Example implementations
  - `llama3_integration_example.py` - Complete Python example
  - `cpp_example.cpp` - C++ example

## Quick Start

### Python Integration

```python
from python.zkgpt_llama3 import ZKGPTLlama3

# Initialize
zkgpt = ZKGPTLlama3("./lib/libzkgpt_llama3.so")
config = {
    'model_type': 0,  # LLAMA3_8B
    'num_layers': 32,
    'num_heads': 32,
    'head_dim': 128,
    'attn_dim': 4096,
    'linear_dim': 14336,
    'seq_len': 2048,
    'num_threads': 4
}
zkgpt.init(config)

# Generate proof for confidential prompt
proof = zkgpt.prove_prompt("What is the capital of France?", "session_123", "nonce_456")

# Verify proof
if zkgpt.verify_prompt(proof, "session_123", "nonce_456"):
    print("✓ Confidential prompt integrity verified")

# Cleanup
zkgpt.free_proof(proof)
zkgpt.free_context()
```

### C++ Integration

```cpp
#include "zkgpt_llama3.h"

// Initialize
zkgpt_llama3_config_t config = {
    .model_type = LLAMA3_8B,
    .num_layers = 32,
    .num_heads = 32,
    .head_dim = 128,
    .attn_dim = 4096,
    .linear_dim = 14336,
    .seq_len = 2048,
    .num_threads = 4
};
zkgpt_llama3_context_t* ctx = zkgpt_llama3_init(&config);

// Generate proof
zkgpt_llama3_proof_t* proof = zkgpt_llama3_prove_prompt(
    ctx, "What is the capital of France?", "session_123", "nonce_456"
);

// Verify proof
if (zkgpt_llama3_verify_prompt(proof, "session_123", "nonce_456") == ZKGPT_SUCCESS) {
    printf("✓ Confidential prompt integrity verified\n");
}

// Cleanup
zkgpt_llama3_free_proof(proof);
zkgpt_llama3_free_context(ctx);
```

## Building Examples

```bash
# Python examples
make python_example
make integration_example

# C++ example
make cpp_example

# Run all tests
make test
```

## Integration with Llama3

This library is designed to be integrated with Llama3 for confidential prompting:

1. **Prompt Verification**: Generate proofs for user prompts to ensure they haven't been tampered with
2. **Response Verification**: Generate proofs for model responses to ensure they're authentic
3. **Session Management**: Track and verify entire conversation sessions
4. **Nonce-based Security**: Use nonces to prevent replay attacks

## Requirements

- Linux (tested on Ubuntu 20.04+)
- GCC 7+ or Clang 5+
- Python 3.6+
- pthread library

## License

See LICENSE.md for license information.
EOF

# Test the build
echo "Testing the build..."
cd ${DIST_DIR}

# Test Python wrapper
echo "Testing Python wrapper..."
python3 python/zkgpt_llama3.py

# Test integration example
echo "Testing integration example..."
python3 examples/llama3_integration_example.py

cd ..

echo ""
echo "=== Build Summary ==="
echo "✓ Shared libraries built: ${DIST_DIR}/lib/"
echo "✓ Headers created: ${DIST_DIR}/include/"
echo "✓ Python wrapper: ${DIST_DIR}/python/"
echo "✓ Examples: ${DIST_DIR}/examples/"
echo "✓ Documentation: ${DIST_DIR}/README.md"
echo ""
echo "=== Files Created ==="
ls -la ${DIST_DIR}/
ls -la ${DIST_DIR}/lib/
ls -la ${DIST_DIR}/include/
ls -la ${DIST_DIR}/python/
ls -la ${DIST_DIR}/examples/
echo ""
echo "=== Usage ==="
echo "Python: cd ${DIST_DIR} && python3 python/zkgpt_llama3.py"
echo "Integration: cd ${DIST_DIR} && python3 examples/llama3_integration_example.py"
echo "C++: cd ${DIST_DIR} && make cpp_example && ./examples/cpp_example"
echo ""
echo "=== Vast.ai Deployment ==="
echo "1. Upload ${DIST_DIR}/ to your Vast.ai instance"
echo "2. Install dependencies: sudo apt install -y libgmp-dev"
echo "3. Set LD_LIBRARY_PATH: export LD_LIBRARY_PATH=\$PWD/lib:\$LD_LIBRARY_PATH"
echo "4. Run examples to test integration"
echo ""
echo "Build completed successfully! 🎉"
echo "Ready for Llama3 confidential prompting integration!"
