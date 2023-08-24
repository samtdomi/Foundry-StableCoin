// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "lib/forge-std/src/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address ethUsdPriceFeed;
        address btcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetworkConfig public activeConfig;

    uint256 DefaultAnvilKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 1) {
            activeConfig = getEthMainnetConfig();
        } else if (block.chainid == 11155111) {
            activeConfig = getSepoliaEthConfig();
        } else if (block.chainid == 31337) {
            activeConfig = getAnvilConfig();
        }
    }

    function getEthMainnetConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory ethMainnetConfig = NetworkConfig({
            ethUsdPriceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            btcUsdPriceFeed: 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c,
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            wbtc: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            deployerKey: 1 // CHANGE THIS
        });

        return ethMainnetConfig;
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        NetworkConfig memory sepoliaConfig = NetworkConfig({
            ethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            btcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
            wbtc: 0xE6D22d565C860Bbeb2B411dFce91dD4B8F318594,
            deployerKey: vm.envUint("PrivateKey")
        });

        return sepoliaConfig;
    }

    function getAnvilConfig() public returns (NetworkConfig memory) {
        uint8 Decimals = 8;
        int256 EthUsdPrice = 1000e8;
        int256 BtcUsdPrice = 1000e8;

        vm.startBroadcast();

        // Creating ETH mock chainlink price feed and giving ETH the value of $1000
        MockV3Aggregator ethUsdMockPriceFeed = new MockV3Aggregator(Decimals, EthUsdPrice);
        // Deploys to get the mock erc20 token address / creates wETH token mock and assigns the user 500 wETH
        ERC20Mock wethMock = new ERC20Mock("WETH" , "WETH", msg.sender, 500e8);

        // Creating BTC mock chainlink price feed and giving BTC the value of $1000
        MockV3Aggregator btcUsdMockPriceFeed = new MockV3Aggregator(Decimals, BtcUsdPrice);
        // Deploys to get the mock erc20 token addres / creates wBTC token mock and assigns the user 500 wBTC
        ERC20Mock wbtcMock = new ERC20Mock("WBTC" , "WBTC", msg.sender, 500e8);

        vm.stopBroadcast();

        NetworkConfig memory anvilConfig = NetworkConfig({
            ethUsdPriceFeed: address(ethUsdMockPriceFeed),
            btcUsdPriceFeed: address(btcUsdMockPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployerKey: DefaultAnvilKey
        });

        return anvilConfig;
    }
}
