#!/bin/bash

# ============================================================
# AI DeFi Guardian — On-chain Interaction Script
# Usage: ./script/interact.sh <command>
# Example: ./script/interact.sh read-policy 0x1Fd8c5...
# ============================================================

set -e

# Load .env (script is in script/ directory, .env is in project root)
source "$(dirname "$0")/../.env"

# ========== Contract Addresses ==========
REGISTRY=0x2a1eb5F43271d2d1aa0635bb56158D2280d6e7cC
AAVE_INTEGRATION=0x0cF45f3ECb4f67ea4688656c27a9c7bfe11E571E
VAULT=0xBB13da705D2Aa3DAA6ED8FfFcC83AD534281F27A
USDC=0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8

RPC="--rpc-url $SEPOLIA_RPC_URL"
SEND="--private-key $PRIVATE_KEY $RPC"

# ========== Helper Functions ==========
title() { echo -e "\n\033[1;36m=== $1 ===\033[0m"; }
info()  { echo -e "\033[0;33m$1\033[0m"; }

# ============================================================
# Read Commands (no gas cost)
# ============================================================

cmd_status() {
    title "Contract Status"
    echo -n "Registry owner:    " && cast call $REGISTRY   "owner()(address)" $RPC
    echo -n "Registry vault:    " && cast call $REGISTRY   "vault()(address)" $RPC
    echo -n "Vault name:        " && cast call $VAULT      "name()(string)" $RPC
    echo -n "Vault agent:       " && cast call $VAULT      "protocolAgent()(address)" $RPC
    echo -n "Vault treasury:    " && cast call $VAULT      "protocolTreasury()(address)" $RPC
    echo -n "Vault paused:      " && cast call $VAULT      "paused()(bool)" $RPC
    echo -n "AaveIntegration:   " && cast call $AAVE_INTEGRATION "vault()(address)" $RPC
}

cmd_read_policy() {
    local user=${1:-$PROTOCOL_AGENT}
    title "Read Policy: $user"
    cast call $REGISTRY "getPolicy(address)((uint256,uint256,uint256,uint256,bool))" "$user" $RPC
}

cmd_users() {
    title "Registered Users"
    cast call $REGISTRY "getRegisteredUsers()(address[])" $RPC
}

cmd_hf() {
    local user=${1:-$PROTOCOL_AGENT}
    title "Health Factor: $user"
    cast call $AAVE_INTEGRATION "getHealthFactor(address)(uint256)" "$user" $RPC
}

cmd_debt() {
    local user=${1:-$PROTOCOL_AGENT}
    title "USDC Debt: $user"
    cast call $AAVE_INTEGRATION "getUserDebt(address)(uint256)" "$user" $RPC
}

cmd_balance() {
    local user=${1:-$PROTOCOL_AGENT}
    title "Balance: $user"
    echo -n "ETH:          " && cast balance "$user" $RPC
    echo -n "USDC:         " && cast call $USDC "balanceOf(address)(uint256)" "$user" $RPC
    echo -n "gUSDC(Vault): " && cast call $VAULT "balanceOf(address)(uint256)" "$user" $RPC
}

# ============================================================
# Write Commands (costs gas, requires private key)
# ============================================================

cmd_set_policy() {
    local threshold=${1:-1300000000000000000}  # Default 1.3e18
    local max_repay=${2:-500000000}             # Default 500 USDC
    local cooldown=${3:-3600}                   # Default 1 hour
    title "Register Policy"
    info "threshold=$threshold, maxRepay=$max_repay, cooldown=$cooldown"
    cast send $REGISTRY "setPolicy(uint256,uint256,uint256)" "$threshold" "$max_repay" "$cooldown" $SEND
}

cmd_deactivate() {
    title "Deactivate Policy"
    cast send $REGISTRY "deactivate()" $SEND
}

cmd_approve_usdc() {
    local amount=${1:-1000000000}  # Default 1000 USDC
    title "Approve USDC -> Vault"
    info "amount=$amount"
    cast send $USDC "approve(address,uint256)" $VAULT "$amount" $SEND
}

cmd_deposit() {
    local amount=${1:-1000000000}  # Default 1000 USDC
    local receiver=${2:-$(cast wallet address --private-key $PRIVATE_KEY)}
    title "Deposit USDC -> Vault"
    info "amount=$amount, receiver=$receiver"
    cast send $VAULT "deposit(uint256,address)" "$amount" "$receiver" $SEND
}

