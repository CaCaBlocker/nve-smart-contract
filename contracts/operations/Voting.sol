// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "../interfaces/IVote.sol";
import "../common/AccessController.sol";

contract Voting is IVote, AccessController {
  bool private _vote;

  constructor() {
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
  }

  function setVote(bool _voting) external onlyAdmin {
    _vote = _voting;
  }

  function Vote() external view override returns (bool) {
    return _vote;
  }
}
