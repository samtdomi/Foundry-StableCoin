// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

/**
 * @notice this contract has each function called by the Invariants test contract and
 * checks to see if the "assertEq" from the invariants test contract remains true
 * when running each function here, individually it checks the assertion with each function
 * and as whole, checks if the assertion is true when running all functions randomly
 * @notice handler is used to narrow down the functions from our smart contract that
 * we want to be included in the tests.
 */

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
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is StdInvariant, Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;
    MockV3Aggregator ethUsdMockPriceFeed;
    MockV3Aggregator btcUsdMockPriceFeed;

    // gets the max uint96 value
    uint256 MAX_DEPOSIT_VALUE = type(uint96).max;

    uint256 public timesMintIsCalled;

    address[] public usersWithCollateralDeposited;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdMockPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
        btcUsdMockPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(wbtc)));
    }

    // 1. Mint DSC
    function mintDsc(uint256 amount, uint256 addressSeed) public {
        // tell forge that if there are no users with collateral deposted, to revert
        // becasue that means no user can mint DSC becasue none have collateral to mint off of
        vm.assume(usersWithCollateralDeposited.length > 0);

        // chooses an address that has collateral deposited by randomly choosing
        // an index in the usersWithCollateralDeposited array
        address user = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];

        vm.startPrank(user);

        // makes sure user always mints the max amount of DSC that they can without going under their health factor
        // do this to ensure fuzz makes calls that will not revert to make the most out of the fuzz
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine._getAccountInformation(user);
        uint256 maxDscToMint = (collateralValueInUsd / 2) - totalDscMinted;

        amount = bound(amount, 1, maxDscToMint);

        // tells forge if maxDscToMint is 0 or less, revert
        vm.assume(maxDscToMint > 0);

        dscEngine.mintDsc(amount);
        vm.stopPrank();

        timesMintIsCalled++;
    }

    // 2. Deposit Collateral
    // in fuzz test's each function paramater will be given random values
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // dscEngine.depositCollateral(collateralSeed, amountCollateral);
        ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_VALUE);

        // mints mock erc20 token amount to be deposited as collateral, and approves
        // DSCEngine to transfer collateral token from msg.sender to itself when running depositCollateral
        vm.startPrank(msg.sender);
        collateralToken.mint(msg.sender, amountCollateral);
        collateralToken.approve(address(dscEngine), amountCollateral);

        dscEngine.depositCollateral(address(collateralToken), amountCollateral);
        vm.stopPrank();

        // potential problem: can doubble push if the address has already deposited collateral
        usersWithCollateralDeposited.push(msg.sender);
    }

    // 3. Redeem Collateral
    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getUserCollateral(msg.sender, address(collateralToken));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);

        // if the user has 0 collateral, the fuzzer will dsicard the current fuzz inputs and start -
        // a new fuzz run, becasue the user cant redeem 0 collateral, it will revert
        vm.assume(maxCollateralToRedeem > 0);

        dscEngine.redeemCollateral(address(collateralToken), amountCollateral);
    }

    // This Breaks Invariant Test Suite!!!! when the collateral token price plummets
    // function updateCollateralPrice(uint96 newPrice) public returns (uint96) {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdMockPriceFeed.updateAnswer(newPriceInt);
    // }

    ////////////////////////////////////////////////////////////////////////////////
    //////////     Helper Functions   //////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////

    // makes sure that the invariant test will always only choose accepted collateral token addresses
    function _getCollateralFromSeed(uint256 collateralSeed) public view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
