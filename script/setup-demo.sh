#!/bin/bash

# ============================================================
# AI DeFi Guardian — Demo Environment Setup
#
# Prerequisites:
#   1. Anvil running: anvil --fork-url $SEPOLIA_RPC_URL
#   2. .env configured with SEPOLIA_RPC_URL and PRIVATE_KEY
#
# This script:
#   - Unfreezes USDC on the forked Aave V3 (Sepolia assets are frozen)
#   - Injects USDC liquidity into the Aave pool
#   - Creates an Aave position (supply WETH, borrow USDC) with HF ~1.15
#   - The position is intentionally unhealthy (HF < 1.3) to trigger AI protection
#
# After running, start the frontend and interact via browser.
# ============================================================

set -e

# ========== Config ==========

FORK=http://127.0.0.1:8545

# Aave V3 Sepolia
ADMIN=0xfA0e305E0f46AB04f00ae6b5f4560d61a2183E00
CONFIGURATOR=0x7Ee60D184C24Ef7AfC1Ec7Be59A0f448A0abd138
ACL_MANAGER=0x7F2bE3b178deeFF716CD6Ff03Ef79A1dFf360ddD
POOL=0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951
USDC=0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8
WETH=0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c
ATOKEN=0x16dA4541aD1807f4443d92D26044C1147406EB80    # USDC aToken
ADDRESSES_PROVIDER=0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A

# Our contracts
VAULT=0xBB13da705D2Aa3DAA6ED8FfFcC83AD534281F27A
REGISTRY=0x2a1eb5F43271d2d1aa0635bb56158D2280d6e7cC

# Anvil default account 1 (the "user" in the demo — clean, no pre-existing Aave position)
USER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
USER_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

# How much WETH to supply as collateral
SUPPLY_WETH="0.5"   # 0.5 ETH
SUPPLY_WEI=500000000000000000

# Target HF after borrowing (~1.15, below our 1.3 threshold)
TARGET_HF=115  # represents 1.15 (scaled by 100)

# ========== Helpers ==========

title() { echo -e "\n\033[1;36m[$1/$TOTAL_STEPS] $2\033[0m"; }
ok()    { echo -e "  \033[0;32m✓ $1\033[0m"; }
info()  { echo -e "  \033[0;33m→ $1\033[0m"; }
err()   { echo -e "  \033[0;31m✗ $1\033[0m"; exit 1; }

TOTAL_STEPS=6

# cast returns "12345 [1.23e4]" — strip the bracket notation
strip() { awk '{print $1}'; }

# ========== Step 0: Pre-flight checks ==========

echo -e "\033[1;35m========================================\033[0m"
echo -e "\033[1;35m  AI DeFi Guardian — Demo Setup\033[0m"
echo -e "\033[1;35m========================================\033[0m"

# Check Anvil is running
if ! cast block-number --rpc-url $FORK &>/dev/null; then
  err "Anvil is not running on $FORK. Start it first:\n  anvil --fork-url \$SEPOLIA_RPC_URL"
fi
ok "Anvil is running (block $(cast block-number --rpc-url $FORK))"

# ========== Step 1: Unfreeze USDC on Aave ==========

title 1 "Unfreeze USDC on Aave"
info "Sepolia Aave V3 froze all assets — we impersonate the admin to unfreeze"

cast rpc anvil_impersonateAccount $ADMIN --rpc-url $FORK > /dev/null
cast rpc anvil_setBalance $ADMIN 0xDE0B6B3A7640000 --rpc-url $FORK > /dev/null

# Grant risk admin role
cast send $ACL_MANAGER "addRiskAdmin(address)" $ADMIN \
  --from $ADMIN --rpc-url $FORK --unlocked > /dev/null 2>&1
ok "Admin granted risk admin role"

# Unfreeze USDC
cast send $CONFIGURATOR "setReserveFreeze(address,bool)" $USDC false \
  --from $ADMIN --rpc-url $FORK --unlocked > /dev/null 2>&1
ok "USDC unfrozen"

# Raise supply/borrow caps
cast send $CONFIGURATOR "setSupplyCap(address,uint256)" $USDC 10000000000 \
  --from $ADMIN --rpc-url $FORK --unlocked > /dev/null 2>&1
cast send $CONFIGURATOR "setBorrowCap(address,uint256)" $USDC 10000000000 \
  --from $ADMIN --rpc-url $FORK --unlocked > /dev/null 2>&1
ok "USDC supply/borrow caps raised"

cast rpc anvil_stopImpersonatingAccount $ADMIN --rpc-url $FORK > /dev/null

# ========== Step 2: Inject USDC liquidity ==========

title 2 "Inject USDC liquidity into Aave pool"
info "Aave pool has insufficient USDC — inject 100,000 USDC into the aToken contract"

STORAGE_KEY=$(cast index address $ATOKEN 0)
cast rpc anvil_setStorageAt $USDC $STORAGE_KEY \
  0x000000000000000000000000000000000000000000000000000000174876e800 \
  --rpc-url $FORK > /dev/null

ATOKEN_BAL=$(cast call $USDC "balanceOf(address)(uint256)" $ATOKEN --rpc-url $FORK | strip)
ok "aToken USDC balance: $(echo "$ATOKEN_BAL / 1000000" | bc) USDC"

# ========== Step 3: Wrap ETH -> WETH ==========

title 3 "Wrap ${SUPPLY_WETH} ETH → WETH"
info "Aave only accepts ERC20 tokens, not native ETH. WETH wraps ETH 1:1."

