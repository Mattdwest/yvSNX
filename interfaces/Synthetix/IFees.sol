// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IFees {
    //write functions

    function claimFees() external;

    function claimOnBehalf(address) external;

    function closeCurrentFeePeriod() external;


    //read-only functions

    function feesAvailable(address) external returns(uint256, uint256);

    function isFeesClaimable(address) external returns(bool);


}
