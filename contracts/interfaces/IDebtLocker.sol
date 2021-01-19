// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface IDebtLocker {
    function owner() external returns (address);
    function loanAsset() external returns (address);
    function claim() external returns(uint[5] memory);
}
