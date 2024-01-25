// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CrossChainMultisig {
    //////////////
    //  TYPES   //
    //////////////

    struct Transaction {
        address destination;
        address token;
        uint64 destinationChainSelector;
        uint256 amount;
        uint256 numberOfConfirmations;
        bytes data;
        bool executed;
        bool executesOnRequirementMet;
    }

    //////////////
    //  STATE   //
    //////////////

    address[] private s_owners;
    Transaction[] private s_transactions;
    mapping(address account => bool isOwner) s_isOwner;
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

    error CrossChainMultisig__NeedAtLeastTwoOwners(uint256 ownersLength);
    error CrossChainMultisig__InvalidOwnerAddress();
    error CrossChainMultisig__OwnerNotUnique();
    error CrossChainMultisig__NotOwner(address account);
    error CrossChainMultisig__InvalidTransactionId(uint256 transactionId);
    error CrossChainMultisig__AlreadyExecuted(uint256 transactionId);
    error CrossChainMultisig__AlreadyConfirmed(uint256 transactionId);
    error CrossChainMultisig__NotEnoughConfirmations(uint256 transactionId);
    error CrossChainMultisig__TransactionExecutionFailed(uint256 transactionId);
    error CrossChainMultisig__NotConfirmed(uint256 transactionId);
    error CrossChainMultisig__RequiredConfirmationsGreaterThanOwnersLength(
        uint256 requiredConfirmations,
        uint256 ownersLength
    );
    error CrossChainMultisig__InvalidConfirmationAmount(
        uint256 requiredConfirmations
    );

    /////////////////
    //  MODIFIERS  //
    /////////////////

    modifier onlyOwner(address _owner) {
        _ensureOwnership(_owner);
        _;
    }

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
        uint256 _requiredConfirmationsAmount
    ) {
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
        bool _executesOnRequirementMet
    ) public onlyOwner(msg.sender) {
        _createTransaction(
            _destination,
            _token,
            _destinationChainSelector,
            _amount,
            _data,
            _executesOnRequirementMet
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
                revert CrossChainMultisig__InvalidOwnerAddress();
            }
            if (isOwner(owner)) {
                revert CrossChainMultisig__OwnerNotUnique();
            }
            s_isOwner[owner] = true;
            s_owners.push(owner);
        }
    }

    function _createTransaction(
        address _destination,
        address _token,
        uint64 _destinationChainSelector,
        uint256 _amount,
        bytes memory _data,
        bool _executesOnRequirementMet
    ) internal {
        s_transactions.push(
            Transaction({
                destination: _destination,
                token: _token,
                destinationChainSelector: _destinationChainSelector,
                amount: _amount,
                numberOfConfirmations: 0,
                data: _data,
                executed: false,
                executesOnRequirementMet: _executesOnRequirementMet
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
        if (transaction.token != address(0)) {
            IERC20(transaction.token).transfer(
                transaction.destination,
                transaction.amount
            );
        } else {
            (bool success, ) = transaction.destination.call{
                value: transaction.amount
            }(transaction.data);
            if (!success) {
                revert CrossChainMultisig__TransactionExecutionFailed(
                    _transactionId
                );
            }
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

    function _ensureMultisigValidity(
        address[] memory _owners,
        uint256 _requiredConfirmationsAmount
    ) internal pure {
        if (_owners.length < 2) {
            revert CrossChainMultisig__NeedAtLeastTwoOwners(_owners.length);
        }
        if (
            _requiredConfirmationsAmount < 1 ||
            _requiredConfirmationsAmount > _owners.length
        ) {
            revert CrossChainMultisig__InvalidConfirmationAmount(
                _requiredConfirmationsAmount
            );
        }
    }

    function _ensureOwnership(address _owner) internal view {
        if (!isOwner(_owner)) {
            revert CrossChainMultisig__NotOwner(_owner);
        }
    }

    function _ensureTransactionExists(uint256 _transactionId) internal view {
        if (_transactionId >= s_transactions.length) {
            revert CrossChainMultisig__InvalidTransactionId(_transactionId);
        }
    }

    function _ensureTransactionNotExecuted(
        uint256 _transactionId
    ) internal view {
        if (s_transactions[_transactionId].executed) {
            revert CrossChainMultisig__AlreadyExecuted(_transactionId);
        }
    }

    function _ensureNotConfirmedByAccount(
        uint256 _transactionId,
        address _account
    ) internal view {
        if (s_isConfirmedByAccount[_transactionId][_account]) {
            revert CrossChainMultisig__AlreadyConfirmed(_transactionId);
        }
    }

    function _ensureConfirmedByAccount(
        uint256 _transactionId,
        address _account
    ) internal view {
        if (!s_isConfirmedByAccount[_transactionId][_account]) {
            revert CrossChainMultisig__NotConfirmed(_transactionId);
        }
    }

    function _ensureEnoughConfirmations(
        uint256 _transactionId
    ) internal view returns (bool) {
        if (
            s_transactions[_transactionId].numberOfConfirmations <
            i_requiredConfirmationsAmount
        ) {
            revert CrossChainMultisig__NotEnoughConfirmations(_transactionId);
        }
        return true;
    }

    ////////////////////
    //  VIEW / PURE   //
    ////////////////////

    function isOwner(address _owner) public view returns (bool) {
        return s_isOwner[_owner];
    }

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
