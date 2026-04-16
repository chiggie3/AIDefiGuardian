// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./GuardianRegistry.sol";
import "./AaveIntegration.sol";

contract GuardianVault is ERC4626, ReentrancyGuard, Pausable {
    GuardianRegistry public immutable registry;
    AaveIntegration public immutable aaveIntegration;
    address public immutable protocolTreasury;

    address public protocolAgent;
    address public owner;

    event ProtectionExecuted(
        address indexed user,
        uint256 amountRepaid,
        uint256 healthFactorBefore,
        uint256 healthFactorAfter,
        string aiReasoning,
        uint256 timestamp
    );

    event BudgetLow(address indexed user, uint256 remainingBudget);

    constructor(
        IERC20 _usdc,
        address _registry,
        address _aaveIntegration,
        address _protocolAgent,
        address _protocolTreasury
    ) ERC4626(_usdc) ERC20("Guardian USDC", "gUSDC") {
        registry = GuardianRegistry(_registry);
        aaveIntegration = AaveIntegration(_aaveIntegration);
        protocolAgent = _protocolAgent;
        protocolTreasury = _protocolTreasury;
        owner = msg.sender;
    }

    function executeRepayment(
        address user,
        uint256 repayAmount,
        string calldata aiReasoning
    ) external nonReentrant whenNotPaused {
        require(msg.sender == protocolAgent, "Unauthorized agent");

        GuardianRegistry.Policy memory policy = registry.getPolicy(user);
        require(policy.active, "Policy not active");

        uint256 hfBefore = aaveIntegration.getHealthFactor(user);

        // Two-tier cooldown: normal cooldown + emergency bypass (HF < threshold - 0.2)
        {
            bool inCooldown = policy.lastExecutionTime > 0 && block.timestamp < policy.lastExecutionTime + policy.cooldownPeriod;
            bool isEmergency = hfBefore < policy.healthFactorThreshold - 0.2e18;
            require(!inCooldown || isEmergency, "Cooldown period: wait or HF must be critical");
        }

        require(repayAmount <= policy.maxRepayPerTx, "Exceeds max repay");
        require(convertToAssets(balanceOf(user)) >= repayAmount, "Insufficient budget");

        // Actual repay amount capped at user's debt
        uint256 actualRepay;
        {
            uint256 userDebt = aaveIntegration.getUserDebt(user);
            actualRepay = repayAmount > userDebt ? userDebt : repayAmount;
        }
        require(actualRepay > 0, "No debt to repay");

        // Protocol fee 0.1%
        uint256 fee = actualRepay * 10 / 10_000;

        // Withdraw USDC from user's shares
        // caller=user skips allowance check, receiver=vault keeps USDC in the contract
        _withdraw(user, address(this), user, actualRepay, previewWithdraw(actualRepay));

        // Transfer fee to treasury, send remainder to AaveIntegration for repayment
        IERC20(asset()).transfer(protocolTreasury, fee);
        IERC20(asset()).transfer(address(aaveIntegration), actualRepay - fee);
        aaveIntegration.repayOnBehalf(user, actualRepay - fee);

        registry.recordExecution(user);

        emit ProtectionExecuted(
            user, actualRepay, hfBefore, aaveIntegration.getHealthFactor(user), aiReasoning, block.timestamp
        );

        // Low balance warning
        uint256 remaining = convertToAssets(balanceOf(user));
        if (remaining < policy.maxRepayPerTx) {
            emit BudgetLow(user, remaining);
        }
    }

    function pause() external {
        require(msg.sender == owner, "Only owner");
        _pause();
    }

    function unpause() external {
        require(msg.sender == owner, "Only owner");
        _unpause();
    }

    function setProtocolAgent(address _newAgent) external {
        require(msg.sender == owner, "Only owner");
        protocolAgent = _newAgent;
    }
}
