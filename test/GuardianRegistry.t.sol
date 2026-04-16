// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GuardianRegistry.sol";

contract GuardianRegistryTest is Test {
    GuardianRegistry public registry;
    address public owner;
    address public user1;
    address public user2;
    address public vault;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        vault = makeAddr("vault");

        registry = new GuardianRegistry();
        registry.setVault(vault);
    }

    // ========== setVault ==========

    function test_SetVault_Success() public view {
        assertEq(registry.vault(), vault);
    }

    function test_SetVault_OnlyOwner_Reverts() public {
        GuardianRegistry reg2 = new GuardianRegistry();
        vm.prank(user1);
        vm.expectRevert("Only owner");
        reg2.setVault(vault);
    }

    function test_SetVault_AlreadySet_Reverts() public {
        vm.expectRevert("Vault already set");
        registry.setVault(makeAddr("newVault"));
    }

    // ========== setPolicy happy path ==========

    function test_SetPolicy_Success() public {
        vm.prank(user1);
        registry.setPolicy(1.3e18, 500e6, 3600);

        GuardianRegistry.Policy memory p = registry.getPolicy(user1);
        assertEq(p.healthFactorThreshold, 1.3e18);
        assertEq(p.maxRepayPerTx, 500e6);
        assertEq(p.cooldownPeriod, 3600);
        assertEq(p.lastExecutionTime, 0);
        assertTrue(p.active);
    }

    function test_SetPolicy_EmitsEvent() public {
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit GuardianRegistry.PolicySet(user1, 1.3e18, 500e6);
        registry.setPolicy(1.3e18, 500e6, 3600);
    }

    function test_SetPolicy_AddsToRegisteredUsers() public {
        vm.prank(user1);
        registry.setPolicy(1.3e18, 500e6, 3600);

        address[] memory users = registry.getRegisteredUsers();
        assertEq(users.length, 1);
        assertEq(users[0], user1);
    }

    function test_UpdatePolicy_PreservesLastExecutionTime() public {
        // Set initial policy
        vm.prank(user1);
        registry.setPolicy(1.3e18, 500e6, 3600);

        // Simulate vault recording execution time
        vm.prank(vault);
        registry.recordExecution(user1);

        uint256 execTime = registry.getPolicy(user1).lastExecutionTime;
        assertGt(execTime, 0);

        // Update policy; lastExecutionTime should be preserved
        vm.prank(user1);
        registry.setPolicy(1.5e18, 300e6, 7200);

        GuardianRegistry.Policy memory p = registry.getPolicy(user1);
        assertEq(p.healthFactorThreshold, 1.5e18);
        assertEq(p.maxRepayPerTx, 300e6);
        assertEq(p.cooldownPeriod, 7200);
        assertEq(p.lastExecutionTime, execTime);
        assertTrue(p.active);
    }

    function test_UpdatePolicy_NoDuplicateInRegisteredUsers() public {
        vm.startPrank(user1);
        registry.setPolicy(1.3e18, 500e6, 3600);
        registry.setPolicy(1.5e18, 300e6, 7200);
        vm.stopPrank();

        address[] memory users = registry.getRegisteredUsers();
        assertEq(users.length, 1);
    }

    // ========== setPolicy boundary values ==========

    function test_SetPolicy_ThresholdTooLow_Reverts() public {
        vm.prank(user1);
        vm.expectRevert("Invalid threshold");
        registry.setPolicy(1.04e18, 500e6, 3600);
    }

    function test_SetPolicy_ThresholdTooHigh_Reverts() public {
        vm.prank(user1);
        vm.expectRevert("Invalid threshold");
        registry.setPolicy(1.81e18, 500e6, 3600);
    }

    function test_SetPolicy_ThresholdMinBoundary() public {
        vm.prank(user1);
        registry.setPolicy(1.05e18, 500e6, 3600);
        assertEq(registry.getPolicy(user1).healthFactorThreshold, 1.05e18);
    }

    function test_SetPolicy_ThresholdMaxBoundary() public {
        vm.prank(user1);
        registry.setPolicy(1.8e18, 500e6, 3600);
        assertEq(registry.getPolicy(user1).healthFactorThreshold, 1.8e18);
    }

    function test_SetPolicy_MaxRepayZero_Reverts() public {
        vm.prank(user1);
        vm.expectRevert("maxRepay must be > 0");
        registry.setPolicy(1.3e18, 0, 3600);
    }

    function test_SetPolicy_CooldownTooShort_Reverts() public {
        vm.prank(user1);
        vm.expectRevert("Cooldown min 1 hour");
        registry.setPolicy(1.3e18, 500e6, 3599);
    }

    function test_SetPolicy_CooldownMinBoundary() public {
        vm.prank(user1);
        registry.setPolicy(1.3e18, 500e6, 3600);
        assertEq(registry.getPolicy(user1).cooldownPeriod, 3600);
    }

    // ========== deactivate ==========

    function test_Deactivate_Success() public {
        vm.startPrank(user1);
        registry.setPolicy(1.3e18, 500e6, 3600);
        registry.deactivate();
        vm.stopPrank();

        assertFalse(registry.getPolicy(user1).active);
    }

    function test_Deactivate_EmitsEvent() public {
        vm.startPrank(user1);
        registry.setPolicy(1.3e18, 500e6, 3600);

        vm.expectEmit(true, false, false, false);
        emit GuardianRegistry.PolicyDeactivated(user1);
        registry.deactivate();
        vm.stopPrank();
    }

    function test_Deactivate_NotActive_Reverts() public {
        vm.prank(user1);
        vm.expectRevert("Not active");
        registry.deactivate();
    }

    function test_Deactivate_ThenReactivate_AddsDuplicate() public {
        // Deactivating then reactivating pushes to registeredUsers again (planned dedup logic)
        vm.startPrank(user1);
        registry.setPolicy(1.3e18, 500e6, 3600);
        registry.deactivate();
        registry.setPolicy(1.3e18, 500e6, 3600);
        vm.stopPrank();

        // When active=false, setPolicy pushes again, so length=2
        address[] memory users = registry.getRegisteredUsers();
        assertEq(users.length, 2);
    }

    // ========== recordExecution ==========

    function test_RecordExecution_Success() public {
        vm.prank(user1);
        registry.setPolicy(1.3e18, 500e6, 3600);

        vm.warp(1000);
        vm.prank(vault);
        registry.recordExecution(user1);

        assertEq(registry.getPolicy(user1).lastExecutionTime, 1000);
    }

    function test_RecordExecution_OnlyVault_Reverts() public {
        vm.prank(user1);
        registry.setPolicy(1.3e18, 500e6, 3600);

        vm.prank(user1);
        vm.expectRevert("Only vault");
        registry.recordExecution(user1);
    }

    // ========== getRegisteredUsers multiple users ==========

    function test_MultipleUsers() public {
        vm.prank(user1);
        registry.setPolicy(1.3e18, 500e6, 3600);

        vm.prank(user2);
        registry.setPolicy(1.5e18, 200e6, 7200);

        address[] memory users = registry.getRegisteredUsers();
        assertEq(users.length, 2);
        assertEq(users[0], user1);
        assertEq(users[1], user2);
    }

    // ========== getPolicy unregistered user ==========

    function test_GetPolicy_UnregisteredUser_ReturnsDefault() public view {
        GuardianRegistry.Policy memory p = registry.getPolicy(address(0xdead));
        assertEq(p.healthFactorThreshold, 0);
        assertEq(p.maxRepayPerTx, 0);
        assertEq(p.cooldownPeriod, 0);
        assertEq(p.lastExecutionTime, 0);
        assertFalse(p.active);
    }
}
