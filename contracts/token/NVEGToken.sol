// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../common/AccessController.sol";
import "../common/ERC20BurnPausable.sol";
import "../interfaces/INeloverseDAO.sol";
import "../interfaces/ITimelock.sol";

contract NVEGToken is ERC20BurnPausable, AccessController, ReentrancyGuard {
    using SafeMath for uint256;

    address public daoContract;
    address public timelockContract;
    uint256 private initializeSupply = 989000 * 10**9; //989k token, Decimals = 9
    uint256 private initializeTokenAmount = 11000 * 10**9; //11k token, Decimals = 9
    uint256 private _lastUnlockedTime;
    uint32 private constant minimumTimeBetweenUnlocks = 30 days;

    constructor(
        address _neloverseGovernorAddress,
        address _timelockContract
    ) ERC20("Neloverse Governance", "NVEG") {
        _setupRole(ADMIN, _msgSender());
        _lastUnlockedTime = block.timestamp;
        timelockContract = _timelockContract;
        _mint(_timelockContract, initializeSupply);
        _mint(_neloverseGovernorAddress, initializeTokenAmount);
    }

    modifier onlyNeloverseDAO(uint256 proposalId, uint256 _proposalType) {
        require(daoContract != address(0), "NVEG: DAO address can not be 0.");
        require(INeloverseDAO(daoContract).checkProposalId(proposalId), "NVEG: Proposal ID is not valid.");
        require(INeloverseDAO(daoContract).getProposalFlags(proposalId, _proposalType)[1] == true && INeloverseDAO(daoContract).getProposalFlags(proposalId, _proposalType)[2] == true, "NVEG: You not allow to do this function.");
        require(INeloverseDAO(daoContract).getProposalTargetAddress(proposalId) == address(this), "NVEG: The target address is not valid.");
        require(INeloverseDAO(daoContract).getActionProposalStatus(proposalId, _proposalType) == false, "NVE: This governance proposal already did.");
        _;
    }

    function setDaoContract(address _daoContract) external onlyAdmin {
        daoContract = _daoContract;
    }

    function mint(
        address receiver,
        uint256 amount,
        uint256 proposalId,
        uint256 _lockId,
        uint256 _proposalType
    ) public onlyNeloverseDAO(proposalId, _proposalType) {
        require(getBalanceTimelock(_lockId) >= amount && getBalanceTimelock(_lockId) > 0, "NVEG: Not enough token to mint");
        require(amount > 0, "NVEG: Amount of token mint must more than zero");

        INeloverseDAO(daoContract).actionProposal(proposalId, _proposalType);
        ITimelock(timelockContract).withdraw(_lockId, amount, receiver);
    }

    function sendTokenToPool(
        address[] memory poolList,
        uint256[] memory ratio,
        uint256 proposalId,
        uint256 _proposalType,
        uint256 _lockId
    ) external nonReentrant onlyNeloverseDAO(proposalId, _proposalType) {
        require(_lastUnlockedTime + minimumTimeBetweenUnlocks < block.timestamp, "NVEG: 1 month should pass");
        require(poolList.length == ratio.length && poolList.length > 0, "NVEG: Invalid pool setting input");

        for (uint256 i = 0; i < poolList.length; i++) {
            uint256 tokenBalance = getBalanceTimelock(_lockId);
            uint256 amountTransfer = tokenBalance.mul(ratio[i]);
            require(tokenBalance > 0, "NVEG: Out of token");

            ITimelock(timelockContract).withdraw(_lockId, amountTransfer, poolList[i]);
        }

        INeloverseDAO(daoContract).actionProposal(proposalId, _proposalType);
        _lastUnlockedTime = block.timestamp;
    }

  //pause when token has problem
    function pause(uint256 proposalId, uint256 _proposalType) external onlyNeloverseDAO(proposalId, _proposalType) {
        INeloverseDAO(daoContract).actionProposal(proposalId, _proposalType);
        _pause();
    }

    function unPause(uint256 proposalId, uint256 _proposalType) external onlyNeloverseDAO(proposalId, _proposalType) {
        INeloverseDAO(daoContract).actionProposal(proposalId, _proposalType);
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
