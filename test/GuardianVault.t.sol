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

        // 设置循环依赖
        registry.setVault(address(vault));
        aaveIntegration.setVault(address(vault));
    }

    // ========== 辅助函数 ==========

    function _setupUser(address user, uint256 deposit, uint256 hf, uint256 debt) internal {
        // 注册策略
        vm.prank(user);
        registry.setPolicy(1.3e18, 500e6, 3600);

        // 存入预算
        usdc.mint(user, deposit);
        vm.startPrank(user);
        usdc.approve(address(vault), deposit);
        vault.deposit(deposit, user);
        vm.stopPrank();

        // 设置 mock 数据
        mockPool.setHealthFactor(user, hf);
        debtToken.mint(user, debt);
    }

    // ========== 存取款 ==========

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

    // ========== executeRepayment 成功路径 ==========

    function test_ExecuteRepayment_Success() public {
        _setupUser(user1, 1000e6, 1.2e18, 5000e6);

        vm.warp(10000);

        vm.prank(agent);
        vault.executeRepayment(user1, 500e6, "HF dropping, repaying to protect position");

        // 协议费 0.1% = 500e6 * 10 / 10000 = 0.5e6
        uint256 fee = 500e6 * 10 / 10_000;
        uint256 repayAfterFee = 500e6 - fee;

        assertEq(usdc.balanceOf(treasury), fee);
        assertEq(mockPool.lastRepayAmount(), repayAfterFee);
        assertEq(mockPool.lastRepayUser(), user1);
        assertEq(mockPool.repayCallCount(), 1);

        // 用户余额减少
        assertEq(vault.convertToAssets(vault.balanceOf(user1)), 500e6);

        // lastExecutionTime 已更新
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
        // 存 600e6，还 500e6 后剩 100e6 < maxRepayPerTx(500e6)
        _setupUser(user1, 600e6, 1.2e18, 5000e6);

        vm.prank(agent);
        vm.expectEmit(true, false, false, true);
        emit GuardianVault.BudgetLow(user1, 100e6);
        vault.executeRepayment(user1, 500e6, "budget will be low");
    }

    function test_ExecuteRepayment_CapsAtDebt() public {
        // 债务只有 200e6，但请求还 500e6，应该只还 200e6
        _setupUser(user1, 1000e6, 1.2e18, 200e6);

        vm.prank(agent);
        vault.executeRepayment(user1, 500e6, "capped at debt");

        uint256 fee = 200e6 * 10 / 10_000;
        uint256 repayAfterFee = 200e6 - fee;

        assertEq(mockPool.lastRepayAmount(), repayAfterFee);
        assertEq(usdc.balanceOf(treasury), fee);
        // 用户只扣了 200e6
        assertEq(vault.convertToAssets(vault.balanceOf(user1)), 800e6);
    }

    // ========== executeRepayment 失败路径 ==========

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

        // 第一次执行
        vm.prank(agent);
        vault.executeRepayment(user1, 100e6, "first");

        // 冷却期内再次执行（HF 不够紧急）
        vm.warp(block.timestamp + 3599); // 差 1 秒
        vm.prank(agent);
        vm.expectRevert("Cooldown period: wait or HF must be critical");
        vault.executeRepayment(user1, 100e6, "too soon");
    }

    function test_ExecuteRepayment_CooldownPassed_Success() public {
        _setupUser(user1, 1000e6, 1.2e18, 5000e6);

        vm.prank(agent);
        vault.executeRepayment(user1, 100e6, "first");

        // 冷却期过后可以执行
        vm.warp(block.timestamp + 3600);
        vm.prank(agent);
        vault.executeRepayment(user1, 100e6, "after cooldown");

        assertEq(mockPool.repayCallCount(), 2);
    }

    function test_ExecuteRepayment_EmergencyBypassCooldown() public {
        _setupUser(user1, 1000e6, 1.3e18, 5000e6);

        // 第一次执行
        vm.prank(agent);
        vault.executeRepayment(user1, 100e6, "first");

        // 冷却期内，但 HF 跌到紧急水平（< 1.3e18 - 0.2e18 = 1.1e18）
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
        _setupUser(user1, 1000e6, 1.2e18, 0); // 无债务

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
