#!/usr/bin/env python3
"""
Integration script for zkGPT with confidential prompting
This script demonstrates how to integrate zkGPT shared library with Llama 3
for confidential prompting with integrity proofs.
"""

import ctypes
import ctypes.util
import json
import hashlib
import secrets
import time
from typing import Dict, Any, Optional, Tuple
from dataclasses import dataclass
from pathlib import Path

@dataclass
class ZKGPTConfig:
    """Configuration for zkGPT"""
    num_layers: int = 12
    num_heads: int = 12
    head_dim: int = 64
    attn_dim: int = 768
    linear_dim: int = 2304
    seq_len: int = 30
    num_threads: int = 4
    model_path: Optional[str] = None

@dataclass
class ConfidentialPrompt:
    """Confidential prompt with metadata"""
    prompt: str
    session_id: str
    nonce: str
    model_id: str
    timestamp: float
    user_id: Optional[str] = None
    policy_hash: Optional[str] = None

class ZKGPTWrapper:
    """Python wrapper for zkGPT shared library"""
    
    def __init__(self, lib_path: str = "./dist/lib/libzkgpt_wrapper.so"):
        """Initialize zkGPT wrapper"""
        self.lib_path = lib_path
        self.lib = None
        self.context = None
        self._load_library()
        self._setup_functions()
    
    def _load_library(self):
        """Load the shared library"""
        try:
            self.lib = ctypes.CDLL(self.lib_path)
            print(f"✓ Loaded zkGPT library from {self.lib_path}")
        except OSError as e:
            raise RuntimeError(f"Failed to load zkGPT library: {e}")
    
    def _setup_functions(self):
        """Setup function signatures"""
        # zkgpt_init
        self.lib.zkgpt_init.argtypes = [ctypes.POINTER(ctypes.c_int * 8)]
        self.lib.zkgpt_init.restype = ctypes.c_void_p
        
        # zkgpt_prove
        self.lib.zkgpt_prove.argtypes = [
            ctypes.c_void_p,  # context
            ctypes.POINTER(ctypes.c_ubyte),  # input_data
            ctypes.c_size_t,  # input_size
            ctypes.c_char_p,  # session_id
            ctypes.c_char_p,  # nonce
            ctypes.c_char_p   # model_id
        ]
        self.lib.zkgpt_prove.restype = ctypes.c_void_p
        
        # zkgpt_verify
        self.lib.zkgpt_verify.argtypes = [
            ctypes.c_void_p,  # proof
            ctypes.c_char_p,  # session_id
            ctypes.c_char_p,  # nonce
            ctypes.c_char_p   # model_id
        ]
        self.lib.zkgpt_verify.restype = ctypes.c_int
        
        # zkgpt_get_last_error
        self.lib.zkgpt_get_last_error.restype = ctypes.c_char_p
        
        # zkgpt_free_proof
        self.lib.zkgpt_free_proof.argtypes = [ctypes.c_void_p]
        self.lib.zkgpt_free_proof.restype = None
        
        # zkgpt_free_context
        self.lib.zkgpt_free_context.argtypes = [ctypes.c_void_p]
        self.lib.zkgpt_free_context.restype = None
        
        # zkgpt_set_log_level
        self.lib.zkgpt_set_log_level.argtypes = [ctypes.c_int]
        self.lib.zkgpt_set_log_level.restype = None
    
    def init(self, config: ZKGPTConfig) -> bool:
        """Initialize zkGPT context"""
        try:
            # Create config array
            config_array = (ctypes.c_int * 8)(
                config.num_layers,
                config.num_heads,
                config.head_dim,
                config.attn_dim,
                config.linear_dim,
                config.seq_len,
                config.num_threads,
                0  # model_path (not used in C interface)
            )
            
            self.context = self.lib.zkgpt_init(ctypes.cast(config_array, ctypes.POINTER(ctypes.c_int * 8)))
            
            if not self.context:
                error_msg = self.lib.zkgpt_get_last_error()
                raise RuntimeError(f"Failed to initialize zkGPT: {error_msg.decode()}")
            
            print("✓ zkGPT context initialized")
            return True
            
        except Exception as e:
            print(f"✗ Failed to initialize zkGPT: {e}")
            return False
    
    def prove(self, prompt: ConfidentialPrompt) -> Optional[Dict[str, Any]]:
        """Generate proof for confidential prompt"""
        if not self.context:
            raise RuntimeError("zkGPT not initialized")
        
        try:
            # Convert prompt to bytes
            prompt_bytes = prompt.prompt.encode('utf-8')
            input_data = (ctypes.c_ubyte * len(prompt_bytes)).from_buffer(bytearray(prompt_bytes))
            
            # Generate proof
            proof_ptr = self.lib.zkgpt_prove(
                self.context,
                input_data,
                len(prompt_bytes),
                prompt.session_id.encode('utf-8'),
                prompt.nonce.encode('utf-8'),
                prompt.model_id.encode('utf-8')
            )
            
            if not proof_ptr:
                error_msg = self.lib.zkgpt_get_last_error()
                raise RuntimeError(f"Failed to generate proof: {error_msg.decode()}")
            
            # For now, return a simple proof structure
            # In a real implementation, you would extract the actual proof data
            proof_data = {
                'proof_ptr': proof_ptr,
                'session_id': prompt.session_id,
                'nonce': prompt.nonce,
                'model_id': prompt.model_id,
                'timestamp': prompt.timestamp,
                'prompt_hash': hashlib.sha256(prompt_bytes).hexdigest()
            }
            
            print(f"✓ Proof generated for session {prompt.session_id}")
            return proof_data
            
        except Exception as e:
            print(f"✗ Failed to generate proof: {e}")
            return None
    
    def verify(self, proof_data: Dict[str, Any]) -> bool:
        """Verify proof"""
        try:
            proof_ptr = proof_data['proof_ptr']
            
            result = self.lib.zkgpt_verify(
                proof_ptr,
                proof_data['session_id'].encode('utf-8'),
                proof_data['nonce'].encode('utf-8'),
                proof_data['model_id'].encode('utf-8')
            )
            
            if result == 0:  # ZKGPT_SUCCESS
                print("✓ Proof verification successful")
                return True
            else:
                error_msg = self.lib.zkgpt_get_last_error()
                print(f"✗ Proof verification failed: {error_msg.decode()}")
                return False
                
        except Exception as e:
            print(f"✗ Verification error: {e}")
            return False
    
    def cleanup(self):
        """Cleanup resources"""
        if self.context:
            self.lib.zkgpt_free_context(self.context)
            self.context = None
            print("✓ zkGPT context cleaned up")

