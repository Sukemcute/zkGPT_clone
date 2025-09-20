# Hướng Dẫn Tích Hợp zkGPT với Confidential Prompting

## Tổng Quan

Hướng dẫn này sẽ giúp bạn build và tích hợp zkGPT vào hệ thống confidential prompting với Llama 3 để chứng minh tính toàn vẹn của việc gửi query (q) xuống để tính toán.

## Các Bước Thực Hiện

### 1. Build Shared Library

```bash
# Chạy script build hoàn chỉnh
./build_and_integrate.sh

# Hoặc chỉ build shared library
./build_shared.sh Release
```

### 2. Cấu Trúc File Được Tạo

```
dist/
├── lib/
│   ├── libzkgpt.so          # Main zkGPT library
│   ├── libzkgpt_wrapper.so  # C wrapper library
│   └── pkgconfig/zkgpt.pc   # pkg-config file
├── include/
│   └── wrapper.h            # C header file
├── example                  # C example program
├── Makefile                 # Build configuration
└── example_usage.c          # Example usage

zkgpt_integration_package/
├── lib/                     # All libraries
├── include/                 # All headers
├── integrate_confidential_prompting.py  # Python integration
├── README_INTEGRATION.md    # Integration documentation
├── deploy.sh               # Deployment script
├── Dockerfile              # Docker configuration
└── docker-compose.yml      # Docker Compose setup
```

### 3. Tích Hợp Vào Confidential Prompting

#### A. Sử Dụng C/C++

```c
#include "wrapper.h"
#include <stdio.h>
#include <string.h>

int main() {
    // Cấu hình zkGPT
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

    // Khởi tạo context
    zkgpt_context_t* ctx = zkgpt_init(&config);
    if (!ctx) {
        printf("Failed to initialize zkGPT\n");
        return 1;
    }

    // Tạo confidential prompt
    const char* prompt = "What is the capital of France?";
    const char* session_id = "session_123";
    const char* nonce = "nonce_456";
    const char* model_id = "llama3-8b";

    // Tạo proof
    zkgpt_proof_t* proof = zkgpt_prove(
        ctx,
        (const unsigned char*)prompt,
        strlen(prompt),
        session_id,
        nonce,
        model_id
    );

    if (proof) {
        printf("Proof generated successfully!\n");

        // Verify proof
        if (zkgpt_verify(proof, session_id, nonce, model_id) == ZKGPT_SUCCESS) {
            printf("Proof verification successful!\n");
        }

        zkgpt_free_proof(proof);
    }

    zkgpt_free_context(ctx);
    return 0;
}
```

#### B. Sử Dụng Python

```python
from integrate_confidential_prompting import ConfidentialPromptingSystem, ZKGPTConfig

# Khởi tạo hệ thống
config = ZKGPTConfig()
system = ConfidentialPromptingSystem(config)

# Tạo confidential prompt
prompt = system.create_confidential_prompt(
    prompt="What is the capital of France?",
    user_id="user123",
    model_id="llama3-8b"
)

# Xử lý với integrity proof
success, proof_data = system.process_prompt(prompt)
if success:
    print("Prompt processed with integrity proof")

    # Verify session
    if system.verify_session(prompt.session_id):
        print("Session integrity verified")
```

### 4. Tích Hợp Với Llama 3

#### A. Kiến Trúc Tích Hợp

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Client        │    │   zkGPT Layer    │    │   Llama 3       │
│                 │    │                  │    │                 │
│ 1. Send prompt  │───▶│ 2. Generate proof│───▶│ 3. Process      │
│ 2. Get proof    │◀───│ 3. Return proof  │◀───│ 4. Return result│
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

#### B. Quy Trình Xử Lý

1. **Client gửi prompt** với metadata (session_id, nonce, model_id)
2. **zkGPT Layer** tạo proof chứng minh:
   - Prompt được xử lý đúng
   - Session integrity được đảm bảo
   - Model được sử dụng đúng
3. **Llama 3** xử lý prompt và trả về kết quả
4. **Client** verify proof để đảm bảo tính toàn vẹn

#### C. Implementation Example

