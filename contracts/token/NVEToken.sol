// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../common/AccessController.sol";
import "../common/ERC20BurnPausable.sol";
import "../interfaces/INeloverseDAO.sol";
import "../interfaces/ITimelock.sol";

contract NVEToken is ERC20BurnPausable, AccessController, ReentrancyGuard {
  using SafeMath for uint256;

  address public daoContract;
  address public timelockContract;
  uint256 private initializeTokenAmount = 17000000 * 10**9; //17M token, Decimals = 9
  uint256 private _lastUnlockedTime;
  uint32 private constant minimumTimeBetweenUnlocks = 30 days;

  constructor(
    address _daoContract,
    address _timelockContract
  ) ERC20("Neloverse", "NVE") {
    _setupRole(ADMIN, _msgSender());
    daoContract = _daoContract;
    timelockContract = _timelockContract;
    _mint(_timelockContract, initializeTokenAmount);
  }

  function setDaoContract(address _daoContract) external onlyAdmin {
    daoContract = _daoContract;
  }

  modifier onlyNeloverseDAO(uint256 proposalId) {
    require(daoContract != address(0), "NVEG: DAO address can not be 0.");
    require(INeloverseDAO(daoContract).checkProposalId(proposalId), "NVE: Proposal ID is not valid.");
    require(INeloverseDAO(daoContract).getProposalFlags(proposalId)[1] == true && INeloverseDAO(daoContract).getProposalFlags(proposalId)[2] == true, "NVE: You not allow to do this function.");
    require(INeloverseDAO(daoContract).getProposalTargetAddress(proposalId) == address(this), "NVE: The target address is not valid.");
    require(INeloverseDAO(daoContract).getActionProposalStatus(proposalId) == false, "NVE: This governance proposal already did.");
    _;
  }

  function mint(
    address receiver,
    uint256 amount,
    uint256 proposalId,
    uint256 _lockId
  ) external onlyNeloverseDAO(proposalId) {
    require(getBalanceTimelock(_lockId) >= amount && getBalanceTimelock(_lockId) > 0, "NVE: Not enough token to mint");
    require(amount > 0, "NVE: Amount of token mint must more than zero");

    INeloverseDAO(daoContract).actionProposal(proposalId);
    ITimelock(timelockContract).withdraw(_lockId, amount, receiver);
  }

  function mintMoreSuply(
    address _owner,
    uint256 amount,
    uint256 proposalId
  ) external returns(uint256) {
    require(timelockContract != address(0), "NVE: Timelock address can not be 0.");
    INeloverseDAO(daoContract).actionProposal(proposalId);
    _mint(timelockContract, amount);
    return ITimelock(timelockContract).deposit(address(this), _owner, amount, 7);
  }

  function sendTokenToPool(
    address[] memory poolList,
    uint256[] memory ratio,
    uint256 proposalId,
    uint256 _lockId
  ) external nonReentrant onlyNeloverseDAO(proposalId) {
    require(_lastUnlockedTime + minimumTimeBetweenUnlocks < block.timestamp, "NVE: 1 month should pass");
    require(poolList.length == ratio.length && poolList.length > 0, "NVE: Invalid pool setting input");

    for (uint256 i = 0; i < poolList.length; i++) {
      uint256 tokenBalance = getBalanceTimelock(_lockId);
      uint256 amountTransfer = tokenBalance.mul(ratio[i]);
      require(tokenBalance > 0, "NVE: Out of token");

      ITimelock(timelockContract).withdraw(_lockId, amountTransfer, poolList[i]);
    }

    INeloverseDAO(daoContract).actionProposal(proposalId);
    _lastUnlockedTime = block.timestamp;
  }

  //pause when token has problem
  function pause(
    uint256 proposalId
  ) external onlyNeloverseDAO(proposalId) {
    INeloverseDAO(daoContract).actionProposal(proposalId);
    _pause();
  }

  function unPause(
    uint256 proposalId
  ) external onlyNeloverseDAO(proposalId) {
    INeloverseDAO(daoContract).actionProposal(proposalId);
    _unpause();
  }

  /**
  * @dev Returns the last unlock time
  */
  function lastUnlockedTime() public view returns (uint256) {
    return _lastUnlockedTime;
  }

  function decimals() public view virtual override returns (uint8) {
    return 9;
  }

  function getBalanceTimelock(uint256 _lockId) public view returns(uint256) {
    return ITimelock(timelockContract).getTokenBalanceByAddress(address(this), _lockId);
  }

  // The following functions are overrides required by Solidity.
  function _beforeTokenTransfer(
    address sender,
    address receiver,
    uint256 amount
  ) internal override(ERC20BurnPausable) {
    super._beforeTokenTransfer(sender, receiver, amount);
  }
}
