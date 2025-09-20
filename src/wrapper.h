#ifndef ZKGPT_WRAPPER_H
#define ZKGPT_WRAPPER_H

#ifdef __cplusplus
extern "C" {
#endif

// Forward declarations
typedef struct zkgpt_context zkgpt_context_t;
typedef struct zkgpt_proof zkgpt_proof_t;
typedef struct zkgpt_public_params zkgpt_public_params_t;

// Error codes
typedef enum {
    ZKGPT_SUCCESS = 0,
    ZKGPT_ERROR_INVALID_PARAMS = -1,
    ZKGPT_ERROR_MEMORY_ALLOC = -2,
    ZKGPT_ERROR_PROOF_GENERATION = -3,
    ZKGPT_ERROR_VERIFICATION = -4,
    ZKGPT_ERROR_INITIALIZATION = -5
} zkgpt_error_t;

// Configuration structure
typedef struct {
    int num_layers;
    int num_heads;
    int head_dim;
    int attn_dim;
    int linear_dim;
    int seq_len;
    int num_threads;
    const char* model_path;
} zkgpt_config_t;

// Public parameters structure
typedef struct {
    unsigned char* commitment_data;
    size_t commitment_size;
    unsigned char* public_input_hash;
    size_t hash_size;
} zkgpt_public_params_t;

// Proof structure
typedef struct {
    unsigned char* proof_data;
    size_t proof_size;
    unsigned char* public_output;
    size_t output_size;
    zkgpt_public_params_t public_params;
} zkgpt_proof_t;

// Context structure
typedef struct {
    void* internal_context;
    zkgpt_config_t config;
    int initialized;
} zkgpt_context_t;

// API Functions

/**
 * Initialize zkGPT context
 * @param config Configuration parameters
 * @return zkgpt_context_t* or NULL on error
 */
zkgpt_context_t* zkgpt_init(const zkgpt_config_t* config);

/**
 * Generate proof for LLM inference
 * @param ctx zkGPT context
 * @param input_data Input prompt data (private)
 * @param input_size Size of input data
 * @param session_id Session identifier
 * @param nonce Nonce for replay protection
 * @param model_id Model identifier
 * @return zkgpt_proof_t* or NULL on error
 */
zkgpt_proof_t* zkgpt_prove(
    zkgpt_context_t* ctx,
    const unsigned char* input_data,
    size_t input_size,
    const char* session_id,
    const char* nonce,
    const char* model_id
);

/**
 * Verify proof
 * @param proof Proof to verify
 * @param session_id Expected session ID
 * @param nonce Expected nonce
 * @param model_id Expected model ID
 * @return zkgpt_error_t
 */
zkgpt_error_t zkgpt_verify(
    const zkgpt_proof_t* proof,
    const char* session_id,
    const char* nonce,
    const char* model_id
);

/**
 * Get proof size
 * @param proof Proof structure
 * @return Size in bytes
 */
size_t zkgpt_get_proof_size(const zkgpt_proof_t* proof);

/**
 * Get output size
 * @param proof Proof structure
 * @return Size in bytes
 */
size_t zkgpt_get_output_size(const zkgpt_proof_t* proof);

/**
 * Serialize proof to bytes
 * @param proof Proof to serialize
 * @param buffer Output buffer (can be NULL to get required size)
 * @param buffer_size Size of buffer
 * @return Actual size needed or written
 */
size_t zkgpt_serialize_proof(
    const zkgpt_proof_t* proof,
    unsigned char* buffer,
    size_t buffer_size
);

/**
 * Deserialize proof from bytes
 * @param data Serialized proof data
 * @param data_size Size of data
 * @return zkgpt_proof_t* or NULL on error
 */
zkgpt_proof_t* zkgpt_deserialize_proof(
    const unsigned char* data,
    size_t data_size
);

/**
 * Free proof memory
 * @param proof Proof to free
 */
void zkgpt_free_proof(zkgpt_proof_t* proof);

/**
 * Free context memory
 * @param ctx Context to free
 */
void zkgpt_free_context(zkgpt_context_t* ctx);

/**
 * Get last error message
 * @return Error message string
 */
const char* zkgpt_get_last_error(void);

/**
 * Set logging level
 * @param level Log level (0=ERROR, 1=WARN, 2=INFO, 3=DEBUG)
 */
void zkgpt_set_log_level(int level);

#ifdef __cplusplus
}
#endif

#endif // ZKGPT_WRAPPER_H
