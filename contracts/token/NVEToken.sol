// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '../common/AccessController.sol';
import '../common/ERC20BurnPausable.sol';
import '../interfaces/IAntiBot.sol';
import '../interfaces/IVote.sol';

contract NVEToken is ERC20BurnPausable, AccessController, ReentrancyGuard {
  using SafeMath for uint256;

  IAntiBot private _antiBot;
  bool public antiBotEnabled;
  address public voteContract;
  uint256 public amountTokenOfPublicPool = 17000000 * 10**18; //17M token

  constructor() ERC20('Neloverse', 'NVE') {
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
  }

  function setAmountTokenOfPublicPool(uint256 _amountToken) external onlyAdmin {
    require(IVote(voteContract).Vote(), 'NVE: Can not set now');
    amountTokenOfPublicPool = _amountToken;
  }

  function setVoteContract(address _voteContract) external onlyAdmin {
    voteContract = _voteContract;
  }

  function mintFromPublicPool(address receiver, uint256 amount) external onlyAdmin {
    require(amountTokenOfPublicPool >= amount, 'NVE: Not enough token to mint');
    require(amount >= 0, 'NVE: Amount of token mint must more than zero');
    amountTokenOfPublicPool -= amount;
    _mint(receiver, amount);
  }

  function mint(address receiver, uint256 amount) external onlyAdmin {
    require(IVote(voteContract).Vote(), 'NVE: Can not mint now');
    _mint(receiver, amount);
  }

  function sendTokenToPool(
    address[] memory poolList,
    uint256[] memory ratio,
    uint256 decimal
  ) external nonReentrant onlyAdmin {
    require(poolList.length == ratio.length && poolList.length > 0, 'NVE: Invalid pool setting input');
    require(amountTokenOfPublicPool > 0, 'NVE: Out of token');
    for (uint256 i = 0; i < poolList.length; i++) {
      uint256 amountTransfer = amountTokenOfPublicPool.mul(ratio[i]).div(decimal);
      _mint(poolList[i], amountTransfer);
      amountTokenOfPublicPool -= amountTransfer;
    }
  }

  //pause when token has problem
  function pause() external onlyAdmin {
    _pause();
  }

  function unPause() external onlyAdmin {
    _unpause();
  }

  //protect token from bot attack
  function setAntiBot(IAntiBot antiBot_) external onlyAdmin {
    _antiBot = antiBot_;
  }

  function enabledAntiBot(bool _enabled) external onlyAdmin {
    antiBotEnabled = _enabled;
  }

  function decimals() public view virtual override returns (uint8) {
    return 9;
  }

  function _beforeTokenTransfer(
    address sender,
    address receiver,
    uint256 amount
  ) internal override(ERC20BurnPausable) {
    if (antiBotEnabled) {
      _antiBot.protect(sender, receiver, amount);
    }
    super._beforeTokenTransfer(sender, receiver, amount);
  }
}
