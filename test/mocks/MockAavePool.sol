// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/interfaces/IAavePool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockAavePool is IAavePool {
    // 可控的 HF 返回值
    mapping(address => uint256) public healthFactors;
    // 记录 repay 调用
    uint256 public lastRepayAmount;
    address public lastRepayUser;
    address public lastRepayAsset;
    uint256 public repayCallCount;

    // mock variableDebtToken 地址
    address public mockDebtToken;

    function setHealthFactor(address user, uint256 hf) external {
        healthFactors[user] = hf;
    }

    function setMockDebtToken(address _debtToken) external {
        mockDebtToken = _debtToken;
    }

    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) {
        return (0, 0, 0, 0, 0, healthFactors[user]);
    }

    function repay(
        address asset,
        uint256 amount,
        uint256, // interestRateMode
        address onBehalfOf
    ) external returns (uint256) {
        lastRepayAsset = asset;
        lastRepayAmount = amount;
        lastRepayUser = onBehalfOf;
        repayCallCount++;
        // 模拟从调用者转入 USDC
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        return amount;
    }

    function getReserveData(address) external view returns (ReserveData memory) {
        ReserveData memory data;
        data.variableDebtTokenAddress = mockDebtToken;
        return data;
    }

    // Fork 测试接口，mock 中不需要实现
    function supply(address, uint256, address, uint16) external {}
    function borrow(address, uint256, uint256, uint16, address) external {}
}
