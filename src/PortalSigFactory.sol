// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {PortalSig} from "./PortalSig.sol";

contract PortalSigFactory {
    mapping(address account => address[] portalSigWallets)
        private listOfPortalSigWalletsContractsByOwner;

    event PortalSigWalletDeployed(
        address[] indexed _owners,
        uint256 indexed _requiredConfirmationsAmount,
        address indexed contractAddress
    );

    function deployPortalSigWallet(
        address[] memory _owners,
        uint256 _requiredConfirmationsAmount,
        address _ccipRouterAddress,
        address _linkAddress,
        uint64 _portalChainSelector
    ) external {
        PortalSig portalSigWallet = new PortalSig(
            _owners,
            _requiredConfirmationsAmount,
            _ccipRouterAddress,
            _linkAddress,
            _portalChainSelector
        );
        for (uint256 i = 0; i < _owners.length; i++) {
            listOfPortalSigWalletsContractsByOwner[_owners[i]].push(
                address(portalSigWallet)
            );
        }
        emit PortalSigWalletDeployed(
            _owners,
            _requiredConfirmationsAmount,
            address(portalSigWallet)
        );
    }

    function getWalletsByOwner(
        address _owner
    ) public view returns (address[] memory) {
        return listOfPortalSigWalletsContractsByOwner[_owner];
    }
}
