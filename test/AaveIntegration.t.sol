// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AaveIntegration.sol";
import "./mocks/MockAavePool.sol";
import "./mocks/MockERC20.sol";

contract AaveIntegrationTest is Test {
    AaveIntegration public integration;
    MockAavePool public mockPool;
    MockERC20 public usdc;
    MockERC20 public debtToken;
    address public owner;
    address public vaultAddr;
    address public user1;

    function setUp() public {
        owner = address(this);
        vaultAddr = makeAddr("vault");
        user1 = makeAddr("user1");

        usdc = new MockERC20("USDC", "USDC", 6);
        debtToken = new MockERC20("aVariableDebtUSDC", "vdUSDC", 6);
        mockPool = new MockAavePool();
        mockPool.setMockDebtToken(address(debtToken));

        integration = new AaveIntegration(address(mockPool), address(usdc));
        integration.setVault(vaultAddr);
    }

    // ========== setVault ==========

    function test_SetVault_Success() public view {
        assertEq(integration.vault(), vaultAddr);
    }

    function test_SetVault_OnlyOwner_Reverts() public {
        AaveIntegration ai2 = new AaveIntegration(address(mockPool), address(usdc));
        vm.prank(user1);
        vm.expectRevert("Only owner");
        ai2.setVault(vaultAddr);
    }

    function test_SetVault_AlreadySet_Reverts() public {
        vm.expectRevert("Vault already set");
        integration.setVault(makeAddr("newVault"));
    }

    // ========== getHealthFactor ==========

    function test_GetHealthFactor_ParsesCorrectly() public {
        mockPool.setHealthFactor(user1, 1.5e18);
        uint256 hf = integration.getHealthFactor(user1);
        assertEq(hf, 1.5e18);
    }

    function test_GetHealthFactor_ReturnsZero_WhenNotSet() public view {
        uint256 hf = integration.getHealthFactor(user1);
        assertEq(hf, 0);
    }

    function test_GetHealthFactor_MultipleUsers() public {
        mockPool.setHealthFactor(user1, 1.2e18);
        address user2 = makeAddr("user2");
        mockPool.setHealthFactor(user2, 0.9e18);

        assertEq(integration.getHealthFactor(user1), 1.2e18);
        assertEq(integration.getHealthFactor(user2), 0.9e18);
    }

    // ========== getUserDebt ==========

    function test_GetUserDebt_ReturnsBalance() public {
        debtToken.mint(user1, 1000e6);
        uint256 debt = integration.getUserDebt(user1);
        assertEq(debt, 1000e6);
    }

    function test_GetUserDebt_ZeroWhenNoDebt() public view {
        uint256 debt = integration.getUserDebt(user1);
        assertEq(debt, 0);
    }

    // ========== repayOnBehalf ==========

    function test_RepayOnBehalf_ApprovesAndRepays() public {
        uint256 repayAmount = 500e6;
        // Mint USDC to the AaveIntegration contract (simulating transfer from Vault)
        usdc.mint(address(integration), repayAmount);

        vm.prank(vaultAddr);
        integration.repayOnBehalf(user1, repayAmount);

        assertEq(mockPool.lastRepayAmount(), repayAmount);
        assertEq(mockPool.lastRepayUser(), user1);
        assertEq(mockPool.lastRepayAsset(), address(usdc));
        assertEq(mockPool.repayCallCount(), 1);
        // USDC transferred from integration to mockPool
        assertEq(usdc.balanceOf(address(integration)), 0);
        assertEq(usdc.balanceOf(address(mockPool)), repayAmount);
    }

    function test_RepayOnBehalf_OnlyVault_Reverts() public {
        vm.prank(user1);
        vm.expectRevert("Only vault");
        integration.repayOnBehalf(user1, 100e6);
    }

    function test_RepayOnBehalf_OwnerCannotCall_Reverts() public {
        vm.expectRevert("Only vault");
        integration.repayOnBehalf(user1, 100e6);
    }

    function test_RepayOnBehalf_MultipleCalls() public {
        usdc.mint(address(integration), 1000e6);

        vm.startPrank(vaultAddr);
        integration.repayOnBehalf(user1, 300e6);
        assertEq(mockPool.repayCallCount(), 1);

        integration.repayOnBehalf(user1, 200e6);
        assertEq(mockPool.repayCallCount(), 2);
        assertEq(mockPool.lastRepayAmount(), 200e6);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(integration)), 500e6);
        assertEq(usdc.balanceOf(address(mockPool)), 500e6);
    }

    // ========== immutable fields ==========

    function test_Immutables() public view {
        assertEq(address(integration.aavePool()), address(mockPool));
        assertEq(integration.usdc(), address(usdc));
    }
}
