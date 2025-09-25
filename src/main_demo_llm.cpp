//
// Created by 69029 on 4/12/2021.
//

#undef NDEBUG
#include "circuit.h"
#include "neuralNetwork.hpp"
#include "verifier.hpp"
#include "models.hpp"
#include "global_var.hpp"
#include <iostream>

#include "range_prover.hpp"
#include "hyrax_rp.hpp"
using namespace mcl::bn;
using namespace std;




int main(int argc, char **argv) 
{
    initPairing(mcl::BN254);
    
        // 1. Range Prover cho các phép toán phi tuyến
    range_prover range_prover(
        32,     // layers
        32,     // heads
        128,    // head_dim (4096 / 32)
        4096,   // model_dim
        14336,  // ffn_dim
        512,    // seq_len (ví dụ chọn 512, bạn có thể tăng lên 2k, 4k, 8k...)
        32,     // threads
        1       // batch_size (ví dụ)
    );
    range_prover.init();
    range_prover.build();
    double range_prover_time = range_prover.prove();  // ← PROVE RANGE CONSTRAINTS

    // 2. GKR Prover cho các phép toán tuyến tính
    prover p;
    LLM nn(
        32,     // layers
        32,     // heads
        128,    // head_dim
        4096,   // model_dim
        14336   // ffn_dim
    );  // Tạo Llama-3.2-3B model (rút gọn)
    nn.create(p, 1);  // ← TẠO CIRCUIT CHO LLAMA-3.2-3B

    // === PHẦN VERIFY ===
    verifier v(&p, p.C);
    v.range_prove(range_prover_time);
    v.prove(32);  // ← VERIFY VỚI 32 THREADS


}

