// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Portal} from "./Portal.sol";

contract PortalSig is Portal {
    address[] private s_owners;

    error PortalSig__NeedAtLeastTwoOwners(uint256 ownersLength);
    error PortalSig__InvalidOwnerAddress();
    error PortalSig__OwnerNotUnique();
    error PortalSig__RequiredConfirmationsGreaterThanOwnersLength(
        uint256 requiredConfirmations,
        uint256 ownersLength
    );
    error PortalSig__InvalidConfirmationAmount(uint256 requiredConfirmations);

    constructor(
        address[] memory _owners,
        uint256 _requiredConfirmationsAmount,
        address _ccipRouterAddress,
        address _linkAddress,
        uint64 _portalChainSelector
    )
        Portal(
            _ccipRouterAddress,
            _linkAddress,
            _portalChainSelector,
            _requiredConfirmationsAmount
        )
    {
        _ensureMultisigValidity(_owners, _requiredConfirmationsAmount);
        _registerOwners(_owners);
    }

    receive() external payable {}

    fallback() external payable {}

    function createTransaction(
        address _destination,
        address _token,
        uint64 _destinationChainSelector,
        uint256 _amount,
        bytes memory _data,
        bool _executesOnRequirementMet,
        PayFeesIn _payFeesIn,
        uint256 _gasLimit
    ) public onlyOwner(msg.sender) {
        _createTransaction(
            _destination,
            _token,
            msg.sender,
            _destinationChainSelector,
            _amount,
            _data,
            _executesOnRequirementMet,
            _payFeesIn,
            _gasLimit
        );
    }

    function confirmTransaction(
        uint256 _transactionId
    )
        public
        onlyOwner(msg.sender)
        transactionExists(_transactionId)
        transactionNotExecuted(_transactionId)
    {
        _ensureNotConfirmedByAccount(_transactionId, msg.sender);
        _confirmTransaction(_transactionId, msg.sender);
    }

    function executeTransaction(
        uint256 _transactionId
    )
        public
        onlyOwner(msg.sender)
        transactionExists(_transactionId)
        transactionNotExecuted(_transactionId)
    {
        _ensureEnoughConfirmations(_transactionId);
        _executeTransaction(_transactionId);
    }

    function revokeConfirmation(
        uint256 _transactionId
    )
        public
        onlyOwner(msg.sender)
        transactionExists(_transactionId)
        transactionNotExecuted(_transactionId)
    {
        _ensureConfirmedByAccount(_transactionId, msg.sender);
        _revokeConfirmation(_transactionId, msg.sender);
    }

    function _registerOwners(address[] memory _owners) internal {
        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            if (owner == address(0)) {
                revert PortalSig__InvalidOwnerAddress();
            }
            if (isOwner(owner)) {
                revert PortalSig__OwnerNotUnique();
            }
            s_isOwner[owner] = true;
            s_owners.push(owner);
        }
    }

    function _ensureMultisigValidity(
        address[] memory _owners,
        uint256 _requiredConfirmationsAmount
    ) internal pure {
        if (_owners.length < 2) {
            revert PortalSig__NeedAtLeastTwoOwners(_owners.length);
        }
        if (
            _requiredConfirmationsAmount < 1 ||
            _requiredConfirmationsAmount > _owners.length
        ) {
            revert PortalSig__InvalidConfirmationAmount(
                _requiredConfirmationsAmount
            );
        }
    }

    function getOwners() public view returns (address[] memory) {
        return s_owners;
    }
}
