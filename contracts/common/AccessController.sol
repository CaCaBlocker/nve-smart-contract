// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract AccessController is AccessControl {
  bytes32 public constant ADMIN = keccak256("ADMIN");
  bytes32 public constant OPERATOR = keccak256("OPERATOR");

  modifier onlyAdmin() {
    require(hasRole(ADMIN, _msgSender()), "Caller is not the admin");
    _;
  }
}
