// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/PolicySmartWallet.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address owner = vm.envAddress("WALLET_OWNER");
        address trustedSigner = vm.envAddress("TRUSTED_SIGNER");
        address guardian = vm.envAddress("GUARDIAN");
        uint256 delayDuration = vm.envOr("DELAY_DURATION", uint256(3600));

        vm.startBroadcast(deployerKey);

        PolicySmartWallet wallet = new PolicySmartWallet(
            owner,
            trustedSigner,
            guardian,
            delayDuration
        );

        vm.stopBroadcast();

        console.log("PolicySmartWallet deployed at:", address(wallet));
        console.log("Owner:", owner);
        console.log("Trusted Signer:", trustedSigner);
        console.log("Guardian:", guardian);
        console.log("Delay Duration:", delayDuration);
    }
}
