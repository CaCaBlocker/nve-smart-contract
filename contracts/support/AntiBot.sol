// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../interfaces/IAntiBot.sol";
import "../common/AccessController.sol";

contract AntiBot is AccessController, IAntiBot {
  using SafeMath for uint256;

  enum TradeType {
    SELL,
    BUY
  }

  mapping(address => bool) public blackList;
  mapping(address => bool) public whiteList;
  uint256 public maxSellAmount;
  uint256 public maxBuyAmount;
  uint256 public sellCoolDown;
  uint256 public buyCoolDown;
  address public lpPairAddress;
  bool public lpPairEnabled;
  uint256 public maxTransferAmount;
  uint256 public transferCoolDown;
  bool public whiteListEnabled;

  mapping(address => mapping(TradeType => uint256)) private lastTradeTimeByAddresses;
  mapping(address => uint256) private lastTransferTimeByAddresses;

  constructor(address _admin) {
    super._setupRole(DEFAULT_ADMIN_ROLE, _admin);
  }

  function enabledWhiteList(bool _enabled) external onlyAdmin {
    whiteListEnabled = _enabled;
  }

  function setTransferCoolDown(uint256 _coolDown) external onlyAdmin {
    transferCoolDown = _coolDown;
  }

  function setMaxTransfer(uint256 _maxTransferAmount) external onlyAdmin {
    maxTransferAmount = _maxTransferAmount;
  }

  function setLpPairAddress(address _lpPairAddress) external onlyAdmin {
    lpPairAddress = _lpPairAddress;
    lpPairEnabled = true;
  }

  function setSellCoolDown(uint256 _sellCoolDown) external onlyAdmin {
    sellCoolDown = _sellCoolDown;
  }

  function setMaxSellAmount(uint256 _maxSellAmount) external onlyAdmin {
    maxSellAmount = _maxSellAmount;
  }

  function setBuyCoolDown(uint256 _buyCoolDown) external onlyAdmin {
    buyCoolDown = _buyCoolDown;
  }

  function setMaxBuyAmount(uint256 _maxBuyAmount) external onlyAdmin {
    maxBuyAmount = _maxBuyAmount;
  }

  function addUsersToBlackList(address[] memory _users) external onlyAdmin {
    require(_users.length > 0, "Forbid adding null to blacklist");
    for (uint256 index; index < _users.length; index++) {
      blackList[_users[index]] = true;
    }
  }

  function removeUsersFromBlackList(address[] memory _users) external onlyAdmin {
    require(_users.length > 0, "Forbid removing null from blacklist");
    for (uint256 index; index < _users.length; index++) {
      if (blackList[_users[index]]) {
        delete blackList[_users[index]];
      }
    }
  }

  function addUsersToWhiteList(address[] memory _users) external onlyAdmin {
    require(_users.length > 0, "Forbid adding null to whitelist");
    for (uint256 index; index < _users.length; index++) {
      if (_users[index] != lpPairAddress) {
        whiteList[_users[index]] = true;
      }
    }
  }

  function removeUsersFromWhiteList(address[] memory _users) external onlyAdmin {
    require(_users.length > 0, "Forbid removing null from whitelist");
    for (uint256 index; index < _users.length; index++) {
      if (whiteList[_users[index]]) {
        delete whiteList[_users[index]];
      }
    }
  }

  function protect(
    address _seller,
    address _buyer,
    uint256 _amount
  ) external override onlyOperator {
    require(_seller != address(0), "seller must be non zero");
    require(_buyer != address(0), "buyer must be non zero");
    require(!blackList[_buyer], "Buyer is in blacklist");
    require(!blackList[_seller], "Seller is in blacklist");
    if (whiteListEnabled) {
      if (whiteList[_seller] || whiteList[_buyer]) {
        return;
      }
    }
    if (lpPairEnabled) {
      if (_seller == lpPairAddress) {
        _canBuy(_buyer, _amount);
        lastTradeTimeByAddresses[_buyer][TradeType.BUY] = block.timestamp;
      } else if (_buyer == lpPairAddress) {
        _canSell(_seller, _amount);
        lastTradeTimeByAddresses[_seller][TradeType.SELL] = block.timestamp;
      }
      return;
    }
    _canTransfer(_seller, _buyer, _amount);
    lastTransferTimeByAddresses[_seller] = block.timestamp;
    lastTransferTimeByAddresses[_buyer] = block.timestamp;
  }

  function _canTransfer(
    address _seller,
    address _buyer,
    uint256 _amount
  ) private view {
    require(_amount <= maxTransferAmount, "Exceed limitation of transfering tokens");
    require(
      block.timestamp >= transferCoolDown.add(lastTransferTimeByAddresses[_seller]),
      "Seller is in transfer cooldown time"
    );
    require(
      block.timestamp >= transferCoolDown.add(lastTransferTimeByAddresses[_buyer]),
      "Buyer is in transfer cooldown time"
    );
  }

  function _canBuy(address _buyer, uint256 _amount) private view {
    require(_amount <= maxBuyAmount, "Exceed limitation of buying tokens");
    require(
      block.timestamp >= buyCoolDown.add(lastTradeTimeByAddresses[_buyer][TradeType.BUY]),
      "In buy cooldown time"
    );
  }

  function _canSell(address _seller, uint256 _amount) private view {
    require(_amount <= maxSellAmount, "Exceed limitation of selling tokens");
    require(
      block.timestamp >= sellCoolDown.add(lastTradeTimeByAddresses[_seller][TradeType.SELL]),
      "In sell cooldown time"
    );
  }
}
