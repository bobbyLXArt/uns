// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';

import './cns/ICryptoResolver.sol';
import './cns/ICryptoSLDMinter.sol';
import './IMintingManager.sol';
import './IRegistry.sol';
import './metatx/Relayer.sol';
import './roles/MinterRole.sol';

/**
 * @title MintingManager
 * @dev Defines the functions for distribution of Second Level Domains (SLD)s.
 */
contract MintingManager is Initializable, ContextUpgradeable, OwnableUpgradeable, MinterRole, Relayer, IMintingManager {
    string public constant NAME = 'UNS: Minting Manager';
    string public constant VERSION = '0.1.0';

    IRegistry public UnsRegistry;
    ICryptoSLDMinter public CryptoMinter;
    ICryptoResolver public CryptoResolver;

    /**
     * @dev Mapping TLD `hashname` to TLD label
     *
     * `hashname` = uint256(keccak256(abi.encodePacked(uint256(0x0), keccak256(abi.encodePacked(label)))))
     */
    mapping(uint256 => string) internal _tlds;

    /**
     * @dev bytes4(keccak256('mintSLD(address,uint256,string)')) == 0xae2ad903
     */
    bytes4 private constant _SIG_MINT = 0xae2ad903;

    /**
     * @dev bytes4(keccak256('safeMintSLD(address,uint256,string)')) == 0x4c1819e0
     */
    bytes4 private constant _SIG_SAFE_MINT = 0x4c1819e0;

    /**
     * @dev bytes4(keccak256('safeMintSLD(address,uint256,string,bytes)')) == 0x58839d6b
     */
    bytes4 private constant _SIG_SAFE_MINT_DATA = 0x58839d6b;

    /**
     * @dev bytes4(keccak256('mintSLDWithRecords(address,uint256,string,string[],string[])')) == 0x39ccf4d0
     */
    bytes4 private constant _SIG_MINT_WITH_RECORDS = 0x39ccf4d0;

    /**
     * @dev bytes4(keccak256('safeMintSLDWithRecords(address,uint256,string,string[],string[])')) == 0x27bbd225
     */
    bytes4 private constant _SIG_SAFE_MINT_WITH_RECORDS = 0x27bbd225;

    /**
     * @dev bytes4(keccak256('safeMintSLDWithRecords(address,uint256,string,string[],string[],bytes)')) == 0x6a2d2256
     */
    bytes4 private constant _SIG_SAFE_MINT_WITH_RECORDS_DATA = 0x6a2d2256;

    modifier validTld(uint256 tld) {
        require(bytes(_tlds[tld]).length > 0, 'MintingManager: TLD_NOT_VALID');
        _;
    }

    function initialize(
        IRegistry unsRegistry,
        ICryptoSLDMinter cryptoMinter,
        ICryptoResolver cryptoResolver
    ) public initializer {
        UnsRegistry = unsRegistry;
        CryptoMinter = cryptoMinter;
        CryptoResolver = cryptoResolver;

        __Ownable_init_unchained();
        __MinterRole_init_unchained();

        // Relayer is required to be a minter
        _addMinter(address(this));

        _tlds[0x0f4a10a4f46c288cea365fcf45cccf0e9d901b945b9829ccdb54c10dc3cb7a6f] = 'crypto';
        _tlds[0x1e3f482b3363eb4710dae2cb2183128e272eafbe137f686851c1caea32502230] = 'wallet';
        _tlds[0x7674e7282552c15f203b9c4a6025aeaf28176ef7f5451b280f9bada3f8bc98e2] = 'coin';

        if(!UnsRegistry.exists(0x1e3f482b3363eb4710dae2cb2183128e272eafbe137f686851c1caea32502230)) {
            UnsRegistry.mint(address(0xdead), 0x1e3f482b3363eb4710dae2cb2183128e272eafbe137f686851c1caea32502230, 'wallet');
        }

        if(!UnsRegistry.exists(0x7674e7282552c15f203b9c4a6025aeaf28176ef7f5451b280f9bada3f8bc98e2)) {
            UnsRegistry.mint(address(0xdead), 0x7674e7282552c15f203b9c4a6025aeaf28176ef7f5451b280f9bada3f8bc98e2, 'coin');
        }
    }

    function mintSLD(address to, uint256 tld, string calldata label)
        external
        override
        onlyMinter
        validTld(tld)
    {
        _mintSLD(to, tld, label);
    }

    function safeMintSLD(address to, uint256 tld, string calldata label)
        external
        override
        onlyMinter
        validTld(tld)
    {
        _safeMintSLD(to, tld, label, '');
    }

    function safeMintSLD(
        address to,
        uint256 tld,
        string calldata label,
        bytes calldata _data
    ) external override onlyMinter validTld(tld) {
        _safeMintSLD(to, tld, label, _data);
    }

    function mintSLDWithRecords(
        address to,
        uint256 tld,
        string calldata label,
        string[] calldata keys,
        string[] calldata values
    ) external override onlyMinter validTld(tld) {
        _mintSLDWithRecords(to, tld, label, keys, values);
    }

    function safeMintSLDWithRecords(
        address to,
        uint256 tld,
        string calldata label,
        string[] calldata keys,
        string[] calldata values
    ) external override onlyMinter validTld(tld) {
        _safeMintSLDWithRecords(to, tld, label, keys, values, '');
    }

    function safeMintSLDWithRecords(
        address to,
        uint256 tld,
        string calldata label,
        string[] calldata keys,
        string[] calldata values,
        bytes calldata _data
    ) external override onlyMinter validTld(tld) {
        _safeMintSLDWithRecords(to, tld, label, keys, values, _data);
    }

    function claim(uint256 tld, string calldata label) external override validTld(tld) {
        _mintSLD(_msgSender(), tld, _freeSLDLabel(label));
    }

    function claimTo(address to, uint256 tld, string calldata label) external override validTld(tld) {
        _mintSLD(to, tld, _freeSLDLabel(label));
    }

    function claimToWithRecords(
        address to,
        uint256 tld,
        string calldata label,
        string[] calldata keys,
        string[] calldata values
    ) external override validTld(tld) {
        _mintSLDWithRecords(to, tld, _freeSLDLabel(label), keys, values);
    }

    function setResolver(address resolver) external onlyOwner {
        CryptoResolver = ICryptoResolver(resolver);
    }

    function _verifyRelaySigner(address signer) internal view override {
        super._verifyRelaySigner(signer);
        require(isMinter(signer), 'MintingManager: SIGNER_IS_NOT_MINTER');
    }

    function _verifyRelayCall(bytes4 funcSig, bytes calldata) internal pure override {
        bool isSupported = funcSig == _SIG_MINT ||
            funcSig == _SIG_SAFE_MINT ||
            funcSig == _SIG_SAFE_MINT_DATA ||
            funcSig == _SIG_MINT_WITH_RECORDS ||
            funcSig == _SIG_SAFE_MINT_WITH_RECORDS ||
            funcSig == _SIG_SAFE_MINT_WITH_RECORDS_DATA;

        require(isSupported, 'MintingManager: UNSUPPORTED_RELAY_CALL');
    }

    function _mintSLD(address to, uint256 tld, string memory label) private {
        if(tld == 0x0f4a10a4f46c288cea365fcf45cccf0e9d901b945b9829ccdb54c10dc3cb7a6f) {
            CryptoMinter.mintSLD(to, label);
        } else {
            UnsRegistry.mint(to, _childId(tld, label),  _uri(tld, label));
        }
    }

    function _safeMintSLD(
        address to,
        uint256 tld,
        string calldata label,
        bytes memory _data
    ) private {
        if(tld == 0x0f4a10a4f46c288cea365fcf45cccf0e9d901b945b9829ccdb54c10dc3cb7a6f) {
            CryptoMinter.safeMintSLD(to, label, _data);
        } else {
            UnsRegistry.safeMint(to, _childId(tld, label),  _uri(tld, label), _data);
        }
    }

    function _mintSLDWithRecords(
        address to,
        uint256 tld,
        string memory label,
        string[] calldata keys,
        string[] calldata values
    ) private {
        uint256 tokenId = _childId(tld, label);
        if(tld == 0x0f4a10a4f46c288cea365fcf45cccf0e9d901b945b9829ccdb54c10dc3cb7a6f) {
            CryptoMinter.mintSLDWithResolver(to, label, address(CryptoResolver));
            if(keys.length > 0) {
                CryptoResolver.preconfigure(keys, values, tokenId);
            }
        } else {
            UnsRegistry.mintWithRecords(to, tokenId, _uri(tld, label), keys, values);
        }
    }

    function _safeMintSLDWithRecords(
        address to,
        uint256 tld,
        string memory label,
        string[] calldata keys,
        string[] calldata values,
        bytes memory _data
    ) private {
        uint256 tokenId = _childId(tld, label);
        if(tld == 0x0f4a10a4f46c288cea365fcf45cccf0e9d901b945b9829ccdb54c10dc3cb7a6f) {
            CryptoMinter.safeMintSLDWithResolver(to, label, address(CryptoResolver), _data);
            if(keys.length > 0) {
                CryptoResolver.preconfigure(keys, values, tokenId);
            }
        } else {
            UnsRegistry.safeMintWithRecords(to, tokenId, _uri(tld, label), keys, values, _data);
        }
    }

    function _childId(uint256 tokenId, string memory label) internal pure returns (uint256) {
        require(bytes(label).length != 0, 'MintingManager: LABEL_EMPTY');
        return uint256(keccak256(abi.encodePacked(tokenId, keccak256(abi.encodePacked(label)))));
    }

    function _freeSLDLabel(string calldata label) private pure returns(string memory) {
        return string(abi.encodePacked('udtestdev-', label));
    }

    function  _uri(uint256 tld, string memory label) private view returns(string memory) {
        return string(abi.encodePacked(label, '.', _tlds[tld]));
    }

    // Reserved storage space to allow for layout changes in the future.
    uint256[50] private __gap;
}
