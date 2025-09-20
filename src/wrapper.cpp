#include "wrapper.h"
#include "circuit.h"
#include "neuralNetwork.hpp"
#include "prover.hpp"
#include "verifier.hpp"
#include "models.hpp"
#include "global_var.hpp"
#include "range_prover.hpp"
#include "hyrax_rp.hpp"
#include <iostream>
#include <memory>
#include <string>
#include <cstring>
#include <vector>
#include <unordered_map>
#include <mutex>

using namespace mcl::bn;
using namespace std;

// Global state
static string g_last_error;
static int g_log_level = 1; // WARN level by default
static mutex g_error_mutex;

// Internal context structure
struct zkgpt_internal_context {
    unique_ptr<prover> p;
    unique_ptr<LLM> nn;
    unique_ptr<verifier> v;
    unique_ptr<range_prover> rp;
    zkgpt_config_t config;
    bool initialized;
    
    zkgpt_internal_context() : initialized(false) {}
};

// Helper functions
static void set_error(const string& error) {
    lock_guard<mutex> lock(g_error_mutex);
    g_last_error = error;
    if (g_log_level >= 1) {
        cerr << "[zkgpt] ERROR: " << error << endl;
    }
}

static void log_info(const string& msg) {
    if (g_log_level >= 2) {
        cerr << "[zkgpt] INFO: " << msg << endl;
    }
}

static void log_debug(const string& msg) {
    if (g_log_level >= 3) {
        cerr << "[zkgpt] DEBUG: " << msg << endl;
    }
}

