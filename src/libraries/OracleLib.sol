// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracelLib
 * @author Samuel Dominguez
 * @notice This library is used to check the Chainlink Oracle for stale data.
 * If a price is stale, the function will revert, and render the DSCEngine unusable - this is by design
 * we want the DSCEngine to freeze if teh chainlink pricefeeds become stale
 *
 * If the Chainlink network explodes and you have alot of money locked in the protocol - youre screwed
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours;

    /**
     * @dev this function is used in place of just calling directly from the AggregatorV3Interface for latestRoundData() -
     * this function will call the latestRoundData(); from the AggregatorV3Interface the same, but with the added
     * ability to check to ensure that the priceFeed has updated its information
     * @return Returns the latest round data for the specific priceFeed token using the AggregatorV3Interface
     */
    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;

        if (secondsSince > TIMEOUT) {
            revert OracleLib__StalePrice();
        }

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
