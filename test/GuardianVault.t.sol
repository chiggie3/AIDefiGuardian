// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GuardianVault.sol";
import "../src/GuardianRegistry.sol";
import "../src/AaveIntegration.sol";
import "./mocks/MockAavePool.sol";
import "./mocks/MockERC20.sol";

contract GuardianVaultTest is Test {
    GuardianVault public vault;
    GuardianRegistry public registry;
    AaveIntegration public aaveIntegration;
    MockAavePool public mockPool;
    MockERC20 public usdc;
    MockERC20 public debtToken;

    address public owner;
    address public agent;
    address public treasury;
    address public user1;
    address public user2;

    function setUp() public {
        owner = address(this);
        agent = makeAddr("agent");
        treasury = makeAddr("treasury");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        usdc = new MockERC20("USDC", "USDC", 6);
        debtToken = new MockERC20("vdUSDC", "vdUSDC", 6);

        mockPool = new MockAavePool();
        mockPool.setMockDebtToken(address(debtToken));

        registry = new GuardianRegistry();
        aaveIntegration = new AaveIntegration(address(mockPool), address(usdc));

        vault = new GuardianVault(
            IERC20(address(usdc)),
            address(registry),
            address(aaveIntegration),
            agent,
            treasury
        );

        // Set up circular dependencies
        registry.setVault(address(vault));
        aaveIntegration.setVault(address(vault));
    }

    // ========== Helper functions ==========

    function _setupUser(address user, uint256 deposit, uint256 hf, uint256 debt) internal {
        // Register policy
        vm.prank(user);
        registry.setPolicy(1.3e18, 500e6, 3600);

        // Deposit budget
        usdc.mint(user, deposit);
        vm.startPrank(user);
        usdc.approve(address(vault), deposit);
        vault.deposit(deposit, user);
        vm.stopPrank();

        // Set mock data
        mockPool.setHealthFactor(user, hf);
        debtToken.mint(user, debt);
    }

    // ========== Deposit & Withdraw ==========

    function test_Deposit_Success() public {
        usdc.mint(user1, 1000e6);
        vm.startPrank(user1);
        usdc.approve(address(vault), 1000e6);
        vault.deposit(1000e6, user1);
        vm.stopPrank();

        assertEq(vault.balanceOf(user1), 1000e6);
        assertEq(usdc.balanceOf(address(vault)), 1000e6);
    }

    function test_Withdraw_Success() public {
        usdc.mint(user1, 1000e6);
        vm.startPrank(user1);
        usdc.approve(address(vault), 1000e6);
        vault.deposit(1000e6, user1);
        vault.withdraw(500e6, user1, user1);
        vm.stopPrank();

        assertEq(usdc.balanceOf(user1), 500e6);
        assertEq(usdc.balanceOf(address(vault)), 500e6);
    }

    function test_Deposit_ZeroAmount_MintsZeroShares() public {
        vm.prank(user1);
        uint256 shares = vault.deposit(0, user1);
        assertEq(shares, 0);
        assertEq(vault.balanceOf(user1), 0);
    }

    // ========== executeRepayment success path ==========

    function test_ExecuteRepayment_Success() public {
        _setupUser(user1, 1000e6, 1.2e18, 5000e6);

        vm.warp(10000);

        vm.prank(agent);
        vault.executeRepayment(user1, 500e6, "HF dropping, repaying to protect position");

        // Protocol fee 0.1% = 500e6 * 10 / 10000 = 0.5e6
        uint256 fee = 500e6 * 10 / 10_000;
        uint256 repayAfterFee = 500e6 - fee;

        assertEq(usdc.balanceOf(treasury), fee);
        assertEq(mockPool.lastRepayAmount(), repayAfterFee);
        assertEq(mockPool.lastRepayUser(), user1);
        assertEq(mockPool.repayCallCount(), 1);

        // User balance decreased
        assertEq(vault.convertToAssets(vault.balanceOf(user1)), 500e6);

        // lastExecutionTime updated
        assertEq(registry.getPolicy(user1).lastExecutionTime, 10000);
    }

    function test_ExecuteRepayment_EmitsProtectionExecuted() public {
        _setupUser(user1, 1000e6, 1.2e18, 5000e6);

        vm.prank(agent);
        vm.expectEmit(true, false, false, false);
        emit GuardianVault.ProtectionExecuted(user1, 500e6, 1.2e18, 1.2e18, "test reason", 1);
        vault.executeRepayment(user1, 500e6, "test reason");
    }

    function test_ExecuteRepayment_EmitsBudgetLow() public {
        // Deposit 600e6, after repaying 500e6, remaining 100e6 < maxRepayPerTx(500e6)
        _setupUser(user1, 600e6, 1.2e18, 5000e6);

        vm.prank(agent);
        vm.expectEmit(true, false, false, true);
        emit GuardianVault.BudgetLow(user1, 100e6);
        vault.executeRepayment(user1, 500e6, "budget will be low");
    }

    function test_ExecuteRepayment_CapsAtDebt() public {
        // Debt is only 200e6, but requesting 500e6 repay; should only repay 200e6
        _setupUser(user1, 1000e6, 1.2e18, 200e6);

        vm.prank(agent);
        vault.executeRepayment(user1, 500e6, "capped at debt");

        uint256 fee = 200e6 * 10 / 10_000;
        uint256 repayAfterFee = 200e6 - fee;

        assertEq(mockPool.lastRepayAmount(), repayAfterFee);
        assertEq(usdc.balanceOf(treasury), fee);
        // User only charged 200e6
        assertEq(vault.convertToAssets(vault.balanceOf(user1)), 800e6);
    }

    // ========== executeRepayment failure path ==========

    function test_ExecuteRepayment_UnauthorizedAgent_Reverts() public {
        _setupUser(user1, 1000e6, 1.2e18, 5000e6);

        vm.prank(user1);
        vm.expectRevert("Unauthorized agent");
        vault.executeRepayment(user1, 500e6, "not agent");
    }

    function test_ExecuteRepayment_PolicyInactive_Reverts() public {
        _setupUser(user1, 1000e6, 1.2e18, 5000e6);

        vm.prank(user1);
        registry.deactivate();

        vm.prank(agent);
        vm.expectRevert("Policy not active");
        vault.executeRepayment(user1, 500e6, "inactive");
    }

    function test_ExecuteRepayment_CooldownNotPassed_Reverts() public {
        _setupUser(user1, 1000e6, 1.2e18, 5000e6);

        // First execution
        vm.prank(agent);
        vault.executeRepayment(user1, 100e6, "first");

        // Execute again within cooldown (HF not critical enough)
        vm.warp(block.timestamp + 3599); // 1 second short
        vm.prank(agent);
        vm.expectRevert("Cooldown period: wait or HF must be critical");
        vault.executeRepayment(user1, 100e6, "too soon");
    }

    function test_ExecuteRepayment_CooldownPassed_Success() public {
        _setupUser(user1, 1000e6, 1.2e18, 5000e6);

        vm.prank(agent);
        vault.executeRepayment(user1, 100e6, "first");

        // Can execute after cooldown period
        vm.warp(block.timestamp + 3600);
        vm.prank(agent);
        vault.executeRepayment(user1, 100e6, "after cooldown");

        assertEq(mockPool.repayCallCount(), 2);
    }

    function test_ExecuteRepayment_EmergencyBypassCooldown() public {
        _setupUser(user1, 1000e6, 1.3e18, 5000e6);

        // First execution
        vm.prank(agent);
        vault.executeRepayment(user1, 100e6, "first");

        // Within cooldown, but HF drops to emergency level (< 1.3e18 - 0.2e18 = 1.1e18)
        mockPool.setHealthFactor(user1, 1.05e18);
        vm.prank(agent);
        vault.executeRepayment(user1, 100e6, "emergency bypass");

        assertEq(mockPool.repayCallCount(), 2);
    }

    function test_ExecuteRepayment_ExceedsMaxRepay_Reverts() public {
        _setupUser(user1, 1000e6, 1.2e18, 5000e6);

        vm.prank(agent);
        vm.expectRevert("Exceeds max repay");
        vault.executeRepayment(user1, 501e6, "too much");
    }

    function test_ExecuteRepayment_InsufficientBudget_Reverts() public {
        _setupUser(user1, 100e6, 1.2e18, 5000e6);

        vm.prank(agent);
        vm.expectRevert("Insufficient budget");
        vault.executeRepayment(user1, 500e6, "no budget");
    }

    function test_ExecuteRepayment_NoDebt_Reverts() public {
        _setupUser(user1, 1000e6, 1.2e18, 0); // No debt

        vm.prank(agent);
        vm.expectRevert("No debt to repay");
        vault.executeRepayment(user1, 500e6, "no debt");
    }

    // ========== Pause ==========

    function test_Pause_StopsExecution() public {
        _setupUser(user1, 1000e6, 1.2e18, 5000e6);

        vault.pause();

        vm.prank(agent);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.executeRepayment(user1, 100e6, "paused");
    }

    function test_Unpause_ResumesExecution() public {
        _setupUser(user1, 1000e6, 1.2e18, 5000e6);

        vault.pause();
        vault.unpause();

        vm.prank(agent);
        vault.executeRepayment(user1, 100e6, "resumed");
        assertEq(mockPool.repayCallCount(), 1);
    }

    function test_Pause_OnlyOwner_Reverts() public {
        vm.prank(user1);
        vm.expectRevert("Only owner");
        vault.pause();
    }

    function test_Unpause_OnlyOwner_Reverts() public {
        vault.pause();
        vm.prank(user1);
        vm.expectRevert("Only owner");
        vault.unpause();
    }

    // ========== setProtocolAgent ==========

    function test_SetProtocolAgent_Success() public {
        address newAgent = makeAddr("newAgent");
        vault.setProtocolAgent(newAgent);
        assertEq(vault.protocolAgent(), newAgent);
    }

    function test_SetProtocolAgent_OnlyOwner_Reverts() public {
        vm.prank(user1);
        vm.expectRevert("Only owner");
        vault.setProtocolAgent(makeAddr("newAgent"));
    }

    function test_SetProtocolAgent_OldAgentLosesAccess() public {
        _setupUser(user1, 1000e6, 1.2e18, 5000e6);

        address newAgent = makeAddr("newAgent");
        vault.setProtocolAgent(newAgent);

        vm.prank(agent); // old agent
        vm.expectRevert("Unauthorized agent");
        vault.executeRepayment(user1, 100e6, "old agent");

        vm.prank(newAgent);
        vault.executeRepayment(user1, 100e6, "new agent");
        assertEq(mockPool.repayCallCount(), 1);
    }

    // ========== immutables ==========

    function test_Immutables() public view {
        assertEq(address(vault.registry()), address(registry));
        assertEq(address(vault.aaveIntegration()), address(aaveIntegration));
        assertEq(vault.protocolTreasury(), treasury);
        assertEq(vault.protocolAgent(), agent);
    }

    function test_ERC20Metadata() public view {
        assertEq(vault.name(), "Guardian USDC");
        assertEq(vault.symbol(), "gUSDC");
        assertEq(vault.decimals(), 6);
    }
}
