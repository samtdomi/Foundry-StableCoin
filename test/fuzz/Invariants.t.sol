// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// Have our invariant aka properties

// what are our Invariants:

// 1. the total supply of DSC should be less than the total value of the collateral

// 2. Getter view functions should never revert  <----- evergreen invariant

import {Test, console} from "lib/forge-std/src/Test.sol";
import {StdInvariant} from "lib/forge-std/src/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DeployDSC deployDsc;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    Handler handler;

    // DSCEngine Constructor Arguments:
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    // Extra variable in HelperConfig - not in DSCEngine constructor
    uint256 deployerKey;

    function setUp() external {
        deployDsc = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployDsc.run();
        // get all necessary addresses for specific chain from helperConfig
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeConfig();

        handler = new Handler(dscEngine, dsc);
        // this line of code tells forge to run tons of fuzz / invariant tests on a specific contract
        targetContract(address(handler));

        // warning, dont call redeemCollateral unless there is collateral in the contract to redeem
    }

    function invariant_ProtocolMustHaveMoreValueThanTotalSupply() public view {
        // 1. get the value of all the collateral in the protocol
        // total supply of DSC stable coin (debt), get the value by calling totalSupply from dsc contract
        uint256 totalSupply = dsc.totalSupply();

        // 2. compare it to all the debt (dsc)
        // total amount of weth and wbtc that the protocol has as collateral
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));
        // converts the token collateral for each token to USD value
        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("weth value: ", wethValue);
        console.log("wbtc value: ", wbtcValue);
        console.log("total supply DSC: ", totalSupply);
        // console.log("Times Mint Function Is Called: ", handler.timesMintIsCalled);

        assert((wethValue + wbtcValue) >= totalSupply);
    }

    // getter / helper functions should not revert ever
    function invariant_gettersShouldNotRevert(address user, address tokenCollateral) public {
        dscEngine.getUserCollateral(user, tokenCollateral);
        dscEngine.getAccountInformation();
        dscEngine.getCollateralTokens();
    }
}
