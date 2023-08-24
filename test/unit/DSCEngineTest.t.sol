// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "lib/forge-std/src/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    /**
     * Type Declarations
     */
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    DeployDSC deployDsc;
    ERC20Mock erc20Mock;

    /**
     * DSCEngine Constructor Paramaters
     */
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    // Extra variable in HelperConfig - not in DSCEngine constructor
    uint256 deployerKey;

    /**
     * Other State Variables
     */
    address public testUser = makeAddr("user");
    uint256 public userStartingErc20Balance = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;

    /**
     * SETUP FUNCTION
     * 1. runs deploy script which deploys and returns new |:
     * 1a. dsc contract
     * 1b. dscEngine contract
     * 1c. helperConfig contract
     * 2. gets the correct address from the helperConfig for each collateral token and price feed
     * 3. mints and sends the testUser 10 ether
     */
    function setUp() public {
        deployDsc = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployDsc.run();
        // get all necessary addresses for specific chain from helperConfig
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeConfig();
        // mint the newly created user 10 ether
        ERC20Mock(weth).mint(testUser, userStartingErc20Balance);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////    Constructor Test's    /////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAdresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAdresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        vm.expectRevert();
        new DSCEngine(tokenAddresses, priceFeedAdresses, address(dsc));
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //////////////     Price Feed Test's    ///////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /**
     * @dev if deploying to local chain (anvil) , the helperConfig will deploy
     * mock priceFeeds for ETH and BTC and make their price (1 ETH / $1000) & (1 BTC / $1000)
     */
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18; // 15 ETH
        // ETH price is 1 / $1000  - $1000 per ETH
        // 15 ETH * $1000 = $15,000
        uint256 expectedValue = 15000e18;
        uint256 actualUsdValue = dscEngine.getUsdValue(weth, ethAmount);

        assertEq(expectedValue, actualUsdValue);
    }

    /**
     * @dev if deploying to local chain (anvil) , the helperConfig will deploy
     * mock priceFeeds for ETH and BTC and make their price (1 ETH / $1000) & (1 BTC / $1000)
     */
    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // $1000 ETH/USD price / 100 = 0.01 ETH
        uint256 expectedWeth = 0.01 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);

        assertEq(expectedWeth, actualWeth);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////     depositCollateral Test's    ///////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////

    modifier depositedCollateral() {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscEngine), 10 ether);
        dscEngine.depositCollateral(weth, 1 ether);
        vm.stopPrank();
        _;
    }

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert();
        dscEngine.depositCollateral(weth, 0);

        vm.stopPrank();
    }

    function testRevertsWithUnnaprovedCollateralToken() public {
        // create a new token to enter its address as the collateral token
        ERC20Mock ranToken = new ERC20Mock("RAN" , "RAN", testUser, 1 ether);

        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert();
        dscEngine.depositCollateral(address(ranToken), 1 ether);

        vm.stopPrank();
    }

    function testCollateralIsDepositedAndUserAccountUpdated() public {
        uint256 startingCollateral = dscEngine.getUserCollateral(address(testUser), weth);

        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscEngine), 2 ether);
        dscEngine.depositCollateral(weth, 1 ether);
        vm.stopPrank();

        uint256 endingCollateral = dscEngine.getUserCollateral(address(testUser), weth);

        assertEq(endingCollateral - startingCollateral, 1 ether);
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(testUser);
        // 1 ether was deposited by testUser using the modifier "depositedCollateral"
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedCollateralInEthToken = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(1 ether, expectedCollateralInEthToken);
    }

    // function testCollateralAmountTransferredFromUserToDscEngineContract() public {
    //     uint256 startingBalance = dscEngine.getDscEngineBalance();

    //     vm.startPrank(testUser);

    //     ERC20Mock(weth).approve(address(dscEngine), 2 ether);

    //     // vm.expectEmit();
    //     // // emit the event we expect to see during the next function call
    //     // emit DSCEngine.CollateralTransferredFromUserToDscEngine(address(testUser), address(dscEngine), 1 ether);
    //     // // call the function which should emit the event we are expecting

    //     dscEngine.depositCollateral(weth, 1 ether);

    //     vm.stopPrank();

    //     uint256 endingBalance = dscEngine.getDscEngineBalance();
    //     // endingBalance = endingBalance * 1 ether;
    //     // assertEq(endingBalance, (startingBalance + 1 ether));

    //     assert(dscEngine.getDscEngineBalance() > 0);

    //     assert(endingBalance > startingBalance);
    // }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////     depositCollateralAndMintDsc Test's    /////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function testUserCanDepositCollateralAndUserCollateralBalanceUpdated() public {
        uint256 startingCollateral = dscEngine.getUserCollateral(address(testUser), weth);

        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscEngine), 2 ether);
        dscEngine.depositCollateralAndMintDsc(weth, 1 ether, 1);
        vm.stopPrank();

        uint256 endingCollateral = dscEngine.getUserCollateral(address(testUser), weth);

        assertEq((startingCollateral + 1 ether), endingCollateral);
    }

    function testMintBalanceUpdatedAfterMinting() public {
        (uint256 startingBalance,) = dscEngine.getAccountInformation(address(testUser));

        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscEngine), 2 ether);
        dscEngine.depositCollateralAndMintDsc(weth, 1 ether, 1);
        vm.stopPrank();

        (uint256 endingBalance,) = dscEngine.getAccountInformation(address(testUser));

        assertEq(endingBalance - startingBalance, 1);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////     mintDsc Test's        /////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // wETH mock price feed price is $1,000/usd
    // 1 ETH = $1,000
    // max amount DSC user can have with 1 ETH collateral is 500

    // deposits 1 ether (weth) as colalteral
    modifier depositTestUserCollateral() {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscEngine), 2 ether);
        dscEngine.depositCollateral(weth, 1 ether);
        vm.stopPrank();
        _;
    }

    /**
     * @notice testUser will try to mint without first depositing any colalteral,
     * therefore, their health factor should be below the threshold
     */
    function revertsIfUsersHealthFactorIsTooLow() public {
        vm.expectRevert();
        vm.startPrank(testUser);

        dscEngine.mintDsc(1);

        vm.stopPrank();
    }

    // modifier deposits 1 wETH as collateral for testUser - can have max 500 DSC
    function testUserMintsDscAndUserAcoountUpdatedWithMintAmount() public depositTestUserCollateral {
        (uint256 startingBalance,) = dscEngine.getAccountInformation(address(testUser));

        vm.startPrank(testUser);
        dscEngine.mintDsc(100);
        vm.stopPrank();

        (uint256 endingBalance,) = dscEngine.getAccountInformation(address(testUser));

        assertEq(startingBalance + 100, endingBalance);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////    redeemCollateral Test's         ////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // deposits 2 ETH as collateral for testUser
    modifier testUserDepositsEthCollateral() {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscEngine), 10 ether);
        dscEngine.depositCollateral(weth, 2 ether);
        vm.stopPrank();
        _;
    }

    function testRevertsIfUserHealthFactorFallsBelowOneAfterRedeem() public testUserDepositsEthCollateral {
        // 1. Mint DSC
        vm.startPrank(testUser);
        dscEngine.mintDsc(100);

        // 2. try to redeem all collateral (2 ether)
        vm.expectRevert();
        dscEngine.redeemCollateral(weth, 2 ether);

        vm.stopPrank();
    }

    function testUserCanRedeemCollateralWhenTheyHaveEnoughCollateralStillAfter() public testUserDepositsEthCollateral {
        // 1. Mint DSC
        vm.startPrank(testUser);
        dscEngine.mintDsc(100);

        // starting Collateral is 2 ether
        uint256 startingCollateral = dscEngine.getUserCollateral(testUser, weth);

        // 2. redeem half (1 ether) of testUsertotal collateral (2 ether), should still be above threshold
        dscEngine.redeemCollateral(weth, 1 ether);

        vm.stopPrank();

        // ending collateral should be 1 ether
        uint256 endingCollateral = dscEngine.getUserCollateral(testUser, weth);

        // 3. check testUser collateral amount is udpdated
        assertEq(endingCollateral, (startingCollateral - 1 ether));
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////    redeemCollateralForDsc Test's         //////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // deposits 2 ETH as collateral for testUser
    modifier testUserDepositEthCollateral() {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscEngine), 10 ether);
        dscEngine.depositCollateral(weth, 2 ether);
        vm.stopPrank();
        _;
    }

    function testRevertsIfAfterBurningAndRedeemingUserHealthFactorGetsTooLow() public testUserDepositEthCollateral {
        // 1. Mint 1,000 DSC -> max user can have with 2 ether collateral
        vm.startPrank(testUser);

        dscEngine.mintDsc(1000);

        // approves dscEngine to transfer DSC token to be burned from testUser to dscEngine contract
        ERC20Mock(address(dsc)).approve(address(dscEngine), 10000);

        // 2. Calls redeemCollateralForDsc -> burns 1 DSC and redeems 1 ether -> user should have $999 DSC and $1,000 ETH
        // health factor will be too low, user would need $2,000 ETH collateral for $1,000 DSC
        vm.expectRevert();
        dscEngine.redeemCollateralForDsc(weth, 1 ether, 1);

        vm.stopPrank();
    }

    function testUserCanRedeemCollateralAndBurnDsc() public testUserDepositEthCollateral {
        // 1. Mint 1,000 DSC -> max user can have with 2 ether collateral
        vm.startPrank(testUser);

        dscEngine.mintDsc(1000);

        (uint256 startingDsc,) = dscEngine.getAccountInformation(address(testUser));
        uint256 startingCollateral = dscEngine.getUserCollateral(address(testUser), weth);

        // approves dscEngine to transfer DSC token to be burned from testUser to dscEngine contract
        ERC20Mock(address(dsc)).approve(address(dscEngine), 10000);

        // 2. calls redeemCollateralForDsc -> burns $550 DSC,leaving $450 DSC -> redeems 1 ether, leaving 1 ether collateral
        // 1 ether = $1,000 USD   -> max amount of DSC user can have is $500
        dscEngine.redeemCollateralForDsc(weth, 1 ether, 550);

        vm.stopPrank();

        (uint256 endingDsc,) = dscEngine.getAccountInformation(address(testUser));
        uint256 endingCollateral = dscEngine.getUserCollateral(address(testUser), weth);

        assertEq(endingCollateral, (startingCollateral - 1 ether));
        assertEq(endingDsc, (startingDsc - 550));
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////    liquidation Test's         //////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // deposits 2 ETH as collateral for testUser
    modifier testUserDepositEth() {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscEngine), 10 ether);
        dscEngine.depositCollateral(weth, 2 ether);
        vm.stopPrank();
        _;
    }

    // function test
} // END OF CONTRACT
