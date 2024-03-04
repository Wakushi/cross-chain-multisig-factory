// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {EnumerableMap} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/utils/structs/EnumerableMap.sol";

contract Portal is CCIPReceiver {
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.Bytes32ToUintMap;

    //////////////
    //  TYPES   //
    //////////////

    enum PayFeesIn {
        Native,
        LINK
    }

    enum ErrorCode {
        RESOLVED,
        BASIC
    }

    struct Transaction {
        address destination;
        address token;
        address initiator;
        uint64 destinationChainSelector;
        uint256 id;
        uint256 amount;
        uint256 numberOfConfirmations;
        uint256 gasLimit;
        uint256 createdAt;
        uint256 executedAt;
        bytes data;
        bool executed;
        bool executesOnRequirementMet;
        PayFeesIn payFeesIn;
    }

    struct PortalCallArgs {
        address sender;
        string functionName;
        uint256 transactionId;
        address destination;
        address token;
        uint64 destinationChainSelector;
        uint256 amount;
        bytes data;
        bool executesOnRequirementMet;
        PayFeesIn payFeesIn;
        uint256 gasLimit;
    }

    //////////////
    //  STATE   //
    //////////////

    // CCIP
    LinkTokenInterface immutable i_link;
    IRouterClient s_ccipRouter;
    uint64 immutable i_portalChainSelector;
    EnumerableMap.Bytes32ToUintMap internal s_failedMessages;
    mapping(bytes32 messageId => Client.Any2EVMMessage contents)
        public s_messageContents;

    string public constant CREATE_TRANSACTION_METHOD = "createTransaction";
    string public constant EXECUTE_TRANSACTION_METHOD = "executeTransaction";
    string public constant CONFIRM_TRANSACTION_METHOD = "confirmTransaction";
    string public constant REVOKE_CONFIRMATION_METHOD = "revokeConfirmation";

    // Multisig
    mapping(address account => bool isOwner) internal s_isOwner;
    Transaction[] private s_transactions;
    mapping(uint256 transactionId => mapping(address account => bool hasConfirmed))
        private s_isConfirmedByAccount;
    uint256 private immutable i_requiredConfirmationsAmount;

    //////////////
    //  EVENTS  //
    //////////////

    event MessageSent(
        bytes32 indexed messageId,
        uint64 destinationChainSelector,
        address receiver,
        address token,
        uint256 amount,
        PayFeesIn payFeesIn,
        uint256 fees
    );
    event MessageFailed(bytes32 indexed messageId, bytes reason);
    event MessageRecovered(bytes32 indexed messageId);
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

    error PortalSig__NotOwner(address account);
    error PortalSig__OnlySelf();
    error PortalSig__DestinationChainNotAllowlisted(
        uint64 destinationChainSelector
    );
    error PortalSig__NotEnoughBalanceForFees(
        uint256 currentBalance,
        uint256 calculatedFees
    );
    error PortalSig__MessageNotFailed(bytes32 messageId);
    error PortalSig__TransactionExecutionFailed(uint256 transactionId);
    error PortalSig__InvalidTransactionId(uint256 transactionId);
    error PortalSig__AlreadyExecuted(uint256 transactionId);
    error PortalSig__AlreadyConfirmed(uint256 transactionId);
    error PortalSig__NotEnoughConfirmations(uint256 transactionId);
    error PortalSig__NotConfirmed(uint256 transactionId);

    /////////////////
    //  MODIFIERS  //
    /////////////////

    modifier onlyOwner(address _owner) {
        _ensureOwnership(_owner);
        _;
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) revert PortalSig__OnlySelf();
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
        address _ccipRouterAddress,
        address _linkAddress,
        uint64 _portalChainSelector,
        uint256 _requiredConfirmationsAmount
    ) CCIPReceiver(_ccipRouterAddress) {
        s_ccipRouter = IRouterClient(_ccipRouterAddress);
        i_link = LinkTokenInterface(_linkAddress);
        i_portalChainSelector = _portalChainSelector;
        i_requiredConfirmationsAmount = _requiredConfirmationsAmount;
    }

    function ccipReceive(
        Client.Any2EVMMessage calldata any2EvmMessage
    ) external override onlyRouter {
        /* solhint-disable no-empty-blocks */
        try this.processMessage(any2EvmMessage) {} catch (bytes memory err) {
            s_failedMessages.set(
                any2EvmMessage.messageId,
                uint256(ErrorCode.BASIC)
            );
            s_messageContents[any2EvmMessage.messageId] = any2EvmMessage;
            emit MessageFailed(any2EvmMessage.messageId, err);
            return;
        }
    }

    function processMessage(
        Client.Any2EVMMessage calldata any2EvmMessage
    ) external onlySelf {
        _ccipReceive(any2EvmMessage);
    }

    function retryFailedMessage(
        bytes32 messageId,
        address tokenReceiver
    ) external onlyOwner(msg.sender) {
        if (s_failedMessages.get(messageId) != uint256(ErrorCode.BASIC))
            revert PortalSig__MessageNotFailed(messageId);

        s_failedMessages.set(messageId, uint256(ErrorCode.RESOLVED));

        Client.Any2EVMMessage memory message = s_messageContents[messageId];

        IERC20(message.destTokenAmounts[0].token).safeTransfer(
            tokenReceiver,
            message.destTokenAmounts[0].amount
        );

        emit MessageRecovered(messageId);
    }

    function updateCCIPRouter(
        address _ccipRouterAddress
    ) external onlyOwner(msg.sender) {
        s_ccipRouter = IRouterClient(_ccipRouterAddress);
    }

    /////////////////
    //  INTERNAL   //
    /////////////////

    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override {
        PortalCallArgs memory portalCall = decodeWhole(any2EvmMessage.data);
        _ensureOwnership(portalCall.sender);
        if (
            compareStrings(portalCall.functionName, CREATE_TRANSACTION_METHOD)
        ) {
            _createTransaction(
                portalCall.destination,
                portalCall.token,
                portalCall.sender,
                portalCall.destinationChainSelector,
                portalCall.amount,
                portalCall.data,
                portalCall.executesOnRequirementMet,
                portalCall.payFeesIn,
                portalCall.gasLimit
            );
        } else {
            _ensureTransactionExists(portalCall.transactionId);
            _ensureTransactionNotExecuted(portalCall.transactionId);
            if (
                compareStrings(
                    portalCall.functionName,
                    EXECUTE_TRANSACTION_METHOD
                )
            ) {
                _ensureEnoughConfirmations(portalCall.transactionId);
                _executeTransaction(portalCall.transactionId);
            } else if (
                compareStrings(
                    portalCall.functionName,
                    CONFIRM_TRANSACTION_METHOD
                )
            ) {
                _ensureNotConfirmedByAccount(
                    portalCall.transactionId,
                    portalCall.sender
                );
                _confirmTransaction(
                    portalCall.transactionId,
                    portalCall.sender
                );
            } else if (
                compareStrings(
                    portalCall.functionName,
                    REVOKE_CONFIRMATION_METHOD
                )
            ) {
                _ensureConfirmedByAccount(
                    portalCall.transactionId,
                    portalCall.sender
                );
                _revokeConfirmation(
                    portalCall.transactionId,
                    portalCall.sender
                );
            }
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
        uint256 transactionId = s_transactions.length;
        s_transactions.push(
            Transaction({
                id: transactionId,
                destination: _destination,
                token: _token,
                initiator: _initiator,
                destinationChainSelector: _destinationChainSelector,
                amount: _amount,
                numberOfConfirmations: 0,
                data: _data,
                executed: false,
                createdAt: block.timestamp,
                executedAt: 0,
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
        transaction.executedAt = block.timestamp;
        if (transaction.destinationChainSelector != i_portalChainSelector) {
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

    function decodeWhole(
        bytes memory encodedPackage
    ) internal pure returns (PortalCallArgs memory) {
        (
            address sender,
            string memory functionName,
            uint256 transactionId,
            address destination,
            address token,
            uint64 destinationChainSelector,
            uint256 amount,
            bytes memory data,
            bool executesOnRequirementMet,
            PayFeesIn payFeesIn,
            uint256 gasLimit
        ) = abi.decode(
                encodedPackage,
                (
                    address,
                    string,
                    uint256,
                    address,
                    address,
                    uint64,
                    uint256,
                    bytes,
                    bool,
                    PayFeesIn,
                    uint256
                )
            );

        return
            PortalCallArgs({
                sender: sender,
                functionName: functionName,
                transactionId: transactionId,
                destination: destination,
                token: token,
                destinationChainSelector: destinationChainSelector,
                amount: amount,
                data: data,
                executesOnRequirementMet: executesOnRequirementMet,
                payFeesIn: payFeesIn,
                gasLimit: gasLimit
            });
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

    function _sendCrossChain(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount,
        bytes memory _data,
        PayFeesIn _payFeesIn,
        uint256 _gasLimit
    ) internal returns (bytes32 messageId) {
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });
        tokenAmounts[0] = tokenAmount;

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: _data,
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: _gasLimit})
            ),
            feeToken: _payFeesIn == PayFeesIn.LINK
                ? address(i_link)
                : address(0)
        });

        uint256 fees = s_ccipRouter.getFee(_destinationChainSelector, message);

        if (_payFeesIn == PayFeesIn.LINK) {
            if (fees > i_link.balanceOf(address(this))) {
                revert PortalSig__NotEnoughBalanceForFees(
                    i_link.balanceOf(address(this)),
                    fees
                );
            }

            i_link.approve(address(s_ccipRouter), fees);

            IERC20(_token).approve(address(s_ccipRouter), _amount);

            messageId = s_ccipRouter.ccipSend(
                _destinationChainSelector,
                message
            );
        } else {
            if (fees > address(this).balance) {
                revert PortalSig__NotEnoughBalanceForFees(
                    address(this).balance,
                    fees
                );
            }

            IERC20(_token).approve(address(s_ccipRouter), _amount);

            messageId = s_ccipRouter.ccipSend{value: fees}(
                _destinationChainSelector,
                message
            );
        }

        emit MessageSent(
            messageId,
            _destinationChainSelector,
            _receiver,
            _token,
            _amount,
            _payFeesIn,
            fees
        );
    }

    function _ensureOwnership(address _owner) internal view {
        if (!isOwner(_owner)) {
            revert PortalSig__NotOwner(_owner);
        }
    }

    ////////////////////
    //  VIEW / PURE   //
    ////////////////////

    function isOwner(address _owner) public view returns (bool) {
        return s_isOwner[_owner];
    }

    function hasEnoughConfirmations(
        uint256 _transactionId
    ) public view returns (bool) {
        return
            s_transactions[_transactionId].numberOfConfirmations >=
            i_requiredConfirmationsAmount;
    }

    function getTransaction(
        uint256 _transactionId
    ) public view returns (Transaction memory) {
        return s_transactions[_transactionId];
    }

    function getTransactions() public view returns (Transaction[] memory) {
        return s_transactions;
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

    function getFailedMessagesIds()
        external
        view
        returns (bytes32[] memory ids)
    {
        uint256 length = s_failedMessages.length();
        bytes32[] memory allKeys = new bytes32[](length);
        for (uint256 i = 0; i < length; i++) {
            (bytes32 key, ) = s_failedMessages.at(i);
            allKeys[i] = key;
        }
        return allKeys;
    }

    function compareStrings(
        string memory a,
        string memory b
    ) public pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function getPortalChainSelector() public view returns (uint64) {
        return i_portalChainSelector;
    }
}
