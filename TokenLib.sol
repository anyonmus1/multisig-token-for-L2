/*////////////////////////////////////////////////////////////
//                     EXTERNAL LIBRARY
////////////////////////////////////////////////////////////*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Token Library
 * @notice Library containing core functionality for Token to reduce main contract size
 * @dev    This library contains calculations and validations to optimize the main contract
 */
library TokenLib {
    struct VestingParams {
        uint256 startTime;
        uint256 totalAmount;
        uint256 claimedAmount;
        bool initialized;
    }

    /**
     * @notice Calculate vested amount based on time and vesting schedule
     * @param startTime Initial timestamp of vesting
     * @param totalAmount Total tokens to be vested
     * @param claimedAmount Amount already claimed
     * @param cliffPeriod Initial lock period
     * @param vestingPeriod Total vesting duration after cliff
     * @param currentTime Current timestamp
     */
    function calculateVestedAmount(
        uint256 startTime,
        uint256 totalAmount,
        uint256 claimedAmount,
        uint256 cliffPeriod,
        uint256 vestingPeriod,
        uint256 currentTime
    ) internal pure returns (uint256) {
        if (currentTime < startTime + cliffPeriod) {
            return 0;
        }

        // Fully vested after entire period
        uint256 totalVestingTime = startTime + cliffPeriod + vestingPeriod;
        if (currentTime >= totalVestingTime) {
            return totalAmount - claimedAmount;
        }

        // Linear vesting
        uint256 timeFromCliff = currentTime - (startTime + cliffPeriod);
        uint256 vestedTotal = (totalAmount * timeFromCliff) / vestingPeriod;
        uint256 claimable = vestedTotal - claimedAmount;
        return claimable;
    }

    /**
     * @notice Calculate fees for a transfer
     * @param amount Transfer amount
     * @param marketingFee Marketing fee in basis points
     * @param liquidityFee Liquidity fee in basis points
     * @return marketingAmount fee for marketing
     * @return liquidityAmount fee for liquidity
     * @return transferAmount net after fees
     */
    function calculateFees(
        uint256 amount,
        uint256 marketingFee,
        uint256 liquidityFee
    )
        internal
        pure
        returns (
            uint256 marketingAmount,
            uint256 liquidityAmount,
            uint256 transferAmount
        )
    {
        marketingAmount = (amount * marketingFee) / 10000;
        liquidityAmount = (amount * liquidityFee) / 10000;
        transferAmount  = amount - (marketingAmount + liquidityAmount);
    }

    /**
     * @notice Validate fee configuration
     * @param marketingFee Marketing fee in basis points
     * @param liquidityFee Liquidity fee in basis points
     * @param maxFee Maximum allowed total fee
     * @return valid Whether fees are valid
     */
    function validateFees(
        uint256 marketingFee,
        uint256 liquidityFee,
        uint256 maxFee
    ) internal pure returns (bool valid) {
        // Combined fee must not exceed maxFee
        return (marketingFee + liquidityFee <= maxFee);
    }

    /**
     * @notice Calculate how long until liquidity is unlocked
     * @param unlockTime Timestamp of liquidity unlock
     * @param currentTime Current block timestamp
     * @return remaining Time until unlock (0 if unlocked)
     */
    function calculateLockTimeRemaining(
        uint256 unlockTime,
        uint256 currentTime
    ) internal pure returns (uint256 remaining) {
        return currentTime >= unlockTime ? 0 : (unlockTime - currentTime);
    }
}