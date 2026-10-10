// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Migraine} from "../src/Migraine.sol";

/// @notice Deploys `Migraine` from environment variables.
/// @dev Required env: TOKEN_A, TOKEN_B, VAULT_WALLET, RATE_NUMERATOR, RATE_DENOMINATOR.
///      Example:
///        TOKEN_A=0x... TOKEN_B=0x... VAULT_WALLET=0x... RATE_NUMERATOR=25 RATE_DENOMINATOR=10 \
///        forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
contract Deploy is Script {
    function run() external returns (Migraine redeemer) {
        address tokenA = vm.envAddress("TOKEN_A");
        address tokenB = vm.envAddress("TOKEN_B");
        address wallet = vm.envAddress("VAULT_WALLET");
        uint256 num = vm.envUint("RATE_NUMERATOR");
        uint256 den = vm.envUint("RATE_DENOMINATOR");

        vm.startBroadcast();
        redeemer = new Migraine(IERC20(tokenA), IERC20(tokenB), wallet, num, den);
        vm.stopBroadcast();
    }
}