// API Implementation
extern "C" {

zkgpt_context_t* zkgpt_init(const zkgpt_config_t* config) {
    if (!config) {
        set_error("Invalid configuration");
        return nullptr;
    }
    
    if (config->num_layers <= 0 || config->num_heads <= 0 || 
        config->head_dim <= 0 || config->attn_dim <= 0 || 
        config->linear_dim <= 0 || config->seq_len <= 0) {
        set_error("Invalid configuration parameters");
        return nullptr;
    }
    
    try {
        // Initialize pairing
        initPairing(mcl::BN254);
        
        auto* ctx = new zkgpt_context_t();
        ctx->internal_context = new zkgpt_internal_context();
        ctx->config = *config;
        ctx->initialized = false;
        
        auto* internal = static_cast<zkgpt_internal_context*>(ctx->internal_context);
        internal->config = *config;
        
        // Initialize range prover
        internal->rp = make_unique<range_prover>(
            config->num_layers, config->num_heads, config->head_dim,
            config->attn_dim, config->linear_dim, config->seq_len,
            config->num_threads, 1
        );
        
        internal->rp->init();
        internal->rp->build();
        
        // Initialize neural network
        internal->nn = make_unique<LLM>(
            config->num_layers, config->num_heads, config->head_dim,
            config->attn_dim, config->linear_dim
        );
        
        // Initialize prover
        internal->p = make_unique<prover>();
        internal->nn->create(*internal->p, 1);
        
        // Initialize verifier
        internal->v = make_unique<verifier>(internal->p.get(), internal->p->C);
        
        internal->initialized = true;
        ctx->initialized = true;
        
        log_info("zkgpt context initialized successfully");
        return ctx;
        
    } catch (const exception& e) {
        set_error("Initialization failed: " + string(e.what()));
        return nullptr;
    }
}

zkgpt_proof_t* zkgpt_prove(
    zkgpt_context_t* ctx,
    const unsigned char* input_data,
    size_t input_size,
    const char* session_id,
    const char* nonce,
    const char* model_id
) {
    if (!ctx || !ctx->initialized) {
        set_error("Invalid or uninitialized context");
        return nullptr;
    }
    
    if (!input_data || input_size == 0) {
        set_error("Invalid input data");
        return nullptr;
    }
    
    if (!session_id || !nonce || !model_id) {
        set_error("Missing session parameters");
        return nullptr;
    }
    
    try {
        auto* internal = static_cast<zkgpt_internal_context*>(ctx->internal_context);
        
        log_debug("Starting proof generation");
        
        // Generate range proof
        double range_prover_time = internal->rp->prove();
        
        // Set range proof time in verifier
        internal->v->range_prove(range_prover_time);
        
        // Generate GKR proof
        internal->v->prove(ctx->config.num_threads);
        
        // Create proof structure
        auto* proof = new zkgpt_proof_t();
        
        // For now, create a simple proof structure
        // In a real implementation, you would serialize the actual proof data
        proof->proof_size = 1024; // Placeholder
        proof->proof_data = new unsigned char[proof->proof_size];
        memset(proof->proof_data, 0, proof->proof_size);
        
        // Set output size (placeholder)
        proof->output_size = 256;
        proof->public_output = new unsigned char[proof->output_size];
        memset(proof->public_output, 0, proof->output_size);
        
        // Create public parameters
        string session_str = string(session_id) + ":" + string(nonce) + ":" + string(model_id);
        string hash_input = string((char*)input_data, input_size) + session_str;
        
        // Simple hash (in real implementation, use proper cryptographic hash)
        size_t hash_size = 32;
        proof->public_params.hash_size = hash_size;
        proof->public_params.public_input_hash = new unsigned char[hash_size];
        
        // Create a simple hash (replace with proper SHA-256)
        for (size_t i = 0; i < hash_size; i++) {
            proof->public_params.public_input_hash[i] = (unsigned char)(hash_input[i % hash_input.length()] ^ i);
        }
        
        // Set commitment data (placeholder)
        proof->public_params.commitment_size = 64;
        proof->public_params.commitment_data = new unsigned char[proof->public_params.commitment_size];
        memset(proof->public_params.commitment_data, 0, proof->public_params.commitment_size);
        
        log_info("Proof generated successfully");
        return proof;
        
    } catch (const exception& e) {
        set_error("Proof generation failed: " + string(e.what()));
        return nullptr;
    }
}

zkgpt_error_t zkgpt_verify(
    const zkgpt_proof_t* proof,
    const char* session_id,
    const char* nonce,
    const char* model_id
) {
    if (!proof) {
        set_error("Invalid proof");
        return ZKGPT_ERROR_INVALID_PARAMS;
    }
    
    if (!session_id || !nonce || !model_id) {
        set_error("Missing verification parameters");
        return ZKGPT_ERROR_INVALID_PARAMS;
    }
    
    try {
        // Verify proof structure
        if (proof->proof_size == 0 || !proof->proof_data) {
            set_error("Invalid proof data");
            return ZKGPT_ERROR_VERIFICATION;
        }
        
        if (proof->public_params.hash_size == 0 || !proof->public_params.public_input_hash) {
            set_error("Invalid public parameters");
            return ZKGPT_ERROR_VERIFICATION;
        }
        
        // In a real implementation, you would verify the actual proof
        // For now, just check basic structure
        log_info("Proof verification completed (placeholder)");
        return ZKGPT_SUCCESS;
        
    } catch (const exception& e) {
        set_error("Verification failed: " + string(e.what()));
        return ZKGPT_ERROR_VERIFICATION;
    }
}

size_t zkgpt_get_proof_size(const zkgpt_proof_t* proof) {
    if (!proof) return 0;
    return proof->proof_size;
}

size_t zkgpt_get_output_size(const zkgpt_proof_t* proof) {
    if (!proof) return 0;
    return proof->output_size;
}

size_t zkgpt_serialize_proof(
    const zkgpt_proof_t* proof,
    unsigned char* buffer,
    size_t buffer_size
) {
    if (!proof) return 0;
    
    size_t total_size = sizeof(zkgpt_proof_t) + 
                       proof->proof_size + 
                       proof->output_size +
                       proof->public_params.commitment_size +
                       proof->public_params.hash_size;
    
    if (!buffer) return total_size;
    
    if (buffer_size < total_size) {
        set_error("Buffer too small for serialization");
        return 0;
    }
    
    // Simple serialization (in real implementation, use proper serialization)
    size_t offset = 0;
    
    // Copy proof data
    memcpy(buffer + offset, proof->proof_data, proof->proof_size);
    offset += proof->proof_size;
    
    // Copy output data
    memcpy(buffer + offset, proof->public_output, proof->output_size);
    offset += proof->output_size;
    
    // Copy public parameters
    memcpy(buffer + offset, proof->public_params.commitment_data, proof->public_params.commitment_size);
    offset += proof->public_params.commitment_size;
    
    memcpy(buffer + offset, proof->public_params.public_input_hash, proof->public_params.hash_size);
    offset += proof->public_params.hash_size;
    
    return total_size;
}

zkgpt_proof_t* zkgpt_deserialize_proof(
    const unsigned char* data,
    size_t data_size
) {
    if (!data || data_size == 0) {
        set_error("Invalid serialized data");
        return nullptr;
    }
    
    // Simple deserialization (in real implementation, use proper deserialization)
    auto* proof = new zkgpt_proof_t();
    
    // Placeholder implementation
    proof->proof_size = 1024;
    proof->proof_data = new unsigned char[proof->proof_size];
    memcpy(proof->proof_data, data, min(proof->proof_size, data_size));
    
    proof->output_size = 256;
    proof->public_output = new unsigned char[proof->output_size];
    
    proof->public_params.commitment_size = 64;
    proof->public_params.commitment_data = new unsigned char[proof->public_params.commitment_size];
    
    proof->public_params.hash_size = 32;
    proof->public_params.public_input_hash = new unsigned char[proof->public_params.hash_size];
    
    return proof;
}

void zkgpt_free_proof(zkgpt_proof_t* proof) {
    if (!proof) return;
    
    delete[] proof->proof_data;
    delete[] proof->public_output;
    delete[] proof->public_params.commitment_data;
    delete[] proof->public_params.public_input_hash;
    delete proof;
}

void zkgpt_free_context(zkgpt_context_t* ctx) {
    if (!ctx) return;
    
    if (ctx->internal_context) {
        delete static_cast<zkgpt_internal_context*>(ctx->internal_context);
    }
    delete ctx;
}

const char* zkgpt_get_last_error(void) {
    lock_guard<mutex> lock(g_error_mutex);
    return g_last_error.c_str();
}

void zkgpt_set_log_level(int level) {
    g_log_level = max(0, min(3, level));
}

} // extern "C"