cmd_withdraw() {
    local amount=${1:-500000000}  # Default 500 USDC
    local receiver=${2:-$(cast wallet address --private-key $PRIVATE_KEY)}
    title "Withdraw USDC <- Vault"
    info "amount=$amount, receiver=$receiver"
    cast send $VAULT "withdraw(uint256,address,address)" "$amount" "$receiver" "$receiver" $SEND
}

cmd_execute() {
    local user=$1
    local amount=$2
    local reason=${3:-"Manual protection trigger"}
    if [ -z "$user" ] || [ -z "$amount" ]; then
        echo "Usage: ./interact.sh execute <user_address> <repay_amount> [AI_reason]"
        echo "Example: ./interact.sh execute 0x1Fd8... 300000000 'ETH price dropping'"
        exit 1
    fi
    title "Execute Protection Repayment"
    info "user=$user, amount=$amount, reason=$reason"
    cast send $VAULT "executeRepayment(address,uint256,string)" "$user" "$amount" "$reason" $SEND
}

cmd_pause() {
    title "Pause Vault"
    cast send $VAULT "pause()" $SEND
}

cmd_unpause() {
    title "Unpause Vault"
    cast send $VAULT "unpause()" $SEND
}

cmd_set_agent() {
    local new_agent=$1
    if [ -z "$new_agent" ]; then
        echo "Usage: ./interact.sh set-agent <new_agent_address>"
        exit 1
    fi
    title "Change Agent"
    info "newAgent=$new_agent"
    cast send $VAULT "setProtocolAgent(address)" "$new_agent" $SEND
}

# ============================================================
# Custom cast Calls (advanced usage)
# ============================================================

cmd_call() {
    # Pass through directly to cast call
    # Usage: ./interact.sh call <contract_address> "function_signature" [args...]
    title "Custom call"
    cast call "$@" $RPC
}

cmd_send() {
    # Pass through directly to cast send
    # Usage: ./interact.sh send <contract_address> "function_signature" [args...]
    title "Custom send"
    cast send "$@" $SEND
}

# ============================================================
# Help
# ============================================================

cmd_help() {
    echo "
AI DeFi Guardian On-chain Interaction Script

Read Commands (free):
  status                         View all contract status
  read-policy [address]          Read user policy (defaults to self)
  users                          List all registered users
  hf [address]                   Query Health Factor (defaults to self)
  debt [address]                 Query USDC debt (defaults to self)
  balance [address]              Query ETH/USDC/gUSDC balance (defaults to self)

Write Commands (costs gas):
  set-policy [threshold] [maxRepay] [cooldown]   Register protection policy
  deactivate                                     Deactivate policy
  approve-usdc [amount]                          Approve USDC for Vault
  deposit [amount] [receiver]                    Deposit USDC into Vault
  withdraw [amount] [receiver]                   Withdraw USDC from Vault
  execute <user> <amount> [AI_reason]            Execute protection repayment (Agent only)
  pause                                          Pause Vault (Owner only)
  unpause                                        Unpause Vault (Owner only)
  set-agent <new_address>                        Change Agent (Owner only)

Advanced Usage:
  call <contract_address> \"function_signature\" [args]    Custom cast call
  send <contract_address> \"function_signature\" [args]    Custom cast send

Examples:
  ./interact.sh status
  ./interact.sh set-policy 1300000000000000000 500000000 3600
  ./interact.sh read-policy 0x1Fd8c5E21885b352b9Afac73861878a95106e9Ae
  ./interact.sh balance
  ./interact.sh execute 0x1Fd8... 300000000 'ETH dropping fast'
  ./interact.sh call \$REGISTRY \"owner()(address)\"
"
}

# ============================================================
# Router
# ============================================================

case "${1:-help}" in
    status)        cmd_status ;;
    read-policy)   cmd_read_policy "$2" ;;
    users)         cmd_users ;;
    hf)            cmd_hf "$2" ;;
    debt)          cmd_debt "$2" ;;
    balance)       cmd_balance "$2" ;;
    set-policy)    cmd_set_policy "$2" "$3" "$4" ;;
    deactivate)    cmd_deactivate ;;
    approve-usdc)  cmd_approve_usdc "$2" ;;
    deposit)       cmd_deposit "$2" "$3" ;;
    withdraw)      cmd_withdraw "$2" "$3" ;;
    execute)       cmd_execute "$2" "$3" "$4" ;;
    pause)         cmd_pause ;;
    unpause)       cmd_unpause ;;
    set-agent)     cmd_set_agent "$2" ;;
    call)          shift; cmd_call "$@" ;;
    send)          shift; cmd_send "$@" ;;
    help|*)        cmd_help ;;
esac
