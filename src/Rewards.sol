// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.21;

import { AccessControl }     from "@openzeppelin/contracts/access/AccessControl.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { MerkleProof }       from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

// TODO: Ascii and rename

contract Rewards is AccessControl {

    using SafeERC20 for IERC20;

    /**********************************************************************************************/
    /*** Events                                                                                 ***/
    /**********************************************************************************************/

    event Claimed(address indexed account, uint256 amount);
    event EpochIsClosed(uint256 indexed epoch, bool isClosed);
    event MerkelRootUpdated(bytes32 oldMerkleRoot, bytes32 newMerkleRoot);
    event WalletUpdated(address indexed oldWallet, address indexed newWallet);

    /**********************************************************************************************/
    /*** State variables and constants                                                          ***/
    /**********************************************************************************************/

    bytes32 public constant EPOCH_ROLE       = keccak256("EPOCH_ROLE");
    bytes32 public constant MERKLE_ROOT_ROLE = keccak256("MERKLE_ROOT_ROLE");
    bytes32 public constant WALLET_ROLE      = keccak256("WALLET_ROLE");

    address public wallet;
    bytes32 public merkleRoot;

    // epoch => isClosed
    mapping(uint256 => bool) public epochClosed;

    // account => token => epoch => amount
    mapping(address => mapping(address => mapping(uint256 => uint256))) public cumulativeClaimed;

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**********************************************************************************************/
    /*** Configuration functions                                                                ***/
    /**********************************************************************************************/

    // TODO: setEscrow?
    function setWallet(address wallet_) public onlyRole(WALLET_ROLE) {
        wallet = wallet_;
        emit WalletUpdated(wallet, wallet_);
    }

    function setMerkleRoot(bytes32 merkleRoot_) external onlyRole(MERKLE_ROOT_ROLE) {
        merkleRoot = merkleRoot_;
        emit MerkelRootUpdated(merkleRoot, merkleRoot_);
    }

    function setEpochClosed(uint256 epoch, bool isClosed) public onlyRole(EPOCH_ROLE) {
        epochClosed[epoch] = isClosed;
        emit EpochIsClosed(epoch, isClosed);
    }

    /**********************************************************************************************/
    /*** User functions                                                                         ***/
    /**********************************************************************************************/

    function claim(
        uint256 epoch,
        address account,
        address token,
        uint256 cumulativeAmount,
        bytes32 expectedMerkleRoot,
        bytes32[] calldata merkleProof
    ) external {
        require(account == msg.sender,            "Rewards/invalid-account");
        require(merkleRoot == expectedMerkleRoot, "Rewards/merkle-root-was-updated");
        require(!epochClosed[epoch],              "Rewards/epoch-not-enabled");

        // Construct the leaf
        bytes32 leaf = keccak256(bytes.concat(
            keccak256(abi.encode(epoch, account, token, cumulativeAmount))
        ));

        // Verify the proof
        require(MerkleProof.verify(merkleProof, expectedMerkleRoot, leaf), "Rewards/invalid-proof");

        // Mark it claimed
        uint256 preClaimed = cumulativeClaimed[account][token][epoch];
        require(preClaimed < cumulativeAmount, "Rewards/nothing-to-claim");
        cumulativeClaimed[account][token][epoch] = cumulativeAmount;

        // Send the token
        uint256 amount = cumulativeAmount - preClaimed;
        IERC20(token).safeTransferFrom(wallet, account, amount);
        emit Claimed(account, amount);
    }
}
