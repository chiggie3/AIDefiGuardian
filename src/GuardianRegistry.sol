// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract GuardianRegistry {
    struct Policy {
        uint256 healthFactorThreshold; // Trigger threshold, e.g. 1.3e18 (18 decimals, Aave standard)
        uint256 maxRepayPerTx;         // Max repayment per tx in USDC (6 decimals, e.g. 500e6)
        uint256 cooldownPeriod;        // Cooldown between executions (seconds, min 3600 = 1 hour)
        uint256 lastExecutionTime;     // Timestamp of last execution
        bool active;                   // Whether the policy is active
    }

    mapping(address => Policy) public policies;
    address[] public registeredUsers;

    address public vault;
    address public owner;

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

    event PolicySet(address indexed user, uint256 threshold, uint256 maxRepay);
    event PolicyDeactivated(address indexed user);

    constructor() {
        owner = msg.sender;
    }

    function setVault(address _vault) external {
        require(msg.sender == owner, "Only owner");
        require(vault == address(0), "Vault already set");
        vault = _vault;
    }

    // setPolicy
    // Called by the user to configure their protection policy with three parameters:
    // healthFactorThreshold — Health factor threshold (1.05~1.8); protection triggers when HF drops below this value
    // maxRepayPerTx — Max USDC to repay per transaction, prevents repaying too much at once
    // cooldownPeriod — Cooldown duration (min 1 hour), prevents frequent executions
    function setPolicy(
        uint256 healthFactorThreshold,
        uint256 maxRepayPerTx,
        uint256 cooldownPeriod
    ) external {
        require(healthFactorThreshold >= 1.05e18 && healthFactorThreshold <= 1.8e18, "Invalid threshold");
        require(maxRepayPerTx > 0, "maxRepay must be > 0");
        require(cooldownPeriod >= 3600, "Cooldown min 1 hour");

        if (!policies[msg.sender].active) {
            registeredUsers.push(msg.sender);
        }

        policies[msg.sender] = Policy({
            healthFactorThreshold: healthFactorThreshold,
            maxRepayPerTx: maxRepayPerTx,
            cooldownPeriod: cooldownPeriod,
            lastExecutionTime: policies[msg.sender].lastExecutionTime,
            active: true
        });
        emit PolicySet(msg.sender, healthFactorThreshold, maxRepayPerTx);
    }

    function deactivate() external {
        require(policies[msg.sender].active, "Not active");
        policies[msg.sender].active = false;
        emit PolicyDeactivated(msg.sender);
    }

    function getPolicy(address user) external view returns (Policy memory) {
        return policies[user];
    }

    function getRegisteredUsers() external view returns (address[] memory) {
        return registeredUsers;
    }

    // Called by the Vault after executing a repayment on behalf of the user, updates lastExecutionTime for cooldown enforcement.
    function recordExecution(address user) external onlyVault {
        policies[user].lastExecutionTime = block.timestamp;
    }
}
