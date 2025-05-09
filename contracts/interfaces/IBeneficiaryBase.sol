// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

interface IBeneficiaryBase {

    function getBeneficiaryList() external view returns (address[] memory);

    function isBenefitAccount(address account) external view returns (bool);

    function getBenefitAmount(address account, uint256 totalAmount) external view returns (uint);

}
