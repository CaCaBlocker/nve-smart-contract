// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface INeloverseDAO {
  function checkProposalId(uint256 proposalId) external view returns (bool);
  function getProposalFlags(uint256 proposalId) external view returns (bool[4] memory);
  function getProposalTargetAddress(uint256 proposalId) external view returns (address);
  function actionProposal(uint256 proposalId) external;
  function getActionProposalStatus(uint256 proposalId) external view returns (bool);
}
