// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title PolicySmartWallet
/// @notice A smart contract wallet with risk-based authorization enforcement.
///         Low-risk txs execute immediately, medium-risk require a guardian co-sign,
///         high-risk are delayed, and very risky txs are denied.
contract PolicySmartWallet is EIP712, Pausable, ReentrancyGuard {
    using ECDSA for bytes32;

    // ──────────────────────────────────────────────
    //  Types
    // ──────────────────────────────────────────────

    enum Decision {
        ALLOW,                    // 0 — execute immediately
        REQUIRE_SECOND_SIGNATURE, // 1 — guardian must co-sign
        REQUIRE_DELAY,            // 2 — queue with timelock
        DENY                      // 3 — revert
    }

    struct Operation {
        address target;
        uint256 value;
        bytes data;
        uint256 nonce;
        Decision decision;
        uint256 expiry;
    }

    struct QueuedOp {
        bytes32 opHash;
        uint256 executeAfter;
        bool executed;
        bool cancelled;
    }

    // ──────────────────────────────────────────────
    //  EIP-712 type hash
    // ──────────────────────────────────────────────

    bytes32 public constant OPERATION_TYPEHASH = keccak256(
        "Operation(address target,uint256 value,bytes32 dataHash,uint256 nonce,uint8 decision,uint256 expiry)"
    );

    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────

    address public owner;
    address public trustedSigner;  // backend risk/policy signer
    uint256 public nonce;
    uint256 public delayDuration;  // seconds to wait for REQUIRE_DELAY ops

    // Guardian management
    mapping(address => bool) public isGuardian;
    address[] public guardians;

    // Operation queue (for REQUIRE_DELAY)
    mapping(bytes32 => QueuedOp) public queue;
    bytes32[] public queuedOpHashes;

    // Allowlist / blocklist
    mapping(address => bool) public allowlistedTargets;
    mapping(address => bool) public blocklistedTargets;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event Executed(bytes32 indexed opHash, address indexed target, uint256 value);
    event OperationQueued(bytes32 indexed opHash, uint256 executeAfter);
    event OperationCancelled(bytes32 indexed opHash);
    event OperationExecutedFromQueue(bytes32 indexed opHash);
    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
    event TrustedSignerUpdated(address indexed newSigner);
    event DelayDurationUpdated(uint256 newDelay);
    event TargetAllowlisted(address indexed target, bool status);
    event TargetBlocklisted(address indexed target, bool status);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ──────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────

    error OnlyOwner();
    error OnlyOwnerOrGuardian();
    error InvalidAttestation();
    error AttestationExpired();
    error TransactionDenied();
    error InvalidGuardianSignature();
    error OperationNotQueued();
    error DelayNotElapsed();
    error OperationAlreadyExecuted();
    error OperationAlreadyCancelled();
    error ExecutionFailed();
    error InvalidNonce();
    error ZeroAddress();

    // ──────────────────────────────────────────────
    //  Modifiers
    // ──────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier onlyOwnerOrGuardian() {
        if (msg.sender != owner && !isGuardian[msg.sender]) revert OnlyOwnerOrGuardian();
        _;
    }

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    constructor(
        address _owner,
        address _trustedSigner,
        address _guardian,
        uint256 _delayDuration
    ) EIP712("PolicySmartWallet", "1") {
        if (_owner == address(0)) revert ZeroAddress();
        if (_trustedSigner == address(0)) revert ZeroAddress();

        owner = _owner;
        trustedSigner = _trustedSigner;
        delayDuration = _delayDuration;

        if (_guardian != address(0)) {
            isGuardian[_guardian] = true;
            guardians.push(_guardian);
            emit GuardianAdded(_guardian);
        }
    }

    // ──────────────────────────────────────────────
    //  Receive ETH
    // ──────────────────────────────────────────────

    receive() external payable {}

    // ──────────────────────────────────────────────
    //  Core execution
    // ──────────────────────────────────────────────

    /// @notice Execute a transaction with ALLOW decision (immediate execution).
    /// @param op The operation details.
    /// @param ownerSig Owner's EIP-712 signature over the operation.
    /// @param attestationSig Backend trusted signer's EIP-712 signature.
    function execute(
        Operation calldata op,
        bytes calldata ownerSig,
        bytes calldata attestationSig
    ) external whenNotPaused nonReentrant {
        _validateNonce(op.nonce);
        _validateExpiry(op.expiry);

        bytes32 opHash = _hashOperation(op);

        // Verify owner signature
        _verifySignature(opHash, ownerSig, owner);

        // Verify backend attestation
        _verifySignature(opHash, attestationSig, trustedSigner);

        if (op.decision == Decision.DENY) revert TransactionDenied();

        if (op.decision == Decision.ALLOW) {
            nonce++;
            _executeCall(op.target, op.value, op.data);
            emit Executed(opHash, op.target, op.value);
        } else if (op.decision == Decision.REQUIRE_SECOND_SIGNATURE) {
            // Guardian signature must be provided separately via executeWithGuardian
            revert("Use executeWithGuardian for REQUIRE_SECOND_SIGNATURE");
        } else if (op.decision == Decision.REQUIRE_DELAY) {
            // Queue the operation
            nonce++;
            uint256 executeAfter = block.timestamp + delayDuration;
            queue[opHash] = QueuedOp({
                opHash: opHash,
                executeAfter: executeAfter,
                executed: false,
                cancelled: false
            });
            queuedOpHashes.push(opHash);
            emit OperationQueued(opHash, executeAfter);
        }
    }

    /// @notice Execute a transaction that requires guardian co-signature.
    /// @param op The operation details (decision must be REQUIRE_SECOND_SIGNATURE).
    /// @param ownerSig Owner's EIP-712 signature.
    /// @param guardianSig Guardian's EIP-712 signature.
    /// @param attestationSig Backend trusted signer's EIP-712 signature.
    function executeWithGuardian(
        Operation calldata op,
        bytes calldata ownerSig,
        bytes calldata guardianSig,
        bytes calldata attestationSig
    ) external whenNotPaused nonReentrant {
        _validateNonce(op.nonce);
        _validateExpiry(op.expiry);

        bytes32 opHash = _hashOperation(op);

        // Verify owner signature
        _verifySignature(opHash, ownerSig, owner);

        // Verify backend attestation
        _verifySignature(opHash, attestationSig, trustedSigner);

        // Verify guardian signature
        address guardianAddr = _recoverSigner(opHash, guardianSig);
        if (!isGuardian[guardianAddr]) revert InvalidGuardianSignature();

        if (op.decision != Decision.REQUIRE_SECOND_SIGNATURE) {
            revert("Decision must be REQUIRE_SECOND_SIGNATURE");
        }

        nonce++;
        _executeCall(op.target, op.value, op.data);
        emit Executed(opHash, op.target, op.value);
    }

    /// @notice Execute a previously queued (delayed) operation after the delay has elapsed.
    /// @param op The original operation that was queued.
    function executeQueued(
        Operation calldata op
    ) external whenNotPaused nonReentrant {
        bytes32 opHash = _hashOperation(op);
        QueuedOp storage qOp = queue[opHash];

        if (qOp.opHash == bytes32(0)) revert OperationNotQueued();
        if (qOp.executed) revert OperationAlreadyExecuted();
        if (qOp.cancelled) revert OperationAlreadyCancelled();
        if (block.timestamp < qOp.executeAfter) revert DelayNotElapsed();

        qOp.executed = true;
        _executeCall(op.target, op.value, op.data);
        emit OperationExecutedFromQueue(opHash);
    }

    /// @notice Cancel a queued operation. Only owner or guardian can cancel.
    /// @param opHash The hash of the queued operation.
    function cancelQueued(bytes32 opHash) external onlyOwnerOrGuardian {
        QueuedOp storage qOp = queue[opHash];
        if (qOp.opHash == bytes32(0)) revert OperationNotQueued();
        if (qOp.executed) revert OperationAlreadyExecuted();
        if (qOp.cancelled) revert OperationAlreadyCancelled();

        qOp.cancelled = true;
        emit OperationCancelled(opHash);
    }

    // ──────────────────────────────────────────────
    //  Guardian management
    // ──────────────────────────────────────────────

    function addGuardian(address guardian) external onlyOwner {
        if (guardian == address(0)) revert ZeroAddress();
        if (!isGuardian[guardian]) {
            isGuardian[guardian] = true;
            guardians.push(guardian);
            emit GuardianAdded(guardian);
        }
    }

    function removeGuardian(address guardian) external onlyOwner {
        if (isGuardian[guardian]) {
            isGuardian[guardian] = false;
            // Remove from array
            for (uint256 i = 0; i < guardians.length; i++) {
                if (guardians[i] == guardian) {
                    guardians[i] = guardians[guardians.length - 1];
                    guardians.pop();
                    break;
                }
            }
            emit GuardianRemoved(guardian);
        }
    }

    function getGuardians() external view returns (address[] memory) {
        return guardians;
    }

    // ──────────────────────────────────────────────
    //  Admin functions
    // ──────────────────────────────────────────────

    function setTrustedSigner(address _trustedSigner) external onlyOwner {
        if (_trustedSigner == address(0)) revert ZeroAddress();
        trustedSigner = _trustedSigner;
        emit TrustedSignerUpdated(_trustedSigner);
    }

    function setDelayDuration(uint256 _delayDuration) external onlyOwner {
        delayDuration = _delayDuration;
        emit DelayDurationUpdated(_delayDuration);
    }

    function setAllowlistedTarget(address target, bool status) external onlyOwner {
        allowlistedTargets[target] = status;
        emit TargetAllowlisted(target, status);
    }

    function setBlocklistedTarget(address target, bool status) external onlyOwner {
        blocklistedTargets[target] = status;
        emit TargetBlocklisted(target, status);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ──────────────────────────────────────────────
    //  View helpers
    // ──────────────────────────────────────────────

    function getQueuedOperation(bytes32 opHash) external view returns (QueuedOp memory) {
        return queue[opHash];
    }

    function getQueuedOpHashes() external view returns (bytes32[] memory) {
        return queuedOpHashes;
    }

    function hashOperation(Operation calldata op) external view returns (bytes32) {
        return _hashOperation(op);
    }

    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ──────────────────────────────────────────────
    //  Internal helpers
    // ──────────────────────────────────────────────

    function _hashOperation(Operation calldata op) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    OPERATION_TYPEHASH,
                    op.target,
                    op.value,
                    keccak256(op.data),
                    op.nonce,
                    uint8(op.decision),
                    op.expiry
                )
            )
        );
    }

    function _verifySignature(bytes32 opHash, bytes calldata signature, address expected) internal pure {
        address recovered = ECDSA.recover(opHash, signature);
        if (recovered != expected) revert InvalidAttestation();
    }

    function _recoverSigner(bytes32 opHash, bytes calldata signature) internal pure returns (address) {
        return ECDSA.recover(opHash, signature);
    }

    function _validateNonce(uint256 opNonce) internal view {
        if (opNonce != nonce) revert InvalidNonce();
    }

    function _validateExpiry(uint256 expiry) internal view {
        if (block.timestamp > expiry) revert AttestationExpired();
    }

    function _executeCall(address target, uint256 value, bytes calldata data) internal {
        (bool success, ) = target.call{value: value}(data);
        if (!success) revert ExecutionFailed();
    }
}
