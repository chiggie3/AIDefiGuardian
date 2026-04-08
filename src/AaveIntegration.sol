// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IAavePool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AaveIntegration {
    IAavePool public immutable aavePool;
    address public immutable usdc;
    address public vault;
    address public owner;

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

    constructor(address _aavePool, address _usdc) {
        aavePool = IAavePool(_aavePool);
        usdc = _usdc;
        owner = msg.sender;
    }

    function setVault(address _vault) external {
        require(msg.sender == owner, "Only owner");
        require(vault == address(0), "Vault already set");
        vault = _vault;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        (, , , , , uint256 healthFactor) = aavePool.getUserAccountData(user);
        return healthFactor;
    }

    function getUserDebt(address user) external view returns (uint256) {
        IAavePool.ReserveData memory reserve = aavePool.getReserveData(usdc);
        return IERC20(reserve.variableDebtTokenAddress).balanceOf(user);
    }

    function repayOnBehalf(address user, uint256 amount) external onlyVault {
        IERC20(usdc).approve(address(aavePool), amount);
        aavePool.repay(usdc, amount, 2, user);
    }
}
