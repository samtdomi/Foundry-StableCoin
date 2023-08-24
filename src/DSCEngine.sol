// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

/* Import Statements */
import {ERC20Burnable, ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/* Error Declarations */
error DSCEngine__NeedsMoreThanZero();
error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
error DSCEngine__NotAllowedToken();
error DSCEngine__TransferFailed();
error DSCEngine__BreaksHealthFactor(uint256 userHealthFactor);
error DSCEngine__MintFailed();
error DSCEngine__HealthFactorOk();
error DSCEngine__HealthFactorNotImproved();

/* Contracts, Interfaces, Libraries */
/**
 * @title DSCEngine
 * @author Samuel Troy Dominguez
 *
 * The system is designed to be s minimal as possible, and have the tokens maintain a
 * 1 token == $1 peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral (wETH , wBTC)
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI, if DAI had no governance, no fees, and was only backed by
 * wETH and wBTC.
 *
 * our DSC system should always be "OverCollateralized".
 * at no point should the value of all collateral <= value of all the stablecoin
 *
 * @notice this contract is the core of the DSC system. It handles all the logic for minting and reedeming DSC, as well as depositing & withdrawing collateral.
 * @notice this contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 *
 */
contract DSCEngine is ReentrancyGuard {
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////        Type Declarations           /////////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    DecentralizedStableCoin private immutable i_dsc;

    using OracleLib for AggregatorV3Interface;

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////        State Variables         ////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /*  maps erc20 token address to its price feed */
    /* all price feeds are USD - ETH/USD, BTC/USD */
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;
    address[] private s_collateralTokens;

    uint256 private constant PRICE_FEED_TEN = 1e10; // adds 10 decimals to the priceFeed value
    uint256 private constant PRICE_FEED_EIGHTEEN = 1e18; // used to divide by and bring amount to a useable #
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_DIVIDE = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // This means a 10% bonus to be given to the liquidator

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //////////////////          Events            ///////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );
    event CollateralTransferredFromUserToDscEngine(
        address indexed user, address indexed dscEngine, uint256 indexed amountCollateral
    );

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////           Modifiers            ////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _tokenAddress) {
        if (s_priceFeeds[_tokenAddress] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////           Functions             /////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /**
     *
     */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // maps the price feed for each token and adds collateral tokens to array
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /**
     * @param tokenCollateralAddress the address of the token to deposit as colalteral
     * @param amountCollateral the amount of collateral to deposit
     * @param amountDscToMint the amount of DecentralizedStableCoin to mint
     * @notice this function will deposit your collateral token of choice and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * ////// depositCollateral ///////
     * @param tokenCollateralAddress The address fo the token ERC20 contract to deposit as collateral (wETH)
     * @param amountCollateral The amount of collateral to deposit
     * @notice follows CEI - Checks (modifiers), Effects, Interactions
     * @notice allows user to deposit ERC20 token as collateral and saves the amount and token deposited for the user so they can mint an amount of the stablecoin based on the amount of collateral they deposited
     * @dev collateral is transferred from the user depositing funds, to this contract address
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        emit CollateralTransferredFromUserToDscEngine(msg.sender, address(this), amountCollateral);
    }

    /**
     * 1. burn DSC
     * 2. redeem collateral
     * @param tokenCollateralAddress the address of the erc20 token used as collateral being redeemed
     * @param amountCollateral the amount of collateral of the specific token to be redeemed
     * @param amountDscToBurn the amount of DSC the user will burn
     * This function burns DSC and then allows the user to redeem their specific erc20 collateral
     * all in one transaction
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        public
    {
        burnDsc(amountDscToBurn);
        // redeemCollateral checks the healthFactor after redeeming the collateral
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /**
     * // in order to redeem collateral the user must have :
     * 1. health factor must be over 1 AFTER collateral pulled
     * @dev so the healthFactor doesnt incorrectly drop below 1 after redeeming the collateral
     * you have to burn DSC before redeeming the collateral
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        // checks if the user healthFactor is above 1 AFTER redeeming the collateral
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * Check if the collateral value > DSC amount : price feeds, values
     * @param amountDscToMint The amount of Decentralized StableCoin to mint
     * @notice They must have more collateral value than the minimum threshold
     * @dev calls the mint function on the DecentralizedStableCoin simple contract to officially mint DSC
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);

        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * 1. transfer the amount of DSC to be burned from the user to this contract address
     * 2. from this contract, burn the DSC
     */
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
    }

    /**
     * if user starts to get under-collateralized, allow anyone to liquidate their positions
     * we will pay anyone to liquidate uers under-collateralized positions
     * @notice the liquidator will receive the total collateral of the user being liquidated
     * and pay off / burn the DSC amount owned by the user being liquidated - and receive the
     * difference as profit
     * @param tokenCollateralAddress the address of the erc20 token used as collateral
     * @param user the user to be liquidated
     * @param debtToCover the amount of DSC you want to burn to improve the users healthFactor
     * @notice you CAN partially liquidate a user and improve their healthFactor
     * @notice you will get a liquidation bonus for taking a users funds (collateral - DSC)
     * @notice this function working assumes the protocol will be roughly 200%
     * over-collateralized in order for this to work.
     * @notice a known bug would be if the protocol were only 100% collateralized or less, then we
     * wouldnt be able to incentivize the liquidators
     * For example, if the price of the collateral plummeted before anyone could be liquidated
     */
    function liquidate(address tokenCollateralAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // need to check the healthFactor of the user, if health factor is OK , dont liquidate
        uint256 startingUserHealthFactor = _healthFactor(user);

        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        // we want to burn their DSC ("debt") and take their Collateral
        // Bad User: $140 ETH , $100 DSC
        // debtToCover = $100
        // $100 of DSC == ?? ETH ? how many ETH tokens is $100 usd??
        // if ETH/USD price is $2,000/USD then the user's $100 DSC is worth .05 ETH
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(tokenCollateralAddress, debtToCover);
        // and give the liquidator a 10% bonus
        // So we are giving the liquidator $110 wETH for $100 DSC
        // We should implement a feature to liquidate in the event the protocol goes insolvent
        // and sweep extra amounts into a treasury
        // Bonus = 0.05 ETH * 10% = 0.005
        // Total to pay lqiuidator = 0.055 ETH   -----> 0.05 ETH  +  .005 ETH Bonus
        uint256 bonusCollateral = tokenAmountFromDebtCovered * (LIQUIDATION_BONUS / 100); // 10/100 == 10%
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral; // ex: .05 ETH + .005 ETH Bonus == .055

        // redeems collateral of the user being liquidated and sending to the LIQUIDATOR
        _redeemCollateral(tokenCollateralAddress, totalCollateralToRedeem, user, msg.sender);

        // burn the amount of DSC that the user had before being liquidated
        // msg.sender (the liquidator) will pay the debtToCover amount onBehalfOf the USER being liquidated ,
        // after being transferred the user's collateral and bonus to liquidate.
        // liquidator gets paid the total collateral of the user being liquidated + bonus, then pays back the Users debt
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);

        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        // if this liquidate process ruined the liquidators health factor - revert and dont allow it to happen
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param tokenCollateralAddress the address of the erc20 token used as collateral
     * @param usdAmountInWei the amount of DSC the user has (which is pegged to $USD) ->  $1 DSC = $1 USD
     * @return ETH token amount of the $DSC amount.
     */
    function getTokenAmountFromUsd(address tokenCollateralAddress, uint256 usdAmountInWei)
        public
        view
        returns (uint256)
    {
        // price of ETH (token)
        // calculate the amount of ETH Tokens the user has based on the $USD amount of their DSC
        // ex: eth price (ETH/USD) = $2,000/USD
        // user total ETH amount in $USD is $1,000
        // ETH = user total ETH value in $USD / (ETH/USD) price  --> $1,000 / $2,000
        // ETH user has = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenCollateralAddress]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData(priceFeed);
        // priceFeed returns int with only 8 decimal places - have to mulitply it by 1e10
        uint256 tokenAmount = (usdAmountInWei * PRICE_FEED_EIGHTEEN) / (uint256(price) * PRICE_FEED_TEN);
        return tokenAmount;
    }

    // function getHealthFactor() external view {}

    /**
     * @notice gets the USD $ value of the amount of collateral that a user has deposited
     * 1. get the specific token that the user has as collateral
     * 2. get the amount of that specific token the user has as collateral
     * 3. get the USD value of that token's collateral amount
     */
    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each possible collateral token, get the amount the user has deposited of each
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        address tokenPriceFeed = s_priceFeeds[token]; // the address of the price feed for that token
        AggregatorV3Interface priceFeed = AggregatorV3Interface(tokenPriceFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData(priceFeed); // gets the price of the specific token /USD
        // has to multiply price feed value by 1e10 to make it 18 decimals , thendivide by 18 tobri
        uint256 priceInUsd = ((uint256(price) * PRICE_FEED_TEN) * amount) / PRICE_FEED_EIGHTEEN;
        return priceInUsd;
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //// Internal & Private Functions /////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice this function gets and returns the amount of DSC minted by the user
     *  and the user's total collateral value in USD
     * @param user the specific user that is getting their account info checked
     * @return totalDscMinted - total amount of DSC minted by the user
     * @return collateralValueInUsd - amount of collateral the user has
     */
    function _getAccountInformation(address user)
        public
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DscMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);

        return (totalDscMinted, collateralValueInUsd);
    }

    ////////
    /**
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     * 1. gets the total collateral user has in USD
     * 2. adjusts the collateral in USD value to the threshold amount
     * 3. checks the user health factor by dividing adjusted collateral / totalDsc user has
     * @return healthFactor of the user
     */
    function _healthFactor(address user) private view returns (uint256) {
        // Total DSC Minted
        // Total Collateral VALUE
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        // Requires you to have double the amount of collateral than you do in DSC
        // Liquidation_Threshold = 50
        // Liquidation_Divide = 100
        // ex:
        // collateral = $150 in ETH
        // $150 ETH * 50 = $7500   ->  $7500 / 100 =   $75
        // collateralAdjustedValue = $75
        // $75 is the max value of DSC you can have
        // if you have $75 DSC , always need to have more than $150 collateral or youll be liquidated
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_DIVIDE;

        // if this number is less than 1 -> you can be liquidated
        // $150 in ETH collateral is $75 in adjustedCollateral
        // lets assume total DSC you have is $50
        // $75 / $50 = 1.5 health factor
        // 1.5 > 1     ---> wont be liquidated
        uint256 healthFactor = (collateralAdjustedForThreshold * 1e18) / totalDscMinted;
        return healthFactor;
    }

    /**
     * 1. Check health factor (do they have enough collateral?)
     * 2. Revert if they dont
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        // if user has collateral and no DSC minted yet (debt) then their health factor is the max it could be
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / 100;
        uint256 healthFactor = (collateralAdjustedForThreshold * 1e18) / totalDscMinted;
        return healthFactor;
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        internal
    {
        // relying on solidity compiler to throw an error if after subtracting the requested
        // amount of collateral to redeem, the users total collateral amount goes below 0.
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;

        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        // transfers the reedeemed collateral token amount from this dscEngine comtract to the user
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @dev low-level internal function - do not call this unless the function calling it,
     *  // is checking for health factors being broken
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) internal {
        s_DscMinted[onBehalfOf] -= amountDscToBurn;
        // transfer DSC from user to this contract address to be burned from this contract address
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        // burn the DSC from this contract
        i_dsc.burn(amountDscToBurn);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////       Getter Functions         ////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function getUserCollateral(address user, address tokenCollateralAddress) public view returns (uint256) {
        uint256 collateral = s_collateralDeposited[user][tokenCollateralAddress];
        return collateral;
    }

    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
        return (totalDscMinted, collateralValueInUsd);
    }

    // function getDscEngineBalance() public view returns (uint256) {
    //     return address(this).balance;
    // }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralTokenPriceFeed(address token) public view returns (address memory) {
        return s_priceFeeds[token];
    }
}
