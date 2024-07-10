source ../.env
forge clean && forge build
forge script MemeverseScript.s.sol:MemeverseScript --rpc-url blast_sepolia \
    --priority-gas-price 300 --with-gas-price 1200000 \
    --optimize --optimizer-runs 2000 \
    --broadcast --verify --ffi -vvvv