class ConfidentialPromptingSystem:
    """Confidential prompting system with zkGPT integration"""
    
    def __init__(self, zkgpt_config: ZKGPTConfig):
        self.zkgpt = ZKGPTWrapper()
        self.zkgpt_config = zkgpt_config
        self.session_store = {}  # Store active sessions
        
        # Initialize zkGPT
        if not self.zkgpt.init(zkgpt_config):
            raise RuntimeError("Failed to initialize zkGPT")
    
    def create_confidential_prompt(
        self, 
        prompt: str, 
        user_id: Optional[str] = None,
        model_id: str = "llama3-8b"
    ) -> ConfidentialPrompt:
        """Create a confidential prompt with integrity metadata"""
        session_id = f"session_{secrets.token_hex(16)}"
        nonce = secrets.token_hex(32)
        timestamp = time.time()
        
        # Create policy hash (in real implementation, this would be more complex)
        policy_data = f"{user_id}:{model_id}:{timestamp}"
        policy_hash = hashlib.sha256(policy_data.encode()).hexdigest()
        
        return ConfidentialPrompt(
            prompt=prompt,
            session_id=session_id,
            nonce=nonce,
            model_id=model_id,
            timestamp=timestamp,
            user_id=user_id,
            policy_hash=policy_hash
        )
    
    def process_prompt(self, confidential_prompt: ConfidentialPrompt) -> Tuple[bool, Optional[Dict[str, Any]]]:
        """Process confidential prompt with integrity proof"""
        try:
            # Generate proof
            proof_data = self.zkgpt.prove(confidential_prompt)
            if not proof_data:
                return False, None
            
            # Store in session store
            self.session_store[confidential_prompt.session_id] = {
                'prompt': confidential_prompt,
                'proof': proof_data,
                'status': 'proven'
            }
            
            return True, proof_data
            
        except Exception as e:
            print(f"✗ Failed to process prompt: {e}")
            return False, None
    
    def verify_session(self, session_id: str) -> bool:
        """Verify a session's integrity"""
        if session_id not in self.session_store:
            print(f"✗ Session {session_id} not found")
            return False
        
        session_data = self.session_store[session_id]
        proof_data = session_data['proof']
        
        # Verify proof
        return self.zkgpt.verify(proof_data)
    
    def get_session_info(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Get session information"""
        if session_id not in self.session_store:
            return None
        
        session_data = self.session_store[session_id]
        return {
            'session_id': session_id,
            'model_id': session_data['prompt'].model_id,
            'timestamp': session_data['prompt'].timestamp,
            'user_id': session_data['prompt'].user_id,
            'status': session_data['status']
        }
    
    def cleanup(self):
        """Cleanup system resources"""
        # Cleanup all proofs
        for session_data in self.session_store.values():
            if 'proof' in session_data and 'proof_ptr' in session_data['proof']:
                self.zkgpt.lib.zkgpt_free_proof(session_data['proof']['proof_ptr'])
        
        self.session_store.clear()
        self.zkgpt.cleanup()

def main():
    """Example usage"""
    print("=== zkGPT Confidential Prompting Integration ===")
    
    # Configuration
    config = ZKGPTConfig(
        num_layers=12,
        num_heads=12,
        head_dim=64,
        attn_dim=768,
        linear_dim=2304,
        seq_len=30,
        num_threads=4
    )
    
    try:
        # Initialize system
        system = ConfidentialPromptingSystem(config)
        
        # Create confidential prompt
        prompt = system.create_confidential_prompt(
            prompt="What is the capital of France?",
            user_id="user123",
            model_id="llama3-8b"
        )
        
        print(f"Created confidential prompt:")
        print(f"  Session ID: {prompt.session_id}")
        print(f"  Model ID: {prompt.model_id}")
        print(f"  Timestamp: {prompt.timestamp}")
        print(f"  Policy Hash: {prompt.policy_hash}")
        
        # Process prompt
        success, proof_data = system.process_prompt(prompt)
        if success:
            print("✓ Prompt processed with integrity proof")
            
            # Verify session
            if system.verify_session(prompt.session_id):
                print("✓ Session integrity verified")
            else:
                print("✗ Session integrity verification failed")
        else:
            print("✗ Failed to process prompt")
        
        # Get session info
        session_info = system.get_session_info(prompt.session_id)
        if session_info:
            print(f"Session info: {json.dumps(session_info, indent=2)}")
        
    except Exception as e:
        print(f"✗ Error: {e}")
    
    finally:
        # Cleanup
        if 'system' in locals():
            system.cleanup()
        print("✓ Cleanup completed")

if __name__ == "__main__":
    main()
