# Hướng Dẫn Deploy zkGPT Llama3 Integration trên Vast.ai

## 🚀 Tổng Quan

Hướng dẫn này sẽ giúp bạn build và deploy zkGPT shared library để tích hợp với Llama3 cho confidential prompting trên Vast.ai.

## 📋 Yêu Cầu Hệ Thống

### Vast.ai Instance Requirements

- **OS**: Ubuntu 20.04 hoặc 22.04 (khuyến nghị)
- **RAM**: Tối thiểu 32GB (khuyến nghị 64GB+)
- **Storage**: Tối thiểu 50GB
- **CPU**: 8+ cores (khuyến nghị 16+ cores)
- **GPU**: Không bắt buộc cho build, nhưng hữu ích cho testing

### Dependencies

```bash
# System packages
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential cmake git wget curl
sudo apt install -y libgmp-dev libssl-dev
sudo apt install -y python3 python3-pip python3-dev
sudo apt install -y pkg-config

# Python packages
pip3 install numpy scipy
```

## 🔧 Bước 1: Setup Vast.ai Instance

### 1.1 Tạo Instance

1. Đăng nhập vào [Vast.ai](https://vast.ai)
2. Chọn "Create Instance"
3. Cấu hình:
   - **Image**: `pytorch/pytorch:2.0.1-cuda11.7-cudnn8-devel`
   - **RAM**: 64GB+
   - **Storage**: 100GB+
   - **CPU**: 16+ cores
   - **GPU**: Optional (RTX 4090 hoặc A100 nếu có)

### 1.2 Kết nối và Setup

```bash
# SSH vào instance
ssh root@<vast-ai-ip>

# Update system
apt update && apt upgrade -y

# Install dependencies
apt install -y build-essential cmake git wget curl
apt install -y libgmp-dev libssl-dev pkg-config
apt install -y python3 python3-pip python3-dev
```

## 📥 Bước 2: Clone và Build

### 2.1 Clone Repository

```bash
# Clone zkGPT repository
git clone <your-repo-url> zkgpt_clone
cd zkgpt_clone

# Make scripts executable
chmod +x *.sh
```

### 2.2 Build Shared Library

```bash
# Chạy script build Llama3 integration
./build_llama3_integration.sh

# Hoặc nếu muốn build với debug info
./build_llama3_integration.sh Debug
```

### 2.3 Verify Build

```bash
# Kiểm tra files đã tạo
ls -la dist_llama3/
ls -la dist_llama3/lib/
ls -la dist_llama3/include/

# Test shared library
cd dist_llama3
python3 python/zkgpt_llama3.py
```

## 🧪 Bước 3: Testing

### 3.1 Test Python Integration

```bash
cd dist_llama3

# Test basic functionality
python3 python/zkgpt_llama3.py

# Test complete integration
python3 examples/llama3_integration_example.py
```

### 3.2 Test C++ Integration

```bash
# Build C++ example
make cpp_example

# Run C++ example
./examples/cpp_example
```

### 3.3 Test All Examples

```bash
# Run all tests
make test
```

## 🔗 Bước 4: Tích Hợp Với Llama3

### 4.1 Tạo Project Structure

```bash
# Tạo project directory
mkdir -p ~/confidential_prompting
cd ~/confidential_prompting

# Copy zkGPT libraries
cp -r /path/to/zkgpt_clone/dist_llama3/* ./

# Tạo project structure
mkdir -p src
mkdir -p models
mkdir -p logs
mkdir -p configs
```

### 4.2 Tạo Configuration File

```bash
cat > configs/llama3_config.json << 'EOF'
{
    "zkgpt": {
        "lib_path": "./lib/libzkgpt_llama3.so",
        "model_type": 0,
        "num_layers": 32,
        "num_heads": 32,
        "head_dim": 128,
        "attn_dim": 4096,
        "linear_dim": 14336,
        "seq_len": 2048,
        "num_threads": 4,
        "max_tokens": 512,
        "temperature": 0.7
    },
    "llama3": {
        "model_path": "./models/llama3-8b",
        "tokenizer_path": "./models/llama3-8b/tokenizer.json",
        "max_tokens": 512,
        "temperature": 0.7,
        "top_p": 0.9
    },
    "security": {
        "session_timeout": 3600,
        "max_sessions": 100,
        "nonce_length": 16
    }
}
EOF
```

### 4.3 Tạo Main Integration Script

```bash
cat > src/confidential_llama3.py << 'EOF'
#!/usr/bin/env python3
"""
Confidential Llama3 Integration with zkGPT
"""

import sys
import os
import json
import time
import hashlib
from typing import Dict, Any, Optional, List

# Add zkGPT to path
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'python'))

from zkgpt_llama3 import ZKGPTLlama3

class ConfidentialLlama3:
    def __init__(self, config_path: str = "configs/llama3_config.json"):
        """Initialize Confidential Llama3 system."""
        self.config = self._load_config(config_path)
        self.zkgpt = ZKGPTLlama3(self.config['zkgpt']['lib_path'])
        self.sessions = {}

        # Initialize zkGPT
        if not self.zkgpt.init(self.config['zkgpt']):
            raise RuntimeError(f"Failed to initialize zkGPT: {self.zkgpt.get_last_error()}")

        print("✓ Confidential Llama3 system initialized")

    def _load_config(self, config_path: str) -> Dict[str, Any]:
        """Load configuration from JSON file."""
        with open(config_path, 'r') as f:
            return json.load(f)

    def create_session(self, user_id: str) -> str:
        """Create a new confidential session."""
        session_id = f"session_{user_id}_{int(time.time())}"
        self.sessions[session_id] = {
            'user_id': user_id,
            'created_at': time.time(),
            'prompts': [],
            'responses': [],
            'nonces': set()
        }
        return session_id

    def generate_nonce(self, session_id: str, prompt: str) -> str:
        """Generate a nonce for the given session and prompt."""
        data = f"{session_id}:{prompt}:{time.time()}"
        nonce = hashlib.sha256(data.encode()).hexdigest()[:self.config['security']['nonce_length']]

        # Store nonce to prevent reuse
        if session_id in self.sessions:
            self.sessions[session_id]['nonces'].add(nonce)

        return nonce

    def process_confidential_query(self, session_id: str, prompt: str) -> Dict[str, Any]:
        """Process a confidential query with integrity verification."""
        if session_id not in self.sessions:
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
        self.sessions[session_id]['prompts'].append(prompt_data)

        # Generate Llama3 response (simulated)
        response = self._generate_llama3_response(prompt)

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
        self.sessions[session_id]['responses'].append(response_data)

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

    def _generate_llama3_response(self, prompt: str) -> str:
        """Generate Llama3 response (simulated)."""
        # In a real implementation, this would call the actual Llama3 model
        # For now, we'll use a simple response generator

        responses = {
            "What is the capital of France?": "The capital of France is Paris, a beautiful city known for its art, culture, and the Eiffel Tower.",
            "Hello, how are you?": "Hello! I'm doing well, thank you for asking. I'm here to help you with any questions you might have. How can I assist you today?",
            "What is artificial intelligence?": "Artificial Intelligence (AI) is a branch of computer science that aims to create machines capable of intelligent behavior, including learning, reasoning, and problem-solving.",
            "Tell me a joke": "Why don't scientists trust atoms? Because they make up everything! 😄",
            "What is the meaning of life?": "The meaning of life is a profound philosophical question that has been pondered for centuries. Many believe it's about finding purpose, happiness, and making meaningful connections with others."
        }

        # Return a response based on the prompt
        for key, value in responses.items():
            if key.lower() in prompt.lower():
                return value

        return f"I understand you're asking about: {prompt}. This is a simulated response from Llama3. In a real implementation, this would be generated by the actual Llama3 model."

    def get_session_summary(self, session_id: str) -> Dict[str, Any]:
        """Get a summary of the session."""
        if session_id not in self.sessions:
            raise ValueError("Invalid session ID")

        session = self.sessions[session_id]
        return {
            'session_id': session_id,
            'user_id': session['user_id'],
            'created_at': session['created_at'],
            'num_prompts': len(session['prompts']),
            'num_responses': len(session['responses']),
            'total_proof_size': sum(p['proof_size'] for p in session['prompts'] + session['responses']),
            'duration': time.time() - session['created_at'],
            'unique_nonces': len(session['nonces'])
        }

    def cleanup(self):
        """Cleanup resources."""
        self.zkgpt.free_context()

def main():
    """Main function for testing."""
    print("=== Confidential Llama3 Integration Test ===\n")

    try:
        # Initialize the system
        system = ConfidentialLlama3()

        # Create a session
        user_id = "user_123"
        session_id = system.create_session(user_id)
        print(f"Created session: {session_id}\n")

        # Test queries
        test_queries = [
            "What is the capital of France?",
            "Hello, how are you?",
            "What is artificial intelligence?",
            "Tell me a joke",
            "What is the meaning of life?"
        ]

        for i, query in enumerate(test_queries, 1):
            print(f"--- Query {i} ---")
            try:
                result = system.process_confidential_query(session_id, query)
                print(f"✓ Query: {query}")
                print(f"✓ Response: {result['response']}")
                print(f"✓ Nonce: {result['nonce']}")
                print(f"✓ Integrity verified: {result['integrity_verified']}")
                print()
            except Exception as e:
                print(f"✗ Error processing query: {e}")
                print()

        # Get session summary
        summary = system.get_session_summary(session_id)
        print("=== Session Summary ===")
        print(f"Session ID: {summary['session_id']}")
        print(f"User ID: {summary['user_id']}")
        print(f"Duration: {summary['duration']:.2f} seconds")
        print(f"Queries processed: {summary['num_prompts']}")
        print(f"Responses generated: {summary['num_responses']}")
        print(f"Total proof size: {summary['total_proof_size']} bytes")
        print(f"Unique nonces: {summary['unique_nonces']}")

        # Cleanup
        system.cleanup()
        print("\n✓ Test completed successfully!")

    except Exception as e:
        print(f"✗ Test failed: {e}")
        return 1

    return 0

if __name__ == "__main__":
    sys.exit(main())
EOF

chmod +x src/confidential_llama3.py
```

## 🚀 Bước 5: Deploy và Test

### 5.1 Test Integration

```bash
cd ~/confidential_prompting

# Test the integration
python3 src/confidential_llama3.py
```

### 5.2 Tạo Service Script

```bash
cat > start_confidential_service.sh << 'EOF'
#!/bin/bash

# Start Confidential Llama3 Service
echo "Starting Confidential Llama3 Service..."

# Set environment variables
export LD_LIBRARY_PATH=$PWD/lib:$LD_LIBRARY_PATH
export PYTHONPATH=$PWD/python:$PYTHONPATH

# Start the service
python3 src/confidential_llama3.py
EOF

chmod +x start_confidential_service.sh
```

### 5.3 Tạo Docker Container (Optional)

```bash
cat > Dockerfile << 'EOF'
FROM ubuntu:20.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    libgmp-dev \
    libssl-dev \
    pkg-config \
    python3 \
    python3-pip \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip3 install numpy scipy

# Copy application
COPY . /app
WORKDIR /app

# Set environment variables
ENV LD_LIBRARY_PATH=/app/lib:$LD_LIBRARY_PATH
ENV PYTHONPATH=/app/python:$PYTHONPATH

# Expose port
EXPOSE 8000

# Start service
CMD ["python3", "src/confidential_llama3.py"]
EOF

# Build Docker image
docker build -t confidential-llama3 .

# Run Docker container
docker run -p 8000:8000 confidential-llama3
```

## 🔍 Bước 6: Monitoring và Debugging

### 6.1 Logging

```bash
# Tạo log directory
mkdir -p logs

# Run with logging
python3 src/confidential_llama3.py 2>&1 | tee logs/confidential_llama3.log
```

### 6.2 Performance Monitoring

```bash
# Monitor system resources
htop

# Monitor memory usage
free -h

# Monitor disk usage
df -h
```

### 6.3 Debug Common Issues

```bash
# Check library dependencies
ldd lib/libzkgpt_llama3.so

# Check Python path
python3 -c "import sys; print(sys.path)"

# Check environment variables
env | grep -E "(LD_LIBRARY_PATH|PYTHONPATH)"
```

## 📊 Bước 7: Performance Optimization

### 7.1 Memory Optimization

```bash
# Increase memory limits
ulimit -v 200000000  # 200GB

# Monitor memory usage
watch -n 1 'free -h'
```

### 7.2 CPU Optimization

```bash
# Set CPU affinity
taskset -c 0-15 python3 src/confidential_llama3.py

# Monitor CPU usage
top -p $(pgrep -f confidential_llama3)
```

### 7.3 Storage Optimization

```bash
# Clean up build files
rm -rf cmake-build-llama3-*

# Compress logs
gzip logs/*.log
```

## 🛡️ Bước 8: Security Considerations

### 8.1 Secure Configuration

```bash
# Set secure permissions
chmod 600 configs/llama3_config.json
chmod 755 lib/*.so
chmod 644 include/*.h
```

### 8.2 Network Security

```bash
# Firewall rules (if needed)
ufw allow 22/tcp
ufw allow 8000/tcp
ufw enable
```

### 8.3 Data Protection

```bash
# Encrypt sensitive data
gpg --symmetric configs/llama3_config.json

# Secure session storage
chmod 700 sessions/
```

## 📈 Bước 9: Scaling và Production

### 9.1 Load Balancing

```bash
# Create multiple instances
for i in {1..3}; do
    cp -r ~/confidential_prompting ~/confidential_prompting_$i
    cd ~/confidential_prompting_$i
    python3 src/confidential_llama3.py &
done
```

### 9.2 Health Checks

```bash
# Create health check script
cat > health_check.sh << 'EOF'
#!/bin/bash

# Check if service is running
if pgrep -f confidential_llama3 > /dev/null; then
    echo "✓ Service is running"
    exit 0
else
    echo "✗ Service is not running"
    exit 1
fi
EOF

chmod +x health_check.sh
```

### 9.3 Backup và Recovery

```bash
# Create backup script
cat > backup.sh << 'EOF'
#!/bin/bash

BACKUP_DIR="/backup/confidential_llama3_$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR

# Backup configuration
cp -r configs/ $BACKUP_DIR/

# Backup logs
cp -r logs/ $BACKUP_DIR/

# Backup session data
cp -r sessions/ $BACKUP_DIR/

echo "Backup created: $BACKUP_DIR"
EOF

chmod +x backup.sh
```

## 🎯 Kết Quả Cuối Cùng

Sau khi hoàn thành tất cả các bước, bạn sẽ có:

1. **Shared Library**: `libzkgpt_llama3.so` - Thư viện chính cho Llama3 integration
2. **Python Wrapper**: `zkgpt_llama3.py` - Python wrapper cho dễ sử dụng
3. **Configuration**: `llama3_config.json` - Cấu hình hệ thống
4. **Main Service**: `confidential_llama3.py` - Service chính
5. **Examples**: Các ví dụ sử dụng
6. **Documentation**: Hướng dẫn chi tiết

## 🚀 Sử Dụng

```bash
# Start service
./start_confidential_service.sh

# Test integration
python3 src/confidential_llama3.py

# Monitor logs
tail -f logs/confidential_llama3.log
```

## 🔧 Troubleshooting

### Common Issues

1. **Library not found**:

   ```bash
   export LD_LIBRARY_PATH=$PWD/lib:$LD_LIBRARY_PATH
   ```

2. **Python import error**:

   ```bash
   export PYTHONPATH=$PWD/python:$PYTHONPATH
   ```

3. **Memory issues**:

   ```bash
   ulimit -v 200000000
   ```

4. **Permission denied**:
   ```bash
   chmod +x *.sh
   chmod 755 lib/*.so
   ```

## 📞 Support

Nếu gặp vấn đề, hãy kiểm tra:

1. Logs trong `logs/` directory
2. System resources với `htop` và `free -h`
3. Library dependencies với `ldd`
4. Environment variables với `env`

Chúc bạn deploy thành công! 🎉
