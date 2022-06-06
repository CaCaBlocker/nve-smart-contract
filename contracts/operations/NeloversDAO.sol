// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NeloverseDAO {
    /// @notice GLOBAL CONSTANTS
    uint256 public summoningTime; /// @notice time DAO contract deployed.
    address public nvegContract; /// @notice NVEG contract address.

    /// @notice INTERNAL ACCOUNTING
    uint256 private proposalCount = 1; /// @notice total proposals submitted.
    uint256[] private proposalQueue;
    uint256[] private governanceProposalQueue;

    mapping (uint256 => Proposal) private proposals;
    mapping (uint256 => GovernanceProposal) private governanceProposals;
    mapping (address => Member) private members;

    /// @notice EVENTS
    event SubmitProposal(address proposer, uint256 acceptanceThreshold, uint256 _days, string details, bool[4] flags, uint256 proposalId);
    event SubmitVote(uint256 indexed proposalIndex, address indexed memberAddress, uint8 uintVote);
    event CancelProposal(uint256 indexed proposalId, address applicantAddress);
    event ProcessedProposal(address proposer, uint256 acceptanceThreshold, uint256 _days, string details, bool[4] flags, uint256 proposalId);

    /// @notice Vote types of the proposal.
    enum Vote {
        Null, // default value, counted as abstent.
        Yes,
        No
    }

    /// @notice Possible states that a proposal may be in.
    enum ProposalState {
        Active,
        Canceled,
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
        bool exists; // always true once a member has been created.
    }

    /// @notice Struct of common proposal
    struct Proposal {
        address proposer; /// @notice the account that submitted the proposal (can be non-member).
        uint256 startingTime; /// @notice the time in which voting can start for this proposal.
        uint256 endingTime; /// @notice the time in which voting can end for this proposal.
        uint256 yesVotes; /// @notice the total number of YES votes for this proposal.
        uint256 noVotes; /// @notice the total number of NO votes for this proposal.
        uint256 acceptanceThreshold; /// @notice the total points you need to pass for this proposal.
        uint256 votingScore; /// @notice the total voting points for this proposal.
        bool[4] flags; /// @notice [sponsored, processed, didPass, cancelled].
        string details; /// @notice proposal details - could be IPFS hash, plaintext, or JSON.
        mapping(address => Vote) votesByMember; /// @notice the votes on this proposal by each member.
        bool exists; /// @notice always true once a proposal has been created.
        bool enacted; /// @notice always false once a proposal has been created.
        uint256 proposalType; /// @notice type of proposal.
    }

    /// @notice Struct of governance proposal
    struct GovernanceProposal {
        address proposer; /// @notice the account that submitted the proposal (can be non-member).
        uint256 startingTime; /// @notice the time in which voting can start for this proposal.
        uint256 endingTime; /// @notice the time in which voting can end for this proposal.
        uint256 yesVotes; /// @notice the total number of YES votes for this proposal.
        uint256 noVotes; /// @notice the total number of NO votes for this proposal.
        uint256 acceptanceThreshold; /// @notice the total points you need to pass for this proposal.
        uint256 votingScore; /// @notice the total voting points for this proposal.
        bool[4] flags; /// @notice [sponsored, processed, didPass, cancelled].
        string details; /// @notice proposal details - could be IPFS hash, plaintext, or JSON.
        mapping(address => Vote) votesByMember; /// @notice the votes on this proposal by each member.
        bool exists; /// @notice always true once a proposal has been created.
        bool enacted; /// @notice always false once a proposal has been created.
        uint256 proposalType; /// @notice type of proposal.
        address targetAddress; /// @notice address of target Governance smart contract.
    }

    // CONSTRUCTOR
    constructor(address _nvegContract) {
        summoningTime = block.timestamp;
        nvegContract = _nvegContract;
    }

    modifier onlyValid(uint256 proposalId, uint256 _proposalType) {
        require(proposalCount >= proposalId && proposalId > 0, "NeloverseDAO: Invalid proposal id.");
        require(_proposalType < 2, "NeloverseDAO: Proposal type must be less than 2.");
        _;
    }

    /// @notice PUBLIC FUNCTIONS
    /// @notice SUBMIT COMMON PROPOSAL
    /// @notice Set applicant, timelimit, details, proposal types.
    function submitProposal(uint256 acceptanceThreshold, uint256 _days, string memory details, uint8 _proposalType) external returns (uint256 proposalId) {
        address applicant = msg.sender;
        require(applicant != address(0), "NeloverseDAO: Applicant cannot be 0");
        require(_proposalType < 2, "NeloverseDAO: Proposal Type must be less than 2.");
        bool[4] memory flags; /// @notice [sponsored, processed, didPass, cancelled]
        _submitProposal(acceptanceThreshold, _days, details, flags, _proposalType);

        return proposalCount; /// @notice return proposalId - contracts calling submit might want it
    }

    /// @notice SUBMIT GOVERNANCE PROPOSAL
    /// @notice Set applicant, timelimit, details, proposal types, target address.
    function submitGovernanceProposal(uint256 acceptanceThreshold, uint256 _days, string memory details, uint8 _proposalType, address _targetAddress) external returns (uint256 proposalId) {
        address applicant = msg.sender;
        require(applicant != address(0), "NeloverseDAO: Applicant cannot be 0");
        require(_proposalType < 2, "NeloverseDAO: Proposal Type must be less than 2.");
        require(IERC20(nvegContract).balanceOf(msg.sender) > 100, "NeloverseDAO: You need to at least 100 VP to submit Governance Proposal.");
        bool[4] memory flags; /// @notice [sponsored, processed, didPass, cancelled]
        _submitGovernanceProposal(acceptanceThreshold, _days, details, flags, _proposalType, _targetAddress);

        return proposalCount; /// @notice return proposalId - contracts calling submit might want it
    }

    /// @notice Function which can be called when the proposal voting time has expired. To either act on the proposal or cancel if not a majority yes vote.
    function processProposal(uint256 proposalId, uint256 _proposalType) external onlyValid(proposalId, _proposalType) returns (bool) {
        bool processing;
        if (_proposalType == 0) {
            require(proposals[proposalId].exists, "NeloverseDAO: This proposal does not exist.");
            require(proposals[proposalId].flags[1] == false, "NeloverseDAO: This proposal has already been processed.");
            require(getCurrentTime() >= proposals[proposalId].startingTime, "NeloverseDAO: Voting period has not started.");
            require(hasVotingPeriodExpired(proposals[proposalId].startingTime, proposals[proposalId].endingTime), "NeloverseDAO: Proposal voting period has not expired yet.");

            for (uint256 i = 0; i < proposalQueue.length; i++) {
                if (proposalQueue[i] == proposalId) {
                    delete proposalQueue[i];
                }
            }

            Proposal storage prop = proposals[proposalId];

            if (prop.flags[3] == false) {
                if (prop.yesVotes > prop.noVotes && prop.votingScore > prop.acceptanceThreshold) {
                    prop.flags[1] = true;
                    prop.flags[2] = true;
                    processing = true;
                } else {
                    prop.flags[1] = true;
                    _cancelProposal(proposalId);
                    processing = false;
                }
            }
            emit ProcessedProposal(prop.proposer, prop.acceptanceThreshold, prop.endingTime, prop.details, prop.flags, proposalId);
        } else {
            require(governanceProposals[proposalId].exists, "NeloverseDAO: This proposal does not exist.");
            require(governanceProposals[proposalId].flags[1] == false, "NeloverseDAO: This proposal has already been processed.");
            require(getCurrentTime() >= governanceProposals[proposalId].startingTime, "NeloverseDAO: Voting period has not started.");
            require(hasVotingPeriodExpired(governanceProposals[proposalId].startingTime, governanceProposals[proposalId].endingTime), "NeloverseDAO: Proposal voting period has not expired yet.");

            for (uint256 i = 0; i < governanceProposalQueue.length; i++) {
                if (governanceProposalQueue[i] == proposalId) {
                    delete governanceProposalQueue[i];
                }
            }

            GovernanceProposal storage prop = governanceProposals[proposalId];

            if (prop.flags[3] == false) {
                if (prop.yesVotes > prop.noVotes && prop.votingScore > prop.acceptanceThreshold) {
                    prop.flags[1] = true;
                    prop.flags[2] = true;
                    processing = true;
                } else {
                    prop.flags[1] = true;
                    _cancelGovernanceProposal(proposalId);
                    processing = false;
                }
            }
            emit ProcessedProposal(prop.proposer, prop.acceptanceThreshold, prop.endingTime, prop.details, prop.flags, proposalId);
        }

        return processing;
    }

    /// @notice Function to submit a vote to a proposal.
    /// @notice Voting period must be in session
    function submitVote(uint256 proposalId, uint8 uintVote, uint256 _proposalType) external onlyValid(proposalId, _proposalType) {
        require(!members[msg.sender].exists, "NeloverseDAO: Member has already voted.");
        require(IERC20(nvegContract).balanceOf(msg.sender) > 0, "NeloverseDAO: You don't have enough NVEG.");
        require(uintVote < 3, "NeloverseDAO: Vote must be less than 3.");

        if (_proposalType == 0) {
            _submitVote(proposalId, uintVote);
        } else {
            _submitGovernanceVote(proposalId, uintVote);
        }
    }

    /// @notice Function to update the action status of proposal, it have been done or not.
    function actionProposal(uint256 proposalId, uint256 _proposalType) external onlyValid(proposalId, _proposalType) {
        if (_proposalType == 0) {
            require(proposals[proposalId].exists, "NeloverseDAO: This proposal does not exist.");
            Proposal storage prop = proposals[proposalId];
            require(prop.flags[1] == true && prop.flags[2] == true, "NeloverseDAO: This proposal not approve.");
            require(prop.enacted == false, "NeloverseDAO: This proposal already did.");
            prop.enacted = true;
        } else {
            require(governanceProposals[proposalId].exists, "NeloverseDAO: This proposal does not exist.");
            GovernanceProposal storage prop = governanceProposals[proposalId];
            require(prop.flags[1] == true && prop.flags[2] == true, "NeloverseDAO: This proposal not approve.");
            require(prop.enacted == false, "NeloverseDAO: This governance proposal already did.");
            prop.enacted = true;
        }
    }

    /// @notice INTERNAL FUNCTION
    /// @notice SUBMIT COMMON PROPOSAL
    function _submitProposal(uint256 acceptanceThreshold, uint256 _days, string memory details, bool[4] memory flags, uint8 _proposalType) internal {
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
        emit SubmitProposal(msg.sender, acceptanceThreshold, _days, details, flags, proposalCount);
        proposalCount += 1;
    }

    /// @notice SUBMIT GOVERNANCE PROPOSAL
    function _submitGovernanceProposal(uint256 acceptanceThreshold, uint256 _days, string memory details, bool[4] memory flags, uint8 _proposalType, address _targetAddress) internal {
        governanceProposalQueue.push(proposalCount);
        GovernanceProposal storage prop = governanceProposals[proposalCount];
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
        emit SubmitProposal(msg.sender, acceptanceThreshold, _days, details, flags, proposalCount);
        proposalCount += 1;
    }

    /// @notice Function cancel a common proposal if it has not been cancelled already.
    function _cancelProposal(uint256 proposalId) internal {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.proposer == msg.sender, "NeloverseDAO: Only proposer can cancelled proposal.");
        require(!proposal.flags[3], "NeloverseDAO: Proposal has already been cancelled");
        proposal.flags[3] = true; // cancelled

        emit CancelProposal(proposalId, msg.sender);
    }

    /// @notice Function cancel a governance proposal if it has not been cancelled already.
    function _cancelGovernanceProposal(uint256 proposalId) internal {
        GovernanceProposal storage proposal = governanceProposals[proposalId];
        require(proposal.proposer == msg.sender, "NeloverseDAO: Only proposer can cancelled proposal.");
        require(!proposal.flags[3], "NeloverseDAO: Proposal has already been cancelled");
        proposal.flags[3] = true; // cancelled

        emit CancelProposal(proposalId, msg.sender);
    }

    /// @notice submit vote for a common proposal.
    function _submitVote(uint256 proposalId, uint8 uintVote) internal {
        require(proposals[proposalId].exists, "NeloverseDAO: This proposal does not exist.");
        Vote vote = Vote(uintVote);
        address memberAddress = msg.sender;
        uint256 accountBalance = IERC20(nvegContract).balanceOf(memberAddress);
        Proposal storage prop = proposals[proposalId];
        Member storage member = members[memberAddress];
        member.shares = weiToEther(accountBalance);
        member.exists = true;

        require(_state(proposalId) == ProposalState.Active, "NeloverseDAO: Proposal voting period has not started.");
        require(!hasVotingPeriodExpired(prop.startingTime, prop.endingTime), "NeloverseDAO: Proposal voting period has expired.");
        require(prop.votesByMember[memberAddress] == Vote.Null, "NeloverseDAO: Member has already voted.");
        require(vote == Vote.Yes || vote == Vote.No, "NeloverseDAO: Vote must be either Yes or No.");

        prop.votesByMember[memberAddress] = vote;

        if (vote == Vote.Yes) {
            prop.yesVotes += 1;
            prop.votingScore = prop.votingScore + weiToEther(accountBalance);
        } else if (vote == Vote.No) {
            prop.noVotes += 1;
            prop.votingScore = (prop.votingScore - weiToEther(accountBalance) < 0) ? 0 : prop.votingScore - weiToEther(accountBalance);
        }

        emit SubmitVote(proposalId, memberAddress, uintVote);
    }

    /// @notice submit vote for a common proposal.
    function _submitGovernanceVote(uint256 proposalId, uint8 uintVote) internal {
        require(governanceProposals[proposalId].exists, "NeloverseDAO: This governance proposal does not exist.");
        Vote vote = Vote(uintVote);
        address memberAddress = msg.sender;
        uint256 accountBalance = IERC20(nvegContract).balanceOf(memberAddress);
        GovernanceProposal storage prop = governanceProposals[proposalId];
        Member storage member = members[memberAddress];
        member.shares = weiToEther(accountBalance);
        member.exists = true;

        require(_governanceState(proposalId) == ProposalState.Active, "NeloverseDAO: Governance Proposal voting period has not started.");
        require(!hasVotingPeriodExpired(prop.startingTime, prop.endingTime), "NeloverseDAO: Governance Proposal voting period has expired.");
        require(prop.votesByMember[memberAddress] == Vote.Null, "NeloverseDAO: Member has already voted.");
        require(vote == Vote.Yes || vote == Vote.No, "NeloverseDAO: Vote must be either Yes or No.");

        prop.votesByMember[memberAddress] = vote;

        if (vote == Vote.Yes) {
            prop.yesVotes += 1;
            prop.votingScore = prop.votingScore + weiToEther(accountBalance);
        } else if (vote == Vote.No) {
            prop.noVotes += 1;
            prop.votingScore = (prop.votingScore - weiToEther(accountBalance) < 0) ? 0 : prop.votingScore - weiToEther(accountBalance);
        }

        emit SubmitVote(proposalId, memberAddress, uintVote);
    }

    /// @notice GETTER FUNCTIONS
    function getCurrentTime() public view returns (uint256) {
        return block.timestamp;
    }

    function getProposalQueueLength(uint256 _proposalType) public view returns (uint256) {
        require(_proposalType < 2, "NeloverseDAO: Proposal type must be less than 2.");

        if (_proposalType == 0) {
            return proposalQueue.length;
        } else {
            return governanceProposalQueue.length;
        }
    }

    function getProposalFlags(uint256 proposalId, uint256 _proposalType) public onlyValid(proposalId, _proposalType) view returns (bool[4] memory) {
        bool[4] memory flags;
        if (_proposalType == 0) {
            require(proposals[proposalId].exists, "NeloverseDAO: This proposal does not exist.");
            flags = proposals[proposalId].flags;
        } else {
            require(governanceProposals[proposalId].exists, "NeloverseDAO: This governance proposal does not exist.");
            flags = governanceProposals[proposalId].flags;
        }

        return flags;
    }

    function getProposalState(uint256 proposalId, uint256 _proposalType) public onlyValid(proposalId, _proposalType) view returns (ProposalState) {
        if (_proposalType == 0) {
            return _state(proposalId);
        } else {
            return _governanceState(proposalId);
        }
    }

    function checkProposalId(uint256 proposalId) public view returns (bool) {
        return proposalCount >= proposalId && proposalId > 0;
    }

    function getProposalTargetAddress(uint256 proposalId) public view returns (address) {
        require(governanceProposals[proposalId].exists, "NeloverseDAO: This governance proposal does not exist.");
        ProposalType proposalType = ProposalType(governanceProposals[proposalId].proposalType);
        require(proposalType == ProposalType.Governance, "NeloverseDAO: This proposal not a Governance Proposal.");
    
        return governanceProposals[proposalId].targetAddress;
    }

    function getMemberProposalVote(address memberAddress, uint256 proposalIndex) public view returns (Vote) {
        require(members[memberAddress].exists, "NeloverseDAO: Member does not exist.");
        require(proposalIndex < proposalQueue.length, "NeloverseDAO: Proposal does not exist.");
        return proposals[proposalQueue[proposalIndex]].votesByMember[memberAddress];
    }

    function getActionProposalStatus(uint256 proposalId, uint256 _proposalType) public onlyValid(proposalId, _proposalType) view returns (bool) {
        bool enacted;
        if (_proposalType == 0) {
            require(proposals[proposalId].exists, "NeloverseDAO: This proposal does not exist.");
            enacted = proposals[proposalId].enacted;
        } else {
            require(governanceProposals[proposalId].exists, "NeloverseDAO: This governance proposal does not exist.");
            enacted = governanceProposals[proposalId].enacted;
        }

        return enacted;
    }

    function getProposalDetail(uint256 proposalId, uint256 _proposalType) public onlyValid(proposalId, _proposalType) view returns(uint256, uint256, uint256, uint256, uint256, uint256, string memory, bool, uint256) {
        if (_proposalType == 0) {
            require(proposals[proposalId].exists, "NeloverseDAO: This proposal does not exist.");
            Proposal storage prop = proposals[proposalId];
            return (prop.startingTime, prop.endingTime, prop.yesVotes, prop.noVotes, prop.acceptanceThreshold, prop.votingScore, prop.details, prop.enacted, prop.proposalType);
        } else {
            require(governanceProposals[proposalId].exists, "NeloverseDAO: This proposal does not exist.");
            GovernanceProposal storage prop = governanceProposals[proposalId];
            return (prop.startingTime, prop.endingTime, prop.yesVotes, prop.noVotes, prop.acceptanceThreshold, prop.votingScore, prop.details, prop.enacted, prop.proposalType);
        }
    }

    /// @notice HELPER FUNCTIONS
    function endDate(uint256 _days) internal view returns (uint256) {
        return block.timestamp + _days * 1 days;
    }

    function weiToEther(uint256 valueWei) internal pure returns (uint256) {
       return valueWei/(10**9);
    }

    function hasVotingPeriodExpired(uint256 startingTime, uint256 endingTime) public view returns (bool) {
        return (getCurrentTime() >= (startingTime + endingTime));
    }

    function _state(uint256 proposalId) internal view returns (ProposalState _stateStatus) {
        require(proposals[proposalId].exists, "NeloverseDAO: This proposal does not exist.");
        Proposal storage proposal = proposals[proposalId];

        if (!hasVotingPeriodExpired(proposal.startingTime, proposal.endingTime) && getCurrentTime() >= proposal.startingTime) {
            _stateStatus = ProposalState.Active;
        } else if (hasVotingPeriodExpired(proposal.startingTime, proposal.endingTime) && proposal.flags[3] == true) {
            _stateStatus = ProposalState.Canceled;
        } else if (hasVotingPeriodExpired(proposal.startingTime, proposal.endingTime) && proposal.flags[2] == true) {
            _stateStatus = ProposalState.Passed;
        } else if (hasVotingPeriodExpired(proposal.startingTime, proposal.endingTime) && proposal.flags[2] == false) {
            _stateStatus = ProposalState.Rejected;
        } else if (hasVotingPeriodExpired(proposal.startingTime, proposal.endingTime)) {
            _stateStatus = ProposalState.Finished;
        }
    }

    function _governanceState(uint256 proposalId) internal view returns (ProposalState _stateStatus) {
        require(governanceProposals[proposalId].exists, "NeloverseDAO: This governance proposal does not exist.");
        GovernanceProposal storage proposal = governanceProposals[proposalId];

        if (!hasVotingPeriodExpired(proposal.startingTime, proposal.endingTime) && getCurrentTime() >= proposal.startingTime) {
            _stateStatus = ProposalState.Active;
        } else if (hasVotingPeriodExpired(proposal.startingTime, proposal.endingTime) && proposal.flags[3] == true) {
            _stateStatus = ProposalState.Canceled;
        } else if (hasVotingPeriodExpired(proposal.startingTime, proposal.endingTime) && proposal.flags[2] == true) {
            _stateStatus = ProposalState.Passed;
        } else if (hasVotingPeriodExpired(proposal.startingTime, proposal.endingTime) && proposal.flags[2] == false) {
            _stateStatus = ProposalState.Rejected;
        } else if (hasVotingPeriodExpired(proposal.startingTime, proposal.endingTime)) {
            _stateStatus = ProposalState.Finished;
        }
    }
}
