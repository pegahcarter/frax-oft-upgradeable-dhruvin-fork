// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { FraxOFTUpgradeable } from "contracts/FraxOFTUpgradeable.sol";
import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev deploy OFT on X-Layer and hookup to Fraxtal OFT
// forge script scripts/UpgradeFrax/test/setup/2b_DeployOFT.s.sol --rpc-url https://xlayerrpc.okx.com
contract DeployOFT is DeployFraxOFTProtocol {
    address adapter = 0x103C430c9Fcaa863EA90386e3d0d5cd53333876e;
    FraxOFTUpgradeable public oft;

    constructor() {
        // already deployed
        implementationMock = 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250;
        proxyAdmin = vm.addr(senderDeployerPK);
    }

    function run() public override {
        delete legacyOfts;
        legacyOfts.push(adapter);

        // deploySource();
        // setupSource();
        (address imp, address proxy) = deployFraxOFTUpgradeableAndProxy({
            _name: "Carters OFT",
            _symbol: "COFT"
        });
        console.log("Implementation @ ", imp);
        console.log("Proxy @ ", proxy);

        // Setup source
        setupSource();
    }

    /// @dev configDeployer as proxy admin, broadcast as configDeployer
    function deployFraxOFTUpgradeableAndProxy(
        string memory _name,
        string memory _symbol
    ) public override broadcastAs(configDeployerPK) returns (address implementation, address proxy) {
        bytes memory bytecode = bytes.concat(
            abi.encodePacked(type(FraxOFTUpgradeable).creationCode),
            abi.encode(broadcastConfig.endpoint)
        );
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }
        /// @dev: create semi-pre-deterministic proxy address, then initialize with correct implementation
        proxy = address(new TransparentUpgradeableProxy(implementationMock, /*vm.addr(oftDeployerPK) */ vm.addr(configDeployerPK), ""));

        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTUpgradeable.initialize.selector,
            _name,
            _symbol,
            vm.addr(configDeployerPK)
        );
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);
        // TODO: will need to look at these instead of expectedProxyOFTs if the deployed addrs are different than expected
        proxyOfts.push(proxy);

        // State checks
        require(
            isStringEqual(FraxOFTUpgradeable(proxy).name(), _name),
            "OFT name incorrect"
        );
        require(
            isStringEqual(FraxOFTUpgradeable(proxy).symbol(), _symbol),
            "OFT symbol incorrect"
        );
        require(
            address(FraxOFTUpgradeable(proxy).endpoint()) == broadcastConfig.endpoint,
            "OFT endpoint incorrect"
        );
        require(
            EndpointV2(broadcastConfig.endpoint).delegates(proxy) == vm.addr(configDeployerPK),
            "Endpoint delegate incorrect"
        );
        require(
            FraxOFTUpgradeable(proxy).owner() == vm.addr(configDeployerPK),
            "OFT owner incorrect"
        );
    }

    function setupSource() public override broadcastAs(configDeployerPK) {
        setupEvms();
        // setupNonEvms();

        setDVNs({
            _connectedConfig: broadcastConfig,
            _connectedOfts: proxyOfts,
            _configs: allConfigs
        });

        // setPriviledgedRoles();
    }

    function setupEvms() public override {
        setEvmEnforcedOptions({
            _connectedOfts: proxyOfts,
            _configs: evmConfigs
        });

        /// @dev legacy, non-upgradeable OFTs
        setEvmPeers({
            _connectedOfts: proxyOfts,
            _peerOfts: legacyOfts,
            _configs: /* legacyConfigs */ proxyConfigs // to include fraxtal adapter
        });
        /// @dev Upgradeable OFTs maintaining the same address cross-chain.
        // setEvmPeers({
        //     _connectedOfts: proxyOfts,
        //     _peerOfts: proxyOfts,
        //     _configs: proxyConfigs
        // });
    }
}