// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IAntiBot {
  function protect(
    address _sender,
    address _receiver,
    uint256 _amount
  ) external;
}
