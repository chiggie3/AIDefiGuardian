// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract GuardianRegistry {
    struct Policy {
        uint256 healthFactorThreshold; // 触发阈值，e.g. 1.3e18 (18位小数，Aave标准)
        uint256 maxRepayPerTx;         // 单次最大还款 USDC (6位小数, e.g. 500e6)
        uint256 cooldownPeriod;        // 两次操作冷却期 (seconds, 最短3600=1小时)
        uint256 lastExecutionTime;     // 上次执行时间戳
        bool active;                   // 策略是否激活
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
    // 用户自己调用，设置保护策略，三个参数：
    // healthFactorThreshold — 健康因子阈值（1.05~1.8），低于这个值就触发保护操作
    // maxRepayPerTx — 单次最多还多少 USDC，防止一次还太多
    // cooldownPeriod — 冷却时间（最少 1 小时），防止频繁操作
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

    // Vault 替用户执行完一次还款后，回调这个函数更新 lastExecutionTime，用来配合 cooldownPeriod 做冷却判断。
    function recordExecution(address user) external onlyVault {
        policies[user].lastExecutionTime = block.timestamp;
    }
}
