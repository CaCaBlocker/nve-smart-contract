// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/INVEG.sol";

contract NeloverseDAO is ReentrancyGuard {
    /// @notice GLOBAL CONSTANTS
    uint public constant MINIMUM_ACCEPTANCE_THRESHOLD = 1000; /// @notice The minimum acceptance threshold.
    uint public constant MINIMUM_PROPOSAL_DAYS = 3; /// @notice The minimum proposal period.
    address public nvegContract; /// @notice NVEG contract address.

    /// @notice INTERNAL ACCOUNTING
    uint256 private proposalCount = 1; /// @notice total proposals submitted.
    uint256 private memberCount = 1; /// @notice total member.
    uint256[] private proposalQueue;

    mapping (uint256 => Proposal) private proposals;
    mapping(uint256 => mapping(address => Member)) private oldMembers;
    mapping(address => Member) private members;

    /// @notice EVENTS
    event SubmitProposal(address proposer, uint256 acceptanceThreshold, uint256 _days, string details, bool[4] flags, uint256 proposalId, uint256 proposalType);
    event SubmitVote(uint256 indexed proposalIndex, address indexed memberAddress, uint8 uintVote, uint256 votedScore);
    event ProcessedProposal(address proposer, uint256 acceptanceThreshold, uint256 _days, string details, bool[4] flags, uint256 proposalId);
    event AddMember(uint256 shares, uint256 memberId, address memberAddress);
    event Withdraw(address memberAddress, uint256 shares);

    /// @notice Vote types of the proposal.
    enum Vote {
        Null, // default value, counted as abstent.
        Yes,
        No
    }

    /// @notice Possible states that a proposal may be in.
    enum ProposalState {
        Active,
        Finished,
        Passed,
        Rejected,
        Enacted
    }

    /// @notice Possible types of the proposal.
    enum ProposalType {
        Common,
        Governance
    }

    /// @notice Struct of member.
    struct Member {
        uint256 shares; // the # of voting shares assigned to this member.
        uint256[] votedProposal; // the total proposals which you voted.
        mapping(uint256 => uint256) votedScore; // the score which you voted for each proposal.
        bool exists; // the flag to checking you a member or not.
    }

    /// @notice Struct of proposal
    struct Proposal {
        address proposer; /// @notice the account that submitted the proposal (can be non-member).
        uint256 startingTime; /// @notice the time in which voting can start for this proposal.
        uint256 endingTime; /// @notice the time in which voting can end for this proposal.
        uint256 yesVotes; /// @notice the total number of YES votes for this proposal.
        uint256 noVotes; /// @notice the total number of NO votes for this proposal.
        uint256 acceptanceThreshold; /// @notice the total points you need to pass for this proposal.
        uint256 votingYesScore; /// @notice the total yes voting points for this proposal.
        uint256 votingNoScore; /// @notice the total no voting points for this proposal.
        bool[4] flags; /// @notice [sponsored, processed, didPass, cancelled].
        string details; /// @notice proposal details - could be IPFS hash, plaintext, or JSON.
        mapping(address => Vote) votesByMember; /// @notice the votes on this proposal by each member.
        bool exists; /// @notice always true once a proposal has been created.
        bool enacted; /// @notice always false once a proposal has been created.
        uint256 proposalType; /// @notice type of proposal.
        address targetAddress; /// @notice address of target smart contract just need for Governance.
    }

    // CONSTRUCTOR
    constructor(address _nvegContract) {
        nvegContract = _nvegContract;
    }

    modifier onlyValid(uint256 proposalId) {
        require(proposalCount >= proposalId && proposalId > 0, "NeloverseDAO: Invalid proposal id.");
        require(proposals[proposalId].exists, "NeloverseDAO: This proposal does not exist.");
        _;
    }

    modifier onlyMember() {
        require(members[msg.sender].exists, "NeloverseDAO: You are not a member.");
        require(members[msg.sender].shares > 0, "NeloverseDAO: You are not a member.");
        _;
    }

    modifier isHaveEnoughNVEG(uint256 _amount) {
        require(IERC20(nvegContract).balanceOf(msg.sender) > 0 && _amount <= IERC20(nvegContract).balanceOf(msg.sender), "NeloverseDAO: You don't have NVEG.");
        require(INVEG(nvegContract).approveFrom(msg.sender, address(this), _amount), "NeloverseDAO: Falied to approve.");
        require(IERC20(nvegContract).transferFrom(msg.sender, address(this), _amount), "NeloverseDAO: Falied to transfer token.");
        _;
    }

    modifier isValidThresholdAndDays(uint256 acceptanceThreshold, uint256 _days) {
        require(acceptanceThreshold >= MINIMUM_ACCEPTANCE_THRESHOLD, "NeloverseDAO: Acceptance Threshold must be at greater than 1000");
        require(_days >= MINIMUM_PROPOSAL_DAYS, "NeloverseDAO: Proposal days must be at least 3 days.");
        _;
    }

    /// @notice PUBLIC FUNCTIONS
    /// @notice SUBMIT PROPOSAL
    /// @notice Set applicant, timelimit, details, proposal types.
    function submitProposal(uint256 acceptanceThreshold, uint256 _days, string memory details, uint8 _proposalType, address _targetAddress) external isValidThresholdAndDays(acceptanceThreshold, _days) returns (uint256 proposalId) {
        require(msg.sender != address(0), "NeloverseDAO: Applicant cannot be 0.");
        require(_proposalType < 2, "NeloverseDAO: Proposal Type must be less than 2.");
        bool[4] memory flags; /// @notice [sponsored, processed, didPass, cancelled]
        if (_proposalType == 1) {
            require(_targetAddress != address(0), "NeloverseDAO: Target Address cannot be 0.");
            require(IERC20(nvegContract).balanceOf(msg.sender) >= 100*10**9, "NeloverseDAO: You need at least 100 NVEG to submit Governance proposal.");
        }

        _submitProposal(acceptanceThreshold, _days, details, flags, _proposalType, _targetAddress);
        return proposalCount; /// @notice return proposalId - contracts calling submit might want it
    }

    /// @notice Function which can be called when the proposal voting time has expired. To either act on the proposal or cancel if not a majority yes vote.
    function processProposal(uint256 proposalId) external onlyValid(proposalId) returns (bool) {
        require(proposals[proposalId].flags[1] == false, "NeloverseDAO: This proposal has already been processed.");
        require(getCurrentTime() >= proposals[proposalId].startingTime, "NeloverseDAO: Voting period has not started.");
        require(hasVotingPeriodExpired(proposals[proposalId].endingTime), "NeloverseDAO: Proposal voting period has not expired yet.");
        for (uint256 i = 0; i < proposalQueue.length; i++) {
            if (proposalQueue[i] == proposalId) {
                delete proposalQueue[i];
            }
        }
        Proposal storage prop = proposals[proposalId];
        if (prop.flags[3] == false) {
            if (prop.yesVotes > prop.noVotes && prop.votingYesScore >= prop.acceptanceThreshold) {
                prop.flags[1] = true;
                prop.flags[2] = true;
            } else {
                prop.flags[1] = true;
                prop.flags[2] = false;
            }
        }
        emit ProcessedProposal(prop.proposer, prop.acceptanceThreshold, prop.endingTime, prop.details, prop.flags, proposalId);
        return true; 
    }

    /// @notice Function to submit a vote to a proposal.
    /// @notice Voting period must be in session
    function submitVote(uint256 proposalId, uint8 uintVote) external onlyMember onlyValid(proposalId) {
        require(uintVote < 3, "NeloverseDAO: Vote must be less than 3.");

        _submitVote(proposalId, uintVote);
    }

    /// @notice Function to update the action status of proposal, it have been done or not.
    function actionProposal(uint256 proposalId) external onlyValid(proposalId) {
        require(proposals[proposalId].flags[1] == true && proposals[proposalId].flags[2] == true, "NeloverseDAO: This proposal not approve.");
        require(proposals[proposalId].enacted == false, "NeloverseDAO: This proposal already did.");
        proposals[proposalId].enacted = true;
    }

    /// @notice Register a member.
    function addMember(uint256 _amount) external isHaveEnoughNVEG(_amount) returns(uint256 _memberId) {
        require(!members[msg.sender].exists, "NeloverseDAO: You already a member.");
        members[msg.sender].shares = weiToEther(_amount);
        members[msg.sender].exists = true;
        _memberId = memberCount;
        emit AddMember(members[msg.sender].shares, _memberId, msg.sender);
        memberCount += 1;
        return _memberId;
    }

    /// @notice Getting more VP when you have more NVEG.
    function getMoreVP(uint256 _amount) external nonReentrant onlyMember isHaveEnoughNVEG(_amount) {
        members[msg.sender].shares += weiToEther(_amount);
    }

    /// @notice Withdraw NVEG.
    function withdraw(uint256 _amount) external nonReentrant onlyMember {
        Member storage member = members[msg.sender];
        if (member.votedProposal.length > 0) {
            for (uint256 i = 0; i < member.votedProposal.length; i++) {
                Proposal storage proposal = proposals[member.votedProposal[i]];
                if (proposal.flags[3] == false) {
                    require(hasVotingPeriodExpired(proposal.endingTime), "NeloverseDAO: Proposal you voted not expired.");
                }
            }
        }
        require(_amount <= member.shares * 10**9, "NeloverseDAO: Your amount is over your balance.");
        require(IERC20(nvegContract).balanceOf(address(this)) >= _amount, "NeloverseDAO: Don't have enough NVEG to withdraw.");
        require(IERC20(nvegContract).transfer(msg.sender, _amount), "NeloverseDAO: Falied to transfer token.");
        member.shares -= weiToEther(_amount);
        if (member.shares <= 0) {
            member.exists = false;
        }
        emit Withdraw(msg.sender, _amount);
    }

    /// @notice INTERNAL FUNCTION
    /// @notice SUBMIT PROPOSAL
    function _submitProposal(uint256 acceptanceThreshold, uint256 _days, string memory details, bool[4] memory flags, uint8 _proposalType, address _targetAddress) internal {
        proposalQueue.push(proposalCount);
        Proposal storage prop = proposals[proposalCount];
        prop.proposer = msg.sender;
        prop.startingTime = block.timestamp;
        prop.endingTime = endDate(_days);
        prop.flags = flags;
        prop.details = details;
        prop.acceptanceThreshold = acceptanceThreshold;
        prop.exists = true;
        prop.enacted = false;
        prop.proposalType = _proposalType;
        prop.targetAddress = _targetAddress;
        emit SubmitProposal(msg.sender, acceptanceThreshold, _days, details, flags, proposalCount, _proposalType);
        proposalCount += 1;
    }

    /// @notice submit vote for proposal.
    function _submitVote(uint256 proposalId, uint8 uintVote) internal {
        Vote vote = Vote(uintVote);
        Proposal storage prop = proposals[proposalId];
        Member storage member = members[msg.sender];
        require(proposals[proposalId].exists, "NeloverseDAO: This proposal does not exist.");

        if (!contains(member.votedProposal, proposalId)) {
            member.votedProposal.push(proposalId);
            member.votedScore[proposalId] = member.shares;
        }

        require(_state(proposalId) == ProposalState.Active, "NeloverseDAO: Proposal voting period has not started.");
        require(!hasVotingPeriodExpired(prop.endingTime), "NeloverseDAO: Proposal voting period has expired.");
        require(vote == Vote.Yes || vote == Vote.No, "NeloverseDAO: Vote must be either Yes or No.");

        if (vote == Vote.Yes) {
            require(prop.votesByMember[msg.sender] != Vote.Yes, "NeloverseDAO: You already voted Yes.");
            if (prop.votesByMember[msg.sender] == Vote.No) {
                prop.noVotes -= 1;
                prop.votingNoScore = prop.votingNoScore - member.votedScore[proposalId];
            }

            prop.yesVotes += 1;
            prop.votingYesScore = prop.votingYesScore + member.votedScore[proposalId];
        } else if (vote == Vote.No) {
            require(prop.votesByMember[msg.sender] != Vote.No, "NeloverseDAO: You already voted No.");
            if (prop.votesByMember[msg.sender] == Vote.Yes) {
                prop.yesVotes -= 1;
                prop.votingYesScore = prop.votingYesScore - member.votedScore[proposalId];
            }

            prop.noVotes += 1;
            prop.votingNoScore = prop.votingNoScore + member.votedScore[proposalId];
        }

        prop.votesByMember[msg.sender] = vote;
        emit SubmitVote(proposalId, msg.sender, uintVote, member.votedScore[proposalId]);
    }

    function getMemberProposalVote(uint256 proposalId) public view returns (Vote) {
        require(proposalCount >= proposalId && proposalId > 0, "NeloverseDAO: Invalid proposal id.");
        uint256 _proposalIndex = proposalId - 1;
        require(_proposalIndex < proposalQueue.length, "NeloverseDAO: Proposal does not exist in Queue.");
        return Vote(proposals[proposalQueue[_proposalIndex]].votesByMember[msg.sender]);
    }

    /// @notice GETTER FUNCTIONS
    function getCurrentTime() public view returns (uint256) {
        return block.timestamp;
    }

    function getProposalQueueLength() public view returns (uint256) {
        return proposalQueue.length;
    }

    function getMember(address _owner) public view returns (uint256, uint256[] memory, bool) {
        return (members[_owner].shares, members[_owner].votedProposal, members[_owner].exists);
    }

    function getProposalFlags(uint256 proposalId) public onlyValid(proposalId) view returns (bool[4] memory _flags) {
        _flags = proposals[proposalId].flags;

        return _flags;
    }

    function getProposalState(uint256 proposalId) public onlyValid(proposalId) view returns (ProposalState) {
        return _state(proposalId);
    }

    function checkProposalId(uint256 proposalId) public view returns (bool) {
        return proposalCount >= proposalId && proposalId > 0 && proposals[proposalId].exists;
    }

    function getProposalTargetAddress(uint256 proposalId) public view returns (address) {
        require(proposals[proposalId].exists, "NeloverseDAO: This proposal does not exist.");
        require(ProposalType(proposals[proposalId].proposalType) == ProposalType.Governance, "NeloverseDAO: This proposal not a Governance Proposal.");

        return proposals[proposalId].targetAddress;
    }

    function getActionProposalStatus(uint256 proposalId) public onlyValid(proposalId) view returns (bool) {
        bool enacted = proposals[proposalId].enacted;

        return enacted;
    }

    function getProposalDetail(uint256 proposalId) public onlyValid(proposalId) view returns(uint256, uint256, uint256, uint256, uint256, uint256, uint256, string memory, bool, uint256) {
        Proposal storage prop = proposals[proposalId];
        return (prop.startingTime, prop.endingTime, prop.yesVotes, prop.noVotes, prop.acceptanceThreshold, prop.votingYesScore, prop.votingNoScore, prop.details, prop.enacted, prop.proposalType);
    }

    /// @notice INTERNAL HELPER FUNCTIONS
    function endDate(uint256 _days) internal view returns (uint256) {
        return block.timestamp + _days * 1 days;
    }

    function weiToEther(uint256 valueWei) internal pure returns (uint256) {
       return valueWei/(10**9);
    }

    function hasVotingPeriodExpired(uint256 endingTime) public view returns (bool) {
        return (getCurrentTime() >= endingTime);
    }

    function _state(uint256 proposalId) internal view returns (ProposalState _stateStatus) {
        require(proposals[proposalId].exists, "NeloverseDAO: This proposal does not exist.");
        Proposal storage proposal = proposals[proposalId];

        if (!hasVotingPeriodExpired(proposal.endingTime) && getCurrentTime() >= proposal.startingTime) {
            _stateStatus = ProposalState.Active;
        } else if (hasVotingPeriodExpired(proposal.endingTime) && proposal.flags[2] == true) {
            _stateStatus = ProposalState.Passed;
        } else if (hasVotingPeriodExpired(proposal.endingTime) && proposal.flags[2] == false) {
            _stateStatus = ProposalState.Rejected;
        } else if (hasVotingPeriodExpired(proposal.endingTime) && proposal.enacted == true) {
            _stateStatus = ProposalState.Enacted;
        } else if (hasVotingPeriodExpired(proposal.endingTime)) {
            _stateStatus = ProposalState.Finished;
        }
    }

    function contains(uint256[] memory _votedProposal, uint256 proposalId) internal pure returns (bool) {
        bool isHave = false;
        for (uint256 i = 0; i < _votedProposal.length; i++) {
            if (_votedProposal[i] == proposalId) {
                isHave = true;
            }
        }
        return isHave;
    }
}