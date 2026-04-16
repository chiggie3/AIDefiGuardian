// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/GuardianRegistry.sol";
import "../../src/GuardianVault.sol";
import "../../src/AaveIntegration.sol";
import "../../src/interfaces/IAavePool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Integration tests against real Aave V3 contracts on a forked Sepolia network
/// Run with: SEPOLIA_RPC_URL=<url> forge test --match-contract GuardianForkTest -vvv
contract GuardianForkTest is Test {
    // ========== Aave V3 Sepolia addresses ==========
    address constant AAVE_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    address constant WETH = 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c;
    address constant ADDRESSES_PROVIDER = 0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A;

    // ========== Project contracts ==========
    GuardianRegistry public registry;
    GuardianVault public vault;
    AaveIntegration public aaveIntegration;

    // ========== Test roles ==========
    address public owner;
    address public agent;
    address public treasury;
    address public testUser;

    IAavePool public aavePool;
    address public aaveOracle;

    function setUp() public {
        // Fork Sepolia
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));

        owner = address(this);
        agent = makeAddr("agent");
        treasury = makeAddr("treasury");
        testUser = makeAddr("testUser");

        aavePool = IAavePool(AAVE_POOL);

        // Dynamically fetch Oracle address
        (bool ok, bytes memory data) = ADDRESSES_PROVIDER.staticcall(
            abi.encodeWithSignature("getPriceOracle()")
        );
        require(ok, "Failed to get oracle");
        aaveOracle = abi.decode(data, (address));

        // Deploy project contracts
        registry = new GuardianRegistry();
        aaveIntegration = new AaveIntegration(AAVE_POOL, USDC);
        vault = new GuardianVault(
            IERC20(USDC),
            address(registry),
            address(aaveIntegration),
            agent,
            treasury
        );

        // Break circular dependencies
        registry.setVault(address(vault));
        aaveIntegration.setVault(address(vault));

        // Provide assets for the test user
        deal(WETH, testUser, 10e18);
        deal(USDC, testUser, 50_000e6);

        // Sepolia pool has insufficient liquidity and supply cap is full
        // Deal USDC directly to the aToken contract to increase borrowable liquidity
        address USDC_ATOKEN = 0x16dA4541aD1807f4443d92D26044C1147406EB80;
        deal(USDC, USDC_ATOKEN, 500_000e6);
    }

    // ========== Helper functions ==========

    /// @dev User supplies WETH and borrows USDC on Aave to create a lending position
    function _createAavePosition(address user, uint256 supplyETH, uint256 borrowUSDC) internal {
        vm.startPrank(user);
        IERC20(WETH).approve(AAVE_POOL, supplyETH);
        aavePool.supply(WETH, supplyETH, user, 0);
        aavePool.borrow(USDC, borrowUSDC, 2, 0, user);
        vm.stopPrank();
    }

    /// @dev User sets Guardian policy and deposits protection budget
    function _setupGuardian(address user, uint256 budget) internal {
        vm.startPrank(user);
        registry.setPolicy(1.3e18, 500e6, 3600);
        IERC20(USDC).approve(address(vault), budget);
        vault.deposit(budget, user);
        vm.stopPrank();
    }

    // ========== Full protection flow ==========

    function test_FullProtectionFlow() public {
        // 1. User supplies 1 ETH on Aave and borrows USDC
        _createAavePosition(testUser, 1e18, 1500e6);

        uint256 hfAfterBorrow = aaveIntegration.getHealthFactor(testUser);
        emit log_named_uint("HF after borrow", hfAfterBorrow);
        assertGt(hfAfterBorrow, 1.3e18, "HF should be safe after initial borrow");

        // 2. Set Guardian protection policy + deposit 500 USDC budget
        _setupGuardian(testUser, 500e6);

        // 3. Simulate ETH price drop -> HF decreases
        //    Mock AaveOracle.getAssetPrice() to change the ETH price Aave sees
        //    Aave Oracle returns 8-decimal precision (e.g. ETH=$4000 -> 4000_00000000)
        //    HF = (ETH_price * 0.825) / 1500; for HF < 1.3, need price < $2364
        vm.mockCall(
            aaveOracle,
            abi.encodeWithSignature("getAssetPrice(address)", WETH),
            abi.encode(2200e8) // ETH drops from ~$4000 to $2200, HF ~ 1.21
        );

        uint256 hfAfterDrop = aaveIntegration.getHealthFactor(testUser);
        emit log_named_uint("HF after price drop", hfAfterDrop);
        assertLt(hfAfterDrop, 1.3e18, "HF should be below threshold after price drop");

        // 4. AI Agent executes protection repayment
        uint256 repayAmount = 300e6;
        vm.prank(agent);
        vault.executeRepayment(testUser, repayAmount, "ETH price dropped to $1500, repaying to protect position");

        // 5. Verify HF recovered
        uint256 hfAfterProtection = aaveIntegration.getHealthFactor(testUser);
        emit log_named_uint("HF after protection", hfAfterProtection);
        assertGt(hfAfterProtection, hfAfterDrop, "HF should improve after repayment");

        // 6. Verify fund flow
        assertGt(IERC20(USDC).balanceOf(treasury), 0, "Treasury should receive fee");

        // 7. Verify user's Vault balance decreased
        uint256 remaining = vault.convertToAssets(vault.balanceOf(testUser));
        assertLt(remaining, 500e6, "User budget should decrease");
        emit log_named_uint("Remaining budget", remaining);
    }

    // ========== Cooldown prevents repeated execution ==========

    function test_CooldownPreventsDoubleExecution() public {
        _createAavePosition(testUser, 1e18, 1500e6);
        _setupGuardian(testUser, 1000e6);

        // Mock price drop so HF < 1.3 but > 1.1 (does not trigger emergency bypass)
        vm.mockCall(
            aaveOracle,
            abi.encodeWithSignature("getAssetPrice(address)", WETH),
            abi.encode(2200e8)
        );

        // First execution succeeds
        vm.prank(agent);
        vault.executeRepayment(testUser, 200e6, "first protection");

        // Second execution within cooldown is rejected (HF not critical enough)
        vm.prank(agent);
        vm.expectRevert("Cooldown period: wait or HF must be critical");
        vault.executeRepayment(testUser, 200e6, "second too soon");

        // Can execute after cooldown period
        vm.warp(block.timestamp + 3601);
        vm.prank(agent);
        vault.executeRepayment(testUser, 200e6, "after cooldown");
    }

    // ========== Emergency bypasses cooldown ==========

    function test_EmergencyBypassesCooldown() public {
        _createAavePosition(testUser, 1e18, 1500e6);
        _setupGuardian(testUser, 1000e6);

        // Small price drop, HF < 1.3 but > 1.1
        vm.mockCall(
            aaveOracle,
            abi.encodeWithSignature("getAssetPrice(address)", WETH),
            abi.encode(2200e8)
        );

        vm.prank(agent);
        vault.executeRepayment(testUser, 100e6, "first");

        // Price crashes further -> HF drops to emergency level (< threshold - 0.2 = 1.1)
        // Need price < 1500 * 1.1 / 0.825 ~ $2000
        vm.mockCall(
            aaveOracle,
            abi.encodeWithSignature("getAssetPrice(address)", WETH),
            abi.encode(1800e8) // ETH crashes to $1800
        );

        uint256 hfEmergency = aaveIntegration.getHealthFactor(testUser);
        emit log_named_uint("HF emergency", hfEmergency);

        // Within cooldown but emergency situation; should be allowed to execute
        vm.prank(agent);
        vault.executeRepayment(testUser, 200e6, "emergency bypass");
    }

    // ========== Budget exhausted ==========

    function test_BudgetExhausted_Reverts() public {
        _createAavePosition(testUser, 1e18, 1500e6);

        // Deposit only 100 USDC budget
        vm.startPrank(testUser);
        registry.setPolicy(1.3e18, 500e6, 3600);
        IERC20(USDC).approve(address(vault), 100e6);
        vault.deposit(100e6, testUser);
        vm.stopPrank();

        vm.mockCall(
            aaveOracle,
            abi.encodeWithSignature("getAssetPrice(address)", WETH),
            abi.encode(2200e8)
        );

        // Request 500 repay but only 100 budget available
        vm.prank(agent);
        vm.expectRevert("Insufficient budget");
        vault.executeRepayment(testUser, 500e6, "not enough budget");
    }

    // ========== Inactive policy blocks execution ==========

    function test_InactivePolicyBlocks() public {
        _createAavePosition(testUser, 1e18, 1500e6);
        _setupGuardian(testUser, 500e6);

        // User deactivates policy
        vm.prank(testUser);
        registry.deactivate();

        vm.mockCall(
            aaveOracle,
            abi.encodeWithSignature("getAssetPrice(address)", WETH),
            abi.encode(2200e8)
        );

        vm.prank(agent);
        vm.expectRevert("Policy not active");
        vault.executeRepayment(testUser, 300e6, "policy inactive");
    }

    // ========== Verify real Aave data reads ==========

    function test_ReadRealAaveData() public {
        _createAavePosition(testUser, 1e18, 1000e6);

        // Read real HF via our AaveIntegration
        uint256 hf = aaveIntegration.getHealthFactor(testUser);
        emit log_named_uint("Real HF from Aave", hf);
        assertGt(hf, 1e18, "HF should be > 1.0 for healthy position");

        // Read real debt
        uint256 debt = aaveIntegration.getUserDebt(testUser);
        emit log_named_uint("Real debt from Aave", debt);
        // Aave precision rounding may cause 1 wei difference; use approximate assertion
        assertGe(debt, 999e6, "Debt should be approximately the borrowed amount");
    }

    // ========== Pause blocks execution ==========

    function test_PauseBlocksExecution() public {
        _createAavePosition(testUser, 1e18, 1500e6);
        _setupGuardian(testUser, 500e6);

        vault.pause();

        vm.mockCall(
            aaveOracle,
            abi.encodeWithSignature("getAssetPrice(address)", WETH),
            abi.encode(1500e8)
        );

        vm.prank(agent);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.executeRepayment(testUser, 300e6, "paused");
    }
}
