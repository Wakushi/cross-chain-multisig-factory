// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Portal} from "./Portal.sol";

contract PortalSig is Portal {
    //////////////
    //  TYPES   //
    //////////////

    struct Transaction {
        address destination;
        address token;
        address initiator;
        uint64 destinationChainSelector;
        uint256 amount;
        uint256 numberOfConfirmations;
        uint256 gasLimit;
        bytes data;
        bool executed;
        bool executesOnRequirementMet;
        PayFeesIn payFeesIn;
    }

    //////////////
    //  STATE   //
    //////////////

    // Multisig
    address[] private s_owners;
    Transaction[] private s_transactions;
    mapping(uint256 transactionId => mapping(address account => bool hasConfirmed))
        private s_isConfirmedByAccount;
    uint256 private immutable i_requiredConfirmationsAmount;

    //////////////
    //  EVENTS  //
    //////////////

    event TransactionCreated(
        address indexed destination,
        uint256 indexed value,
        uint64 indexed destinationChainSelector,
        bytes data
    );

    event TransactionConfirmed(
        uint256 indexed transactionId,
        address indexed account
    );

    event TransactionConfirmationRevoked(
        uint256 indexed transactionId,
        address indexed account
    );

    event TransactionExecuted(uint256 indexed transactionId);

    //////////////
    //  ERRORS  //
    //////////////

    error PortalSig__NeedAtLeastTwoOwners(uint256 ownersLength);
    error PortalSig__InvalidOwnerAddress();
    error PortalSig__OwnerNotUnique();
    error PortalSig__InvalidTransactionId(uint256 transactionId);
    error PortalSig__AlreadyExecuted(uint256 transactionId);
    error PortalSig__AlreadyConfirmed(uint256 transactionId);
    error PortalSig__NotEnoughConfirmations(uint256 transactionId);
    error PortalSig__TransactionExecutionFailed(uint256 transactionId);
    error PortalSig__NotConfirmed(uint256 transactionId);
    error PortalSig__RequiredConfirmationsGreaterThanOwnersLength(
        uint256 requiredConfirmations,
        uint256 ownersLength
    );
    error PortalSig__InvalidConfirmationAmount(uint256 requiredConfirmations);

    /////////////////
    //  MODIFIERS  //
    /////////////////

    modifier transactionExists(uint256 _transactionId) {
        _ensureTransactionExists(_transactionId);
        _;
    }

    modifier transactionNotExecuted(uint256 _transactionId) {
        _ensureTransactionNotExecuted(_transactionId);
        _;
    }

    /////////////////
    //  FUNCTIONS  //
    /////////////////

    constructor(
        address[] memory _owners,
        uint256 _requiredConfirmationsAmount,
        address _ccipRouterAddress,
        address _linkAddress
    ) Portal(_ccipRouterAddress, _linkAddress) {
        _ensureMultisigValidity(_owners, _requiredConfirmationsAmount);
        _registerOwners(_owners);
        i_requiredConfirmationsAmount = _requiredConfirmationsAmount;
    }

    receive() external payable {}

    fallback() external payable {}

    /////////////////
    //   EXTERNAL  //
    /////////////////

    /////////////////
    //   PUBLIC    //
    /////////////////

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

    /////////////////
    //  INTERNAL   //
    /////////////////

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

    function _createTransaction(
        address _destination,
        address _token,
        address _initiator,
        uint64 _destinationChainSelector,
        uint256 _amount,
        bytes memory _data,
        bool _executesOnRequirementMet,
        PayFeesIn _payFeesIn,
        uint256 _gasLimit
    ) internal {
        s_transactions.push(
            Transaction({
                destination: _destination,
                token: _token,
                initiator: _initiator,
                destinationChainSelector: _destinationChainSelector,
                amount: _amount,
                numberOfConfirmations: 0,
                data: _data,
                executed: false,
                executesOnRequirementMet: _executesOnRequirementMet,
                payFeesIn: _payFeesIn,
                gasLimit: _gasLimit
            })
        );
        emit TransactionCreated(
            _destination,
            _amount,
            _destinationChainSelector,
            _data
        );
    }

    function _confirmTransaction(
        uint256 _transactionId,
        address _account
    ) internal {
        s_isConfirmedByAccount[_transactionId][_account] = true;
        Transaction storage transaction = s_transactions[_transactionId];
        ++transaction.numberOfConfirmations;
        if (
            transaction.executesOnRequirementMet &&
            hasEnoughConfirmations(_transactionId)
        ) {
            _executeTransaction(_transactionId);
        }
        emit TransactionConfirmed(_transactionId, _account);
    }

    function _executeTransaction(uint256 _transactionId) internal {
        Transaction storage transaction = s_transactions[_transactionId];
        transaction.executed = true;
        if (transaction.destinationChainSelector != 0) {
            _ensureWhiteListedChain(transaction.destinationChainSelector);
            _sendCrossChain(
                transaction.destinationChainSelector,
                transaction.destination,
                transaction.token,
                transaction.amount,
                transaction.data,
                transaction.payFeesIn,
                transaction.gasLimit
            );
        } else if (transaction.token != address(0)) {
            _transferERC20Token(
                transaction.destination,
                transaction.token,
                transaction.amount
            );
        } else {
            _transferNativeTokenAndData(
                transaction.destination,
                transaction.amount,
                transaction.data,
                _transactionId
            );
        }
        emit TransactionExecuted(_transactionId);
    }

    function _revokeConfirmation(
        uint256 _transactionId,
        address _account
    ) internal {
        s_isConfirmedByAccount[_transactionId][_account] = false;
        Transaction storage transaction = s_transactions[_transactionId];
        --transaction.numberOfConfirmations;
        emit TransactionConfirmationRevoked(_transactionId, _account);
    }

    function _transferERC20Token(
        address _destination,
        address _token,
        uint256 _amount
    ) internal {
        IERC20(_token).transfer(_destination, _amount);
    }

    function _transferNativeTokenAndData(
        address _destination,
        uint256 _amount,
        bytes memory _data,
        uint256 _transactionId
    ) internal {
        (bool success, ) = _destination.call{value: _amount}(_data);
        if (!success) {
            revert PortalSig__TransactionExecutionFailed(_transactionId);
        }
    }

    function _ensureTransactionExists(uint256 _transactionId) internal view {
        if (_transactionId >= s_transactions.length) {
            revert PortalSig__InvalidTransactionId(_transactionId);
        }
    }

    function _ensureTransactionNotExecuted(
        uint256 _transactionId
    ) internal view {
        if (s_transactions[_transactionId].executed) {
            revert PortalSig__AlreadyExecuted(_transactionId);
        }
    }

    function _ensureNotConfirmedByAccount(
        uint256 _transactionId,
        address _account
    ) internal view {
        if (s_isConfirmedByAccount[_transactionId][_account]) {
            revert PortalSig__AlreadyConfirmed(_transactionId);
        }
    }

    function _ensureConfirmedByAccount(
        uint256 _transactionId,
        address _account
    ) internal view {
        if (!s_isConfirmedByAccount[_transactionId][_account]) {
            revert PortalSig__NotConfirmed(_transactionId);
        }
    }

    function _ensureEnoughConfirmations(
        uint256 _transactionId
    ) internal view returns (bool) {
        if (
            s_transactions[_transactionId].numberOfConfirmations <
            i_requiredConfirmationsAmount
        ) {
            revert PortalSig__NotEnoughConfirmations(_transactionId);
        }
        return true;
    }

    ////////////////////
    //  VIEW / PURE   //
    ////////////////////

    function getTransaction(
        uint256 _transactionId
    ) public view returns (Transaction memory) {
        return s_transactions[_transactionId];
    }

    function getTransactions() public view returns (Transaction[] memory) {
        return s_transactions;
    }

    function getOwners() public view returns (address[] memory) {
        return s_owners;
    }

    function getRequiredConfirmationsAmount()
        public
        view
        returns (uint256 requiredConfirmationsAmount)
    {
        return i_requiredConfirmationsAmount;
    }

    function getTransactionCount() public view returns (uint256) {
        return s_transactions.length;
    }

    function isConfirmedByAccount(
        uint256 _transactionId,
        address _account
    ) public view returns (bool) {
        return s_isConfirmedByAccount[_transactionId][_account];
    }

    function hasEnoughConfirmations(
        uint256 _transactionId
    ) public view returns (bool) {
        return
            s_transactions[_transactionId].numberOfConfirmations >=
            i_requiredConfirmationsAmount;
    }
}
