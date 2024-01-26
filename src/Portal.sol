// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

contract Portal {
    using SafeERC20 for IERC20;

    //////////////
    //  TYPES   //
    //////////////

    enum PayFeesIn {
        Native,
        LINK
    }

    //////////////
    //  STATE   //
    //////////////

    // CCIP
    IRouterClient immutable i_ccipRouter;
    LinkTokenInterface immutable i_link;
    mapping(uint64 chainSelector => bool isAllowlisted)
        private allowlistedDestinationChains;

    // Multisig
    mapping(address account => bool isOwner) internal s_isOwner;

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

    //////////////
    //  ERRORS  //
    //////////////

    error PortalSig__NotOwner(address account);
    error PortalSig__DestinationChainNotAllowlisted(
        uint64 destinationChainSelector
    );
    error PortalSig__NotEnoughBalanceForFees(
        uint256 currentBalance,
        uint256 calculatedFees
    );

    /////////////////
    //  MODIFIERS  //
    /////////////////

    modifier onlyOwner(address _owner) {
        _ensureOwnership(_owner);
        _;
    }

    modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
        _ensureWhiteListedChain(_destinationChainSelector);
        _;
    }

    /////////////////
    //  FUNCTIONS  //
    /////////////////

    constructor(address ccipRouterAddress, address linkAddress) {
        i_ccipRouter = IRouterClient(ccipRouterAddress);
        i_link = LinkTokenInterface(linkAddress);
    }

    /////////////////
    //   EXTERNAL  //
    /////////////////

    /// @dev Updates the allowlist status of a destination chain for transactions.
    /// @notice This function can only be called by the owner.
    /// @param _destinationChainSelector The selector of the destination chain to be updated.
    /// @param allowed The allowlist status to be set for the destination chain.
    function allowlistDestinationChain(
        uint64 _destinationChainSelector,
        bool allowed
    ) external onlyOwner(msg.sender) {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }

    /////////////////
    //  INTERNAL   //
    /////////////////

    function _sendCrossChain(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount,
        bytes memory _data,
        PayFeesIn _payFeesIn,
        uint256 _gasLimit
    )
        internal
        onlyAllowlistedDestinationChain(_destinationChainSelector)
        returns (bytes32 messageId)
    {
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

        uint256 fees = i_ccipRouter.getFee(_destinationChainSelector, message);

        if (_payFeesIn == PayFeesIn.LINK) {
            if (fees > i_link.balanceOf(address(this)))
                revert PortalSig__NotEnoughBalanceForFees(
                    i_link.balanceOf(address(this)),
                    fees
                );

            i_link.approve(address(i_ccipRouter), fees);

            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
            IERC20(_token).approve(address(i_ccipRouter), _amount);

            messageId = i_ccipRouter.ccipSend(
                _destinationChainSelector,
                message
            );
        } else {
            if (fees > address(this).balance)
                revert PortalSig__NotEnoughBalanceForFees(
                    address(this).balance,
                    fees
                );

            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
            IERC20(_token).approve(address(i_ccipRouter), _amount);

            messageId = i_ccipRouter.ccipSend{value: fees}(
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

    function _ensureWhiteListedChain(uint64 _chainSelector) internal view {
        if (!allowlistedDestinationChains[_chainSelector]) {
            revert PortalSig__DestinationChainNotAllowlisted(_chainSelector);
        }
    }

    ////////////////////
    //  VIEW / PURE   //
    ////////////////////

    function isOwner(address _owner) public view returns (bool) {
        return s_isOwner[_owner];
    }
}