cast send $WETH "deposit()" --value ${SUPPLY_WETH}ether \
  --rpc-url $FORK --private-key $USER_KEY > /dev/null 2>&1

WETH_BAL=$(cast call $WETH "balanceOf(address)(uint256)" $USER --rpc-url $FORK | strip)
ok "WETH balance: $(echo "scale=4; $WETH_BAL / 1000000000000000000" | bc) WETH"

# ========== Step 4: Supply WETH to Aave as collateral ==========

title 4 "Supply WETH to Aave as collateral"
info "This becomes your collateral — Aave uses it to calculate how much you can borrow"

cast send $WETH "approve(address,uint256)" $POOL $SUPPLY_WEI \
  --rpc-url $FORK --private-key $USER_KEY > /dev/null 2>&1

cast send $POOL "supply(address,uint256,address,uint16)" $WETH $SUPPLY_WEI $USER 0 \
  --rpc-url $FORK --private-key $USER_KEY > /dev/null 2>&1

ok "Supplied ${SUPPLY_WETH} WETH to Aave"

# Read position to calculate borrow amount
COLLATERAL=$(cast call $POOL "getUserAccountData(address)(uint256,uint256,uint256,uint256,uint256,uint256)" $USER --rpc-url $FORK | sed -n '1p' | strip)
CURRENT_DEBT=$(cast call $POOL "getUserAccountData(address)(uint256,uint256,uint256,uint256,uint256,uint256)" $USER --rpc-url $FORK | sed -n '2p' | strip)
LT=$(cast call $POOL "getUserAccountData(address)(uint256,uint256,uint256,uint256,uint256,uint256)" $USER --rpc-url $FORK | sed -n '4p' | strip)

COLLATERAL_USD=$(echo "scale=2; $COLLATERAL / 100000000" | bc)
CURRENT_DEBT_USD=$(echo "scale=2; $CURRENT_DEBT / 100000000" | bc)
info "Collateral: \$$COLLATERAL_USD | Current debt: \$$CURRENT_DEBT_USD | LT: $(echo "scale=2; $LT / 100" | bc)%"

# ========== Step 5: Borrow USDC to create low-HF position ==========

title 5 "Borrow USDC → target HF ~1.15"
info "Borrow enough USDC so Health Factor drops below the 1.3 protection threshold"

# Calculate: targetDebt = collateral * LT / 10000 / 1.15
# borrowMore = targetDebt - currentDebt
# All values in 8-decimal base currency units
TARGET_DEBT=$(echo "$COLLATERAL * $LT / 10000 * 100 / $TARGET_HF" | bc)
BORROW_MORE=$(echo "$TARGET_DEBT - $CURRENT_DEBT" | bc)

if [ "$BORROW_MORE" -le 0 ]; then
  info "Current debt already sufficient for target HF"
  BORROW_MORE=0
else
  # Convert from 8-decimal base currency to 6-decimal USDC
  BORROW_USDC=$(echo "$BORROW_MORE / 100" | bc)
  BORROW_USD=$(echo "scale=2; $BORROW_USDC / 1000000" | bc)
  info "Need to borrow: \$$BORROW_USD USDC"

  cast send $POOL "borrow(address,uint256,uint256,uint16,address)" \
    $USDC $BORROW_USDC 2 0 $USER \
    --rpc-url $FORK --private-key $USER_KEY > /dev/null 2>&1
  ok "Borrowed $BORROW_USD USDC"
fi

# Verify final position
FINAL_DEBT=$(cast call $POOL "getUserAccountData(address)(uint256,uint256,uint256,uint256,uint256,uint256)" $USER --rpc-url $FORK | sed -n '2p' | strip)
FINAL_HF=$(cast call $POOL "getUserAccountData(address)(uint256,uint256,uint256,uint256,uint256,uint256)" $USER --rpc-url $FORK | sed -n '6p' | strip)
FINAL_DEBT_USD=$(echo "scale=2; $FINAL_DEBT / 100000000" | bc)
FINAL_HF_DISPLAY=$(echo "scale=4; $FINAL_HF / 1000000000000000000" | bc)

ok "Final debt: \$$FINAL_DEBT_USD | HF: $FINAL_HF_DISPLAY"

# ========== Step 6: Verify user USDC balance ==========

title 6 "Verify user balances"
info "User already has USDC from the Aave borrow — enough to deposit as Guardian budget"

USER_USDC=$(cast call $USDC "balanceOf(address)(uint256)" $USER --rpc-url $FORK | strip)
USER_USDC_DISPLAY=$(echo "scale=2; $USER_USDC / 1000000" | bc)
ok "User USDC balance: $USER_USDC_DISPLAY USDC (from borrowing)"
ok "User ETH balance: 10000 ETH (Anvil default)"

# ========== Done ==========

echo ""
echo -e "\033[1;32m========================================\033[0m"
echo -e "\033[1;32m  Setup complete!\033[0m"
echo -e "\033[1;32m========================================\033[0m"
echo ""
echo -e "  User address:  $USER"
echo -e "  Health Factor: \033[1;31m$FINAL_HF_DISPLAY\033[0m (below 1.3 threshold)"
echo -e "  USDC balance:  $USER_USDC_DISPLAY USDC (for Guardian budget)"
echo ""
echo -e "  \033[1;33mNext steps:\033[0m"
echo -e "  1. cd frontend && npm run dev"
echo -e "  2. Open http://localhost:5173 in browser"
echo -e "  3. Connect MetaMask with Anvil account 1"
echo -e "     Address: $USER"
echo -e "     Private key: $USER_KEY"
echo -e "  4. MetaMask RPC must point to http://127.0.0.1:8545"
echo ""
