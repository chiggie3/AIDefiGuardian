// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/GuardianRegistry.sol";
import "../../src/GuardianVault.sol";
import "../../src/AaveIntegration.sol";
import "../../src/interfaces/IAavePool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Fork Sepolia 真实 Aave V3 合约的集成测试
/// 运行方式: SEPOLIA_RPC_URL=<url> forge test --match-contract GuardianForkTest -vvv
contract GuardianForkTest is Test {
    // ========== Aave V3 Sepolia 地址 ==========
    address constant AAVE_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    address constant WETH = 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c;
    address constant ADDRESSES_PROVIDER = 0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A;

    // ========== 项目合约 ==========
    GuardianRegistry public registry;
    GuardianVault public vault;
    AaveIntegration public aaveIntegration;

    // ========== 测试角色 ==========
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

        // 动态获取 Oracle 地址
        (bool ok, bytes memory data) = ADDRESSES_PROVIDER.staticcall(
            abi.encodeWithSignature("getPriceOracle()")
        );
        require(ok, "Failed to get oracle");
        aaveOracle = abi.decode(data, (address));

        // 部署项目合约
        registry = new GuardianRegistry();
        aaveIntegration = new AaveIntegration(AAVE_POOL, USDC);
        vault = new GuardianVault(
            IERC20(USDC),
            address(registry),
            address(aaveIntegration),
            agent,
            treasury
        );

        // 打破循环依赖
        registry.setVault(address(vault));
        aaveIntegration.setVault(address(vault));

        // 给测试用户准备资产
        deal(WETH, testUser, 10e18);
        deal(USDC, testUser, 50_000e6);

        // Sepolia 池子流动性不足且供应上限已满
        // 直接 deal USDC 到 aToken 合约地址，增加可借流动性
        address USDC_ATOKEN = 0x16dA4541aD1807f4443d92D26044C1147406EB80;
        deal(USDC, USDC_ATOKEN, 500_000e6);
    }

    // ========== 辅助函数 ==========

    /// @dev 用户在 Aave 中存 WETH 借 USDC，创建一个借贷仓位
    function _createAavePosition(address user, uint256 supplyETH, uint256 borrowUSDC) internal {
        vm.startPrank(user);
        IERC20(WETH).approve(AAVE_POOL, supplyETH);
        aavePool.supply(WETH, supplyETH, user, 0);
        aavePool.borrow(USDC, borrowUSDC, 2, 0, user);
        vm.stopPrank();
    }

    /// @dev 用户设置 Guardian 策略并存入保护预算
    function _setupGuardian(address user, uint256 budget) internal {
        vm.startPrank(user);
        registry.setPolicy(1.3e18, 500e6, 3600);
        IERC20(USDC).approve(address(vault), budget);
        vault.deposit(budget, user);
        vm.stopPrank();
    }

    // ========== 完整保护流程 ==========

    function test_FullProtectionFlow() public {
        // 1. 用户在 Aave 存 1 ETH，借 USDC
        _createAavePosition(testUser, 1e18, 1500e6);

        uint256 hfAfterBorrow = aaveIntegration.getHealthFactor(testUser);
        emit log_named_uint("HF after borrow", hfAfterBorrow);
        assertGt(hfAfterBorrow, 1.3e18, "HF should be safe after initial borrow");

        // 2. 设置 Guardian 保护策略 + 存入 500 USDC 预算
        _setupGuardian(testUser, 500e6);

        // 3. 模拟 ETH 价格下跌 → HF 降低
        //    通过 mock AaveOracle.getAssetPrice() 来改变 Aave 看到的 ETH 价格
        //    Aave Oracle 返回 8 位精度（如 ETH=$4000 → 4000_00000000）
        //    HF = (ETH_price × 0.825) / 1500，要 HF < 1.3 需要 price < $2364
        vm.mockCall(
            aaveOracle,
            abi.encodeWithSignature("getAssetPrice(address)", WETH),
            abi.encode(2200e8) // ETH 从 ~$4000 跌到 $2200，HF ≈ 1.21
        );

        uint256 hfAfterDrop = aaveIntegration.getHealthFactor(testUser);
        emit log_named_uint("HF after price drop", hfAfterDrop);
        assertLt(hfAfterDrop, 1.3e18, "HF should be below threshold after price drop");

        // 4. AI Agent 执行保护还款
        uint256 repayAmount = 300e6;
        vm.prank(agent);
        vault.executeRepayment(testUser, repayAmount, "ETH price dropped to $1500, repaying to protect position");

        // 5. 验证 HF 恢复
        uint256 hfAfterProtection = aaveIntegration.getHealthFactor(testUser);
        emit log_named_uint("HF after protection", hfAfterProtection);
        assertGt(hfAfterProtection, hfAfterDrop, "HF should improve after repayment");

        // 6. 验证资金流转
        assertGt(IERC20(USDC).balanceOf(treasury), 0, "Treasury should receive fee");

        // 7. 验证用户 Vault 余额减少
        uint256 remaining = vault.convertToAssets(vault.balanceOf(testUser));
        assertLt(remaining, 500e6, "User budget should decrease");
        emit log_named_uint("Remaining budget", remaining);
    }

    // ========== 冷却期阻止重复执行 ==========

    function test_CooldownPreventsDoubleExecution() public {
        _createAavePosition(testUser, 1e18, 1500e6);
        _setupGuardian(testUser, 1000e6);

        // mock 价格下跌到 HF < 1.3 但 > 1.1（不触发紧急豁免）
        vm.mockCall(
            aaveOracle,
            abi.encodeWithSignature("getAssetPrice(address)", WETH),
            abi.encode(2200e8)
        );

        // 第一次执行成功
        vm.prank(agent);
        vault.executeRepayment(testUser, 200e6, "first protection");

        // 冷却期内再次执行被拒（HF 不够紧急）
        vm.prank(agent);
        vm.expectRevert("Cooldown period: wait or HF must be critical");
        vault.executeRepayment(testUser, 200e6, "second too soon");

        // 冷却期过后可以执行
        vm.warp(block.timestamp + 3601);
        vm.prank(agent);
        vault.executeRepayment(testUser, 200e6, "after cooldown");
    }

    // ========== 紧急豁免冷却期 ==========

    function test_EmergencyBypassesCooldown() public {
        _createAavePosition(testUser, 1e18, 1500e6);
        _setupGuardian(testUser, 1000e6);

        // 价格小幅下跌，HF < 1.3 但 > 1.1
        vm.mockCall(
            aaveOracle,
            abi.encodeWithSignature("getAssetPrice(address)", WETH),
            abi.encode(2200e8)
        );

        vm.prank(agent);
        vault.executeRepayment(testUser, 100e6, "first");

        // 价格继续暴跌 → HF 跌到紧急水平（< threshold - 0.2 = 1.1）
        // 需要 price < 1500 × 1.1 / 0.825 ≈ $2000
        vm.mockCall(
            aaveOracle,
            abi.encodeWithSignature("getAssetPrice(address)", WETH),
            abi.encode(1800e8) // ETH 暴跌到 $1800
        );

        uint256 hfEmergency = aaveIntegration.getHealthFactor(testUser);
        emit log_named_uint("HF emergency", hfEmergency);

        // 冷却期内但紧急情况，应该可以执行
        vm.prank(agent);
        vault.executeRepayment(testUser, 200e6, "emergency bypass");
    }

    // ========== 预算耗尽 ==========

    function test_BudgetExhausted_Reverts() public {
        _createAavePosition(testUser, 1e18, 1500e6);

        // 只存 100 USDC 预算
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

        // 请求还 500 但只有 100 预算
        vm.prank(agent);
        vm.expectRevert("Insufficient budget");
        vault.executeRepayment(testUser, 500e6, "not enough budget");
    }

    // ========== 策略未激活 ==========

    function test_InactivePolicyBlocks() public {
        _createAavePosition(testUser, 1e18, 1500e6);
        _setupGuardian(testUser, 500e6);

        // 用户停用策略
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

    // ========== 验证真实 Aave 数据读取 ==========

    function test_ReadRealAaveData() public {
        _createAavePosition(testUser, 1e18, 1000e6);

        // 通过我们的 AaveIntegration 读取真实 HF
        uint256 hf = aaveIntegration.getHealthFactor(testUser);
        emit log_named_uint("Real HF from Aave", hf);
        assertGt(hf, 1e18, "HF should be > 1.0 for healthy position");

        // 读取真实债务
        uint256 debt = aaveIntegration.getUserDebt(testUser);
        emit log_named_uint("Real debt from Aave", debt);
        // Aave 精度舍入可能导致 debt 差 1 wei，用近似判断
        assertGe(debt, 999e6, "Debt should be approximately the borrowed amount");
    }

    // ========== 暂停阻止执行 ==========

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
