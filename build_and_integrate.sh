#!/bin/bash

# Complete build and integration script for zkGPT with confidential prompting
set -e

echo "=== zkGPT Build and Integration Script ==="
echo ""

# Check dependencies
echo "Checking dependencies..."
if ! command -v cmake &> /dev/null; then
    echo "✗ CMake not found. Please install cmake >= 3.10"
    exit 1
fi

if ! command -v make &> /dev/null; then
    echo "✗ Make not found. Please install build-essential"
    exit 1
fi

if ! command -v gcc &> /dev/null; then
    echo "✗ GCC not found. Please install build-essential"
    exit 1
fi

echo "✓ Dependencies check passed"
echo ""

# Build shared library
echo "Building zkGPT shared library..."
chmod +x build_shared.sh
./build_shared.sh Release

if [ ! -f "dist/lib/libzkgpt.so" ]; then
    echo "✗ Failed to build shared library"
    exit 1
fi

echo "✓ Shared library built successfully"
echo ""

# Test the library
echo "Testing shared library..."
cd dist
make clean
make example

if [ -f "example" ]; then
    echo "✓ Example compiled successfully"
    echo "Running example..."
    ./example
    echo "✓ Example ran successfully"
else
    echo "✗ Failed to compile example"
    exit 1
fi

cd ..
echo ""

# Create integration package
echo "Creating integration package..."
INTEGRATION_DIR="zkgpt_integration_package"
mkdir -p "$INTEGRATION_DIR"

# Copy libraries and headers
cp -r dist/* "$INTEGRATION_DIR/"

# Copy Python integration script
cp integrate_confidential_prompting.py "$INTEGRATION_DIR/"

# Create requirements.txt
cat > "$INTEGRATION_DIR/requirements.txt" << EOF
# Python dependencies for zkGPT integration
# No additional dependencies required for basic integration
# Optional: add your specific dependencies here
EOF

# Create README for integration
cat > "$INTEGRATION_DIR/README_INTEGRATION.md" << EOF
# zkGPT Integration Package

This package contains the zkGPT shared library and integration tools for confidential prompting.

## Files

- \`lib/\` - Shared libraries (.so files)
- \`include/\` - Header files
- \`integrate_confidential_prompting.py\` - Python integration script
- \`example\` - C example program
- \`Makefile\` - Build configuration for C projects

## Quick Start

### C/C++ Integration

\`\`\`c
#include "wrapper.h"

// Initialize zkGPT
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

zkgpt_context_t* ctx = zkgpt_init(&config);

// Generate proof
zkgpt_proof_t* proof = zkgpt_prove(
    ctx,
    input_data,
    input_size,
    session_id,
    nonce,
    model_id
);

// Verify proof
zkgpt_error_t result = zkgpt_verify(proof, session_id, nonce, model_id);

// Cleanup
zkgpt_free_proof(proof);
zkgpt_free_context(ctx);
\`\`\`

### Python Integration

\`\`\`python
from integrate_confidential_prompting import ConfidentialPromptingSystem, ZKGPTConfig

# Initialize system
config = ZKGPTConfig()
system = ConfidentialPromptingSystem(config)

# Create confidential prompt
prompt = system.create_confidential_prompt(
    prompt="Your prompt here",
    user_id="user123",
    model_id="llama3-8b"
)

# Process with integrity proof
success, proof_data = system.process_prompt(prompt)
\`\`\`

## Building Your Project

### C/C++

\`\`\`bash
gcc -I./include -L./lib -o your_program your_program.c -lzkgpt_wrapper -lzkgpt -lmcl -lpthread
\`\`\`

### Python

\`\`\`bash
python3 integrate_confidential_prompting.py
\`\`\`

## Integration with Llama 3

To integrate with Llama 3 for confidential prompting:

1. **Input Validation**: Use zkGPT to prove that the input prompt was processed correctly
2. **Session Integrity**: Bind each prompt to a session with cryptographic proof
3. **Model Verification**: Ensure the correct model was used for inference
4. **Output Integrity**: Verify that the output corresponds to the proven input

## Security Considerations

- The current implementation is a proof-of-concept
- For production use, implement proper cryptographic hashing
- Add proper error handling and logging
- Consider using TEE (Trusted Execution Environment) for additional security
- Implement proper key management for commitments

## Performance Notes

- Proof generation can be computationally intensive
- Consider using GPU acceleration for production
- The current implementation is optimized for GPT-2, not Llama 3
- For Llama 3, consider using TEE + partial proofs

## Troubleshooting

- Ensure all dependencies are installed
- Check that the shared library is in the library path
- Verify that the model files are accessible
- Check system memory requirements (recommended: 200GB+ RAM)
EOF

# Create deployment script
cat > "$INTEGRATION_DIR/deploy.sh" << 'EOF'
#!/bin/bash

# Deployment script for zkGPT integration
set -e

echo "Deploying zkGPT integration..."

# Install libraries to system
if [ "$EUID" -eq 0 ]; then
    echo "Installing to system directories..."
    cp lib/*.so* /usr/local/lib/
    cp include/*.h /usr/local/include/
    ldconfig
    echo "✓ Libraries installed to system"
else
    echo "Installing to user directory..."
    mkdir -p ~/.local/lib
    mkdir -p ~/.local/include
    cp lib/*.so* ~/.local/lib/
    cp include/*.h ~/.local/include/
    echo "✓ Libraries installed to user directory"
    echo "Add ~/.local/lib to LD_LIBRARY_PATH if needed"
fi

echo "Deployment completed!"
EOF

chmod +x "$INTEGRATION_DIR/deploy.sh"

# Create Docker integration
cat > "$INTEGRATION_DIR/Dockerfile" << 'EOF'
FROM ubuntu:20.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    libgmp-dev \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Copy zkGPT integration
COPY . /app
WORKDIR /app

# Set library path
ENV LD_LIBRARY_PATH=/app/lib:$LD_LIBRARY_PATH

# Install Python dependencies
RUN pip3 install -r requirements.txt

# Build example
RUN make example

# Default command
CMD ["./example"]
EOF

# Create docker-compose for testing
cat > "$INTEGRATION_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  zkgpt-integration:
    build: .
    volumes:
      - ./data:/app/data
    environment:
      - LD_LIBRARY_PATH=/app/lib
    command: ["./example"]
EOF

echo "✓ Integration package created: $INTEGRATION_DIR"
echo ""

# Summary
echo "=== Build Summary ==="
echo "✓ zkGPT shared library built"
echo "✓ C/C++ wrapper created"
echo "✓ Python integration script created"
echo "✓ Example programs compiled and tested"
echo "✓ Integration package created: $INTEGRATION_DIR"
echo ""

echo "=== Next Steps ==="
echo "1. Copy the integration package to your confidential prompting system"
echo "2. Link against the shared libraries in your application"
echo "3. Use the Python script as a reference for integration"
echo "4. Customize the proof generation for your specific use case"
echo ""

echo "=== Files Created ==="
echo "- dist/lib/libzkgpt.so - Main zkGPT library"
echo "- dist/lib/libzkgpt_wrapper.so - C wrapper library"
echo "- dist/include/wrapper.h - C header file"
echo "- integrate_confidential_prompting.py - Python integration"
echo "- $INTEGRATION_DIR/ - Complete integration package"
echo ""

echo "=== Usage Examples ==="
echo "C/C++: gcc -I./include -L./lib -o prog prog.c -lzkgpt_wrapper -lzkgpt -lmcl -lpthread"
echo "Python: python3 integrate_confidential_prompting.py"
echo "Docker: docker-compose up"
echo ""

echo "Build and integration completed successfully! 🎉"
