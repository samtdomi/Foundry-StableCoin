// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

/* Import Statements */
import {ERC20Burnable, ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/* Error Declarations */
error DecentralizedStableCoin__MustBeMoreThanZero();
error DecentralizedStableCoin__BurnAmountExceedsBalance();
error DecentralizedStableCoin__NotZeroAddress();

/* Contracts, Interfaces, Libraries */
/// @title DecntralizedStableCoin
/// @author Samuel Troy Dominguez
/// Collateral: Exogenous (wETH & wBTC)
/// Minting: Algorithmic
/// Relative Stability: Pegged to USD
///
/// this is the contract meant to be governed by DSCEngine. This contract is
/// just the ERC20 implementation of our stablecoin system
///
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    ///////////////////////////////
    ////   Type Declarations  /////
    ///////////////////////////////

    ///////////////////////////////
    ////    State Variables   /////
    ///////////////////////////////

    ///////////////////////////////
    ////        Events        /////
    ///////////////////////////////

    ///////////////////////////////
    ////       Modifiers      /////
    ///////////////////////////////

    //////////////////////////////////////////////////////////////////////////////////////
    ////       Functions      ////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////////
    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }

        if (_amount > balance) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }

        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }

        _mint(_to, _amount);

        return true;
    }
}
