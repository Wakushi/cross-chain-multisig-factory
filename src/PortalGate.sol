// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PortalGate is Ownable {
    using SafeERC20 for IERC20;

    enum PayFeesIn {
        Native,
        LINK
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

    IRouterClient s_ccipRouter;
    LinkTokenInterface immutable i_linkToken;
    uint256 public constant STANDARD_GAS_LIMIT = 200000;

    event MessageTransferred(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        address feeToken,
        uint256 fees
    );

    error PortalGate__NotEnoughBalanceForFees(
        uint256 currentBalance,
        uint256 calculatedFees
    );

    constructor(address _router, address _linkToken) Ownable(msg.sender) {
        s_ccipRouter = IRouterClient(_router);
        i_linkToken = LinkTokenInterface(_linkToken);
    }

    function updateCCIPRouter(address _ccipRouterAddress) external onlyOwner {
        s_ccipRouter = IRouterClient(_ccipRouterAddress);
    }

    function createTransaction(
        address _portalAddress,
        uint64 _portalChainSelector,
        address _destination,
        address _token,
        uint64 _destinationChainSelector,
        uint256 _amount,
        bytes memory _data,
        bool _executesOnRequirementMet,
        PayFeesIn _payFeesIn,
        uint256 _gasLimit,
        PayFeesIn _payGateFeesIn
    ) external {
        PortalCallArgs memory portalCallArgs = PortalCallArgs({
            sender: msg.sender,
            functionName: "createTransaction",
            transactionId: 0,
            destination: _destination,
            token: _token,
            destinationChainSelector: _destinationChainSelector,
            amount: _amount,
            data: _data,
            executesOnRequirementMet: _executesOnRequirementMet,
            payFeesIn: _payFeesIn,
            gasLimit: _gasLimit
        });

        bytes memory encodedPortalData = encodeArgs(portalCallArgs);

        _sendCrossChainMessage(
            _portalChainSelector,
            _portalAddress,
            encodedPortalData,
            _payGateFeesIn
        );
    }

    function confirmTransaction(
        address _portalAddress,
        uint64 _portalChainSelector,
        uint256 _transactionId,
        PayFeesIn _payGateFeesIn
    ) public {
        PortalCallArgs memory portalCallArgs = PortalCallArgs({
            sender: msg.sender,
            functionName: "confirmTransaction",
            transactionId: _transactionId,
            destination: address(0),
            token: address(0),
            destinationChainSelector: 0,
            amount: 0,
            data: new bytes(0),
            executesOnRequirementMet: false,
            payFeesIn: PayFeesIn.Native,
            gasLimit: 0
        });

        bytes memory encodedPortalData = encodeArgs(portalCallArgs);

        _sendCrossChainMessage(
            _portalChainSelector,
            _portalAddress,
            encodedPortalData,
            _payGateFeesIn
        );
    }

    function executeTransaction(
        address _portalAddress,
        uint64 _portalChainSelector,
        uint256 _transactionId,
        PayFeesIn _payGateFeesIn
    ) public {
        PortalCallArgs memory portalCallArgs = PortalCallArgs({
            sender: msg.sender,
            functionName: "executeTransaction",
            transactionId: _transactionId,
            destination: address(0),
            token: address(0),
            destinationChainSelector: 0,
            amount: 0,
            data: new bytes(0),
            executesOnRequirementMet: false,
            payFeesIn: PayFeesIn.Native,
            gasLimit: 0
        });

        bytes memory encodedPortalData = encodeArgs(portalCallArgs);

        _sendCrossChainMessage(
            _portalChainSelector,
            _portalAddress,
            encodedPortalData,
            _payGateFeesIn
        );
    }

    function revokeConfirmation(
        address _portalAddress,
        uint64 _portalChainSelector,
        uint256 _transactionId,
        PayFeesIn _payGateFeesIn
    ) public {
        PortalCallArgs memory portalCallArgs = PortalCallArgs({
            sender: msg.sender,
            functionName: "revokeConfirmation",
            transactionId: _transactionId,
            destination: address(0),
            token: address(0),
            destinationChainSelector: 0,
            amount: 0,
            data: new bytes(0),
            executesOnRequirementMet: false,
            payFeesIn: PayFeesIn.Native,
            gasLimit: 0
        });

        bytes memory encodedPortalData = encodeArgs(portalCallArgs);

        _sendCrossChainMessage(
            _portalChainSelector,
            _portalAddress,
            encodedPortalData,
            _payGateFeesIn
        );
    }

    function _sendCrossChainMessage(
        uint64 _destinationChainSelector,
        address _receiver,
        bytes memory _data,
        PayFeesIn _payGateFeesIn
    ) internal returns (bytes32 messageId) {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: _data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: STANDARD_GAS_LIMIT})
            ),
            feeToken: _payGateFeesIn == PayFeesIn.LINK
                ? address(i_linkToken)
                : address(0)
        });
        uint256 fees = s_ccipRouter.getFee(_destinationChainSelector, message);
        if (_payGateFeesIn == PayFeesIn.LINK) {
            if (fees > i_linkToken.balanceOf(address(this))) {
                revert PortalGate__NotEnoughBalanceForFees(
                    i_linkToken.balanceOf(address(this)),
                    fees
                );
            }
            i_linkToken.approve(address(s_ccipRouter), fees);
            messageId = s_ccipRouter.ccipSend(
                _destinationChainSelector,
                message
            );
        } else {
            if (fees > address(this).balance) {
                revert PortalGate__NotEnoughBalanceForFees(
                    address(this).balance,
                    fees
                );
            }
            messageId = s_ccipRouter.ccipSend{value: fees}(
                _destinationChainSelector,
                message
            );
        }

        emit MessageTransferred(
            messageId,
            _destinationChainSelector,
            _receiver,
            address(i_linkToken),
            fees
        );
    }

    function encodeArgs(
        PortalCallArgs memory _encodePortalCall
    ) internal pure returns (bytes memory) {
        bytes memory encodedArgs = abi.encode(
            _encodePortalCall.sender,
            _encodePortalCall.functionName,
            _encodePortalCall.transactionId,
            _encodePortalCall.destination,
            _encodePortalCall.token,
            _encodePortalCall.destinationChainSelector,
            _encodePortalCall.amount,
            _encodePortalCall.data,
            _encodePortalCall.executesOnRequirementMet,
            _encodePortalCall.payFeesIn,
            _encodePortalCall.gasLimit
        );
        return encodedArgs;
    }

    function getMessageFee(
        uint64 _destinationChainSelector,
        bytes memory _data
    ) external view returns (uint256) {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(0)),
            data: _data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: STANDARD_GAS_LIMIT})
            ),
            feeToken: address(i_linkToken)
        });

        return s_ccipRouter.getFee(_destinationChainSelector, message);
    }
}
