// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface INVEG {
  function  approveFrom(address owner, address spender, uint256 _amount) external returns(bool);
}
