// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

interface IMintr {
    //function approve(address, uint256) external;

    //function provide(uint256) external payable returns (uint256);

    //write functions

    function approve(address,uint256) external;

    function issueMaxSynths() external;

    function issueSynths(uint256) external;

    function issueSynthsOnBehalf(address, uint256) external;

    function burnSynths(uint256) external;

    function burnSynthsToTarget() external;

    function burnSynthsOnBehalf(address, uint256) external;

    function burnSynthsToTargetOnBehalf(address) external;

    function mint() external;

    function mintSecondary(address, uint256) external;

    function mintSecondaryRewards(uint256) external;

    //read-only functions

    function balanceOf(address) external view returns(uint256);

    function collateral(address) external view returns(uint256);

    function collateralisationRatio(address) external view returns(uint256);

    function debtBalanceOf(address, bytes32) external view returns(uint256);

    function maxIssuableSynths(address) external view returns(uint256);

    function remainingIssuableSynths(address) external view returns(uint256, uint256, uint256);

    function transferableSynthetix(address) external view returns(uint256);

}
