// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/GuardianRegistry.sol";
import "../src/AaveIntegration.sol";
import "../src/GuardianVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployScript is Script {
    // Aave V3 Sepolia addresses
    address constant AAVE_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;

    function run() external {
        address protocolAgent = vm.envAddress("PROTOCOL_AGENT");
        address protocolTreasury = vm.envAddress("PROTOCOL_TREASURY");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy GuardianRegistry
        GuardianRegistry registry = new GuardianRegistry();
        console.log("GuardianRegistry:", address(registry));

        // 2. Deploy AaveIntegration
        AaveIntegration aaveIntegration = new AaveIntegration(AAVE_POOL, USDC);
        console.log("AaveIntegration:", address(aaveIntegration));

        // 3. Deploy GuardianVault
        GuardianVault vault = new GuardianVault(
            IERC20(USDC),
            address(registry),
            address(aaveIntegration),
            protocolAgent,
            protocolTreasury
        );
        console.log("GuardianVault:", address(vault));

        // 4. Break circular dependency
        registry.setVault(address(vault));
        console.log("Registry.setVault done");

        // 5. Break circular dependency
        aaveIntegration.setVault(address(vault));
        console.log("AaveIntegration.setVault done");

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("Network: Sepolia");
        console.log("GuardianRegistry:", address(registry));
        console.log("AaveIntegration:", address(aaveIntegration));
        console.log("GuardianVault:", address(vault));
        console.log("ProtocolAgent:", protocolAgent);
        console.log("ProtocolTreasury:", protocolTreasury);
    }
}
