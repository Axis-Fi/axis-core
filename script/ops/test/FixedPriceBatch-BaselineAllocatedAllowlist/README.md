# FixedPriceBatch - Baseline Allocated Allowlist Testing

## How to Test

1. Deploy the Axis stack
2. Deploy the Baseline v2 stack
    - Record the kernel and reserve token addresses
3. Generate salts for the BaselineAllocatedAllowlist
    - You will need to provide the kernel, owner, and reserveToken
4. Deploy the BaselineAllocatedAllowlist callback contract
    - You will need to provide the kernel, owner, and reserveToken
5. Generate the Merkle root
6. Create the auction
    - You will need to provide the quote token, base token, BaselineAllocatedAllowlist address and merkle root
