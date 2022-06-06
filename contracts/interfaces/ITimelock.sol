// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ITimelock {
  function deposit(address _tokenAddress, uint256 _amount, uint256 _unlockTime) external view returns (uint256);
  function withdraw(uint256 _id, uint256 _amount, address _withdrawalAddress) external;
  function getTokenBalanceByAddress(address _tokenAddress, uint256 _id) external view returns (uint256);
}