```python
class Llama3ConfidentialPrompting:
    def __init__(self):
        self.zkgpt_system = ConfidentialPromptingSystem(ZKGPTConfig())
        self.llama_model = self.load_llama_model()

    def process_confidential_prompt(self, prompt: str, user_id: str):
        # Tạo confidential prompt
        confidential_prompt = self.zkgpt_system.create_confidential_prompt(
            prompt=prompt,
            user_id=user_id,
            model_id="llama3-8b"
        )

        # Tạo proof
        success, proof_data = self.zkgpt_system.process_prompt(confidential_prompt)
        if not success:
            raise Exception("Failed to generate proof")

        # Xử lý với Llama 3
        result = self.llama_model.generate(prompt)

        # Trả về kết quả kèm proof
        return {
            'result': result,
            'proof': proof_data,
            'session_id': confidential_prompt.session_id,
            'integrity_verified': True
        }

    def verify_result(self, result_data: dict):
        # Verify proof
        return self.zkgpt_system.verify_session(result_data['session_id'])
```

### 5. Cấu Hình Production

#### A. Environment Variables

```bash
export ZKGPT_LIB_PATH="/path/to/libzkgpt_wrapper.so"
export ZKGPT_LOG_LEVEL=2  # 0=ERROR, 1=WARN, 2=INFO, 3=DEBUG
export ZKGPT_THREADS=4
```

#### B. Docker Deployment

```bash
# Build Docker image
cd zkgpt_integration_package
docker build -t zkgpt-confidential-prompting .

# Run with Docker Compose
docker-compose up
```

#### C. System Integration

```bash
# Install to system
cd zkgpt_integration_package
./deploy.sh

# Verify installation
ldconfig -p | grep zkgpt
```

### 6. Monitoring và Logging

#### A. Logging Configuration

```python
# Set log level
zkgpt_set_log_level(2)  # INFO level

# Get last error
error_msg = zkgpt_get_last_error()
```

#### B. Performance Monitoring

```python
import time

start_time = time.time()
success, proof_data = system.process_prompt(prompt)
end_time = time.time()

print(f"Proof generation time: {end_time - start_time:.2f} seconds")
print(f"Proof size: {len(proof_data.get('proof_data', ''))} bytes")
```

### 7. Troubleshooting

#### A. Common Issues

1. **Library not found**

   ```bash
   export LD_LIBRARY_PATH=/path/to/dist/lib:$LD_LIBRARY_PATH
   ```

2. **Build errors**

   ```bash
   # Install dependencies
   sudo apt-get install build-essential cmake libgmp-dev
   ```

3. **Memory issues**
   ```bash
   # Increase memory limits
   ulimit -v 200000000  # 200GB
   ```

#### B. Debug Mode

```bash
# Build in debug mode
./build_shared.sh Debug

# Run with debug output
export ZKGPT_LOG_LEVEL=3
./example
```

### 8. Security Considerations

#### A. Input Validation

- Validate all inputs before processing
- Sanitize prompt content
- Check session permissions

#### B. Proof Verification

- Always verify proofs before trusting results
- Implement proper error handling
- Log all verification attempts

#### C. Key Management

- Use secure random number generation
- Implement proper session management
- Rotate keys regularly

### 9. Performance Optimization

#### A. Threading

```c
zkgpt_config_t config = {
    .num_threads = 8,  // Adjust based on CPU cores
    // ... other config
};
```

#### B. Memory Management

- Use appropriate buffer sizes
- Free resources properly
- Monitor memory usage

#### C. Caching

- Cache proofs for repeated queries
- Implement session persistence
- Use efficient data structures

### 10. Testing

#### A. Unit Tests

```python
def test_proof_generation():
    system = ConfidentialPromptingSystem(ZKGPTConfig())
    prompt = system.create_confidential_prompt("test", "user1", "llama3-8b")
    success, proof = system.process_prompt(prompt)
    assert success
    assert system.verify_session(prompt.session_id)
```

#### B. Integration Tests

```python
def test_llama3_integration():
    system = Llama3ConfidentialPrompting()
    result = system.process_confidential_prompt("Hello", "user1")
    assert result['integrity_verified']
    assert system.verify_result(result)
```

## Kết Luận

Với hướng dẫn này, bạn có thể:

1. ✅ Build zkGPT thành shared library (.so)
2. ✅ Tích hợp vào confidential prompting system
3. ✅ Chứng minh tính toàn vẹn của việc gửi query
4. ✅ Verify session integrity
5. ✅ Deploy trong production environment

Hệ thống này sẽ giúp bạn đảm bảo rằng mọi query được gửi xuống để tính toán đều có proof chứng minh tính toàn vẹn, phù hợp cho confidential computing với Llama 3.
