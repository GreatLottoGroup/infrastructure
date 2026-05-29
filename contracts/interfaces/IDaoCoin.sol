// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "./IBeneficiaryBase.sol";

interface IDaoCoin is IBeneficiaryBase {

    event PriceChanged(uint256 price);

    // only owner
    function mint(address account, uint256 amount) external returns (bool);
    function changePrice(uint256 price) external returns (bool);

    // only caller
    function mintToUser(address account, uint256 assets) external;


}
