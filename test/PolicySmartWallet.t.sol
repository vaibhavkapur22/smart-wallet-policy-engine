// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PolicySmartWallet.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Simple ERC20 for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 1_000_000e18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract PolicySmartWalletTest is Test {
    PolicySmartWallet public wallet;
    MockERC20 public token;

    uint256 internal ownerKey = 0xA11CE;
    uint256 internal guardianKey = 0xB0B;
    uint256 internal signerKey = 0xC0DE;
    uint256 internal randomKey = 0xDEAD;

    address internal ownerAddr;
    address internal guardianAddr;
    address internal signerAddr;
    address internal randomAddr;
    address internal recipient = address(0x1234);

    uint256 internal constant DELAY = 3600; // 1 hour

    function setUp() public {
        ownerAddr = vm.addr(ownerKey);
        guardianAddr = vm.addr(guardianKey);
        signerAddr = vm.addr(signerKey);
        randomAddr = vm.addr(randomKey);

        wallet = new PolicySmartWallet(ownerAddr, signerAddr, guardianAddr, DELAY);

        // Fund the wallet
        vm.deal(address(wallet), 100 ether);

        // Deploy and fund wallet with ERC20
        token = new MockERC20();
        token.mint(address(wallet), 1_000_000e18);
    }

    // ──────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────

    function _createOp(
        address target,
        uint256 value,
        bytes memory data,
        PolicySmartWallet.Decision decision
    ) internal view returns (PolicySmartWallet.Operation memory) {
        return PolicySmartWallet.Operation({
            target: target,
            value: value,
            data: data,
            nonce: wallet.nonce(),
            decision: decision,
            expiry: block.timestamp + 1 hours
        });
    }

    function _signOp(PolicySmartWallet.Operation memory op, uint256 privateKey) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                wallet.OPERATION_TYPEHASH(),
                op.target,
                op.value,
                keccak256(op.data),
                op.nonce,
                uint8(op.decision),
                op.expiry
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", wallet.getDomainSeparator(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // ──────────────────────────────────────────────
    //  Constructor tests
    // ──────────────────────────────────────────────

    function test_constructor_setsOwner() public view {
        assertEq(wallet.owner(), ownerAddr);
    }

    function test_constructor_setsTrustedSigner() public view {
        assertEq(wallet.trustedSigner(), signerAddr);
    }

    function test_constructor_setsGuardian() public view {
        assertTrue(wallet.isGuardian(guardianAddr));
    }

    function test_constructor_setsDelay() public view {
        assertEq(wallet.delayDuration(), DELAY);
    }

    function test_constructor_revertsZeroOwner() public {
        vm.expectRevert(PolicySmartWallet.ZeroAddress.selector);
        new PolicySmartWallet(address(0), signerAddr, guardianAddr, DELAY);
    }

    function test_constructor_revertsZeroSigner() public {
        vm.expectRevert(PolicySmartWallet.ZeroAddress.selector);
        new PolicySmartWallet(ownerAddr, address(0), guardianAddr, DELAY);
    }

    // ──────────────────────────────────────────────
    //  ALLOW path — immediate execution
    // ──────────────────────────────────────────────

    function test_execute_ALLOW_ethTransfer() public {
        uint256 balBefore = recipient.balance;

        PolicySmartWallet.Operation memory op = _createOp(
            recipient, 1 ether, "", PolicySmartWallet.Decision.ALLOW
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory attestSig = _signOp(op, signerKey);

        wallet.execute(op, ownerSig, attestSig);

        assertEq(recipient.balance, balBefore + 1 ether);
        assertEq(wallet.nonce(), 1);
    }

    function test_execute_ALLOW_erc20Transfer() public {
        bytes memory data = abi.encodeWithSelector(
            IERC20.transfer.selector, recipient, 100e18
        );
        PolicySmartWallet.Operation memory op = _createOp(
            address(token), 0, data, PolicySmartWallet.Decision.ALLOW
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory attestSig = _signOp(op, signerKey);

        wallet.execute(op, ownerSig, attestSig);

        assertEq(token.balanceOf(recipient), 100e18);
    }

    function test_execute_ALLOW_erc20Approve() public {
        bytes memory data = abi.encodeWithSelector(
            IERC20.approve.selector, recipient, 500e18
        );
        PolicySmartWallet.Operation memory op = _createOp(
            address(token), 0, data, PolicySmartWallet.Decision.ALLOW
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory attestSig = _signOp(op, signerKey);

        wallet.execute(op, ownerSig, attestSig);

        assertEq(token.allowance(address(wallet), recipient), 500e18);
    }

    // ──────────────────────────────────────────────
    //  DENY path
    // ──────────────────────────────────────────────

    function test_execute_DENY_reverts() public {
        PolicySmartWallet.Operation memory op = _createOp(
            recipient, 1 ether, "", PolicySmartWallet.Decision.DENY
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory attestSig = _signOp(op, signerKey);

        vm.expectRevert(PolicySmartWallet.TransactionDenied.selector);
        wallet.execute(op, ownerSig, attestSig);
    }

    // ──────────────────────────────────────────────
    //  REQUIRE_SECOND_SIGNATURE path
    // ──────────────────────────────────────────────

    function test_executeWithGuardian_success() public {
        PolicySmartWallet.Operation memory op = _createOp(
            recipient, 5 ether, "", PolicySmartWallet.Decision.REQUIRE_SECOND_SIGNATURE
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory guardianSig = _signOp(op, guardianKey);
        bytes memory attestSig = _signOp(op, signerKey);

        uint256 balBefore = recipient.balance;
        wallet.executeWithGuardian(op, ownerSig, guardianSig, attestSig);

        assertEq(recipient.balance, balBefore + 5 ether);
        assertEq(wallet.nonce(), 1);
    }

    function test_executeWithGuardian_invalidGuardian_reverts() public {
        PolicySmartWallet.Operation memory op = _createOp(
            recipient, 5 ether, "", PolicySmartWallet.Decision.REQUIRE_SECOND_SIGNATURE
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory fakeSig = _signOp(op, randomKey); // not a guardian
        bytes memory attestSig = _signOp(op, signerKey);

        vm.expectRevert(PolicySmartWallet.InvalidGuardianSignature.selector);
        wallet.executeWithGuardian(op, ownerSig, fakeSig, attestSig);
    }

    function test_executeWithGuardian_wrongDecision_reverts() public {
        PolicySmartWallet.Operation memory op = _createOp(
            recipient, 5 ether, "", PolicySmartWallet.Decision.ALLOW
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory guardianSig = _signOp(op, guardianKey);
        bytes memory attestSig = _signOp(op, signerKey);

        vm.expectRevert("Decision must be REQUIRE_SECOND_SIGNATURE");
        wallet.executeWithGuardian(op, ownerSig, guardianSig, attestSig);
    }

    // ──────────────────────────────────────────────
    //  REQUIRE_DELAY path — queue + execute + cancel
    // ──────────────────────────────────────────────

    function test_execute_REQUIRE_DELAY_queues() public {
        PolicySmartWallet.Operation memory op = _createOp(
            recipient, 10 ether, "", PolicySmartWallet.Decision.REQUIRE_DELAY
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory attestSig = _signOp(op, signerKey);

        wallet.execute(op, ownerSig, attestSig);

        // Nonce incremented, funds not transferred yet
        assertEq(wallet.nonce(), 1);
        assertEq(recipient.balance, 0);

        // Queue populated
        bytes32[] memory hashes = wallet.getQueuedOpHashes();
        assertEq(hashes.length, 1);
    }

    function test_executeQueued_afterDelay() public {
        PolicySmartWallet.Operation memory op = _createOp(
            recipient, 10 ether, "", PolicySmartWallet.Decision.REQUIRE_DELAY
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory attestSig = _signOp(op, signerKey);

        wallet.execute(op, ownerSig, attestSig);

        // Warp past delay
        vm.warp(block.timestamp + DELAY + 1);

        wallet.executeQueued(op);
        assertEq(recipient.balance, 10 ether);
    }

    function test_executeQueued_beforeDelay_reverts() public {
        PolicySmartWallet.Operation memory op = _createOp(
            recipient, 10 ether, "", PolicySmartWallet.Decision.REQUIRE_DELAY
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory attestSig = _signOp(op, signerKey);

        wallet.execute(op, ownerSig, attestSig);

        // Don't warp — try immediately
        vm.expectRevert(PolicySmartWallet.DelayNotElapsed.selector);
        wallet.executeQueued(op);
    }

    function test_cancelQueued_byOwner() public {
        PolicySmartWallet.Operation memory op = _createOp(
            recipient, 10 ether, "", PolicySmartWallet.Decision.REQUIRE_DELAY
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory attestSig = _signOp(op, signerKey);

        wallet.execute(op, ownerSig, attestSig);

        bytes32 opHash = wallet.hashOperation(op);

        vm.prank(ownerAddr);
        wallet.cancelQueued(opHash);

        PolicySmartWallet.QueuedOp memory qOp = wallet.getQueuedOperation(opHash);
        assertTrue(qOp.cancelled);
    }

    function test_cancelQueued_byGuardian() public {
        PolicySmartWallet.Operation memory op = _createOp(
            recipient, 10 ether, "", PolicySmartWallet.Decision.REQUIRE_DELAY
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory attestSig = _signOp(op, signerKey);

        wallet.execute(op, ownerSig, attestSig);

        bytes32 opHash = wallet.hashOperation(op);

        vm.prank(guardianAddr);
        wallet.cancelQueued(opHash);

        PolicySmartWallet.QueuedOp memory qOp = wallet.getQueuedOperation(opHash);
        assertTrue(qOp.cancelled);
    }

    function test_cancelQueued_byRandom_reverts() public {
        PolicySmartWallet.Operation memory op = _createOp(
            recipient, 10 ether, "", PolicySmartWallet.Decision.REQUIRE_DELAY
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory attestSig = _signOp(op, signerKey);

        wallet.execute(op, ownerSig, attestSig);

        bytes32 opHash = wallet.hashOperation(op);

        vm.prank(randomAddr);
        vm.expectRevert(PolicySmartWallet.OnlyOwnerOrGuardian.selector);
        wallet.cancelQueued(opHash);
    }

    function test_executeQueued_afterCancel_reverts() public {
        PolicySmartWallet.Operation memory op = _createOp(
            recipient, 10 ether, "", PolicySmartWallet.Decision.REQUIRE_DELAY
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory attestSig = _signOp(op, signerKey);

        wallet.execute(op, ownerSig, attestSig);

        bytes32 opHash = wallet.hashOperation(op);
        vm.prank(ownerAddr);
        wallet.cancelQueued(opHash);

        vm.warp(block.timestamp + DELAY + 1);
        vm.expectRevert(PolicySmartWallet.OperationAlreadyCancelled.selector);
        wallet.executeQueued(op);
    }

    function test_executeQueued_twice_reverts() public {
        PolicySmartWallet.Operation memory op = _createOp(
            recipient, 10 ether, "", PolicySmartWallet.Decision.REQUIRE_DELAY
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory attestSig = _signOp(op, signerKey);

        wallet.execute(op, ownerSig, attestSig);
        vm.warp(block.timestamp + DELAY + 1);
        wallet.executeQueued(op);

        vm.expectRevert(PolicySmartWallet.OperationAlreadyExecuted.selector);
        wallet.executeQueued(op);
    }

    // ──────────────────────────────────────────────
    //  Signature / attestation validation
    // ──────────────────────────────────────────────

    function test_execute_invalidOwnerSig_reverts() public {
        PolicySmartWallet.Operation memory op = _createOp(
            recipient, 1 ether, "", PolicySmartWallet.Decision.ALLOW
        );
        bytes memory fakeSig = _signOp(op, randomKey); // wrong key
        bytes memory attestSig = _signOp(op, signerKey);

        vm.expectRevert(PolicySmartWallet.InvalidAttestation.selector);
        wallet.execute(op, fakeSig, attestSig);
    }

    function test_execute_invalidAttestationSig_reverts() public {
        PolicySmartWallet.Operation memory op = _createOp(
            recipient, 1 ether, "", PolicySmartWallet.Decision.ALLOW
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory fakeSig = _signOp(op, randomKey); // wrong signer

        vm.expectRevert(PolicySmartWallet.InvalidAttestation.selector);
        wallet.execute(op, ownerSig, fakeSig);
    }

    function test_execute_expiredAttestation_reverts() public {
        PolicySmartWallet.Operation memory op = PolicySmartWallet.Operation({
            target: recipient,
            value: 1 ether,
            data: "",
            nonce: wallet.nonce(),
            decision: PolicySmartWallet.Decision.ALLOW,
            expiry: block.timestamp - 1 // already expired
        });
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory attestSig = _signOp(op, signerKey);

        vm.expectRevert(PolicySmartWallet.AttestationExpired.selector);
        wallet.execute(op, ownerSig, attestSig);
    }

    // ──────────────────────────────────────────────
    //  Replay / nonce protection
    // ──────────────────────────────────────────────

    function test_execute_replayAttack_reverts() public {
        PolicySmartWallet.Operation memory op = _createOp(
            recipient, 1 ether, "", PolicySmartWallet.Decision.ALLOW
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory attestSig = _signOp(op, signerKey);

        wallet.execute(op, ownerSig, attestSig);

        // Try to replay the same operation
        vm.expectRevert(PolicySmartWallet.InvalidNonce.selector);
        wallet.execute(op, ownerSig, attestSig);
    }

    function test_execute_wrongNonce_reverts() public {
        PolicySmartWallet.Operation memory op = PolicySmartWallet.Operation({
            target: recipient,
            value: 1 ether,
            data: "",
            nonce: 999, // wrong nonce
            decision: PolicySmartWallet.Decision.ALLOW,
            expiry: block.timestamp + 1 hours
        });
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory attestSig = _signOp(op, signerKey);

        vm.expectRevert(PolicySmartWallet.InvalidNonce.selector);
        wallet.execute(op, ownerSig, attestSig);
    }

    // ──────────────────────────────────────────────
    //  Guardian management
    // ──────────────────────────────────────────────

    function test_addGuardian() public {
        vm.prank(ownerAddr);
        wallet.addGuardian(randomAddr);
        assertTrue(wallet.isGuardian(randomAddr));
    }

    function test_removeGuardian() public {
        vm.prank(ownerAddr);
        wallet.removeGuardian(guardianAddr);
        assertFalse(wallet.isGuardian(guardianAddr));
    }

    function test_addGuardian_notOwner_reverts() public {
        vm.prank(randomAddr);
        vm.expectRevert(PolicySmartWallet.OnlyOwner.selector);
        wallet.addGuardian(randomAddr);
    }

    // ──────────────────────────────────────────────
    //  Admin functions
    // ──────────────────────────────────────────────

    function test_setTrustedSigner() public {
        vm.prank(ownerAddr);
        wallet.setTrustedSigner(randomAddr);
        assertEq(wallet.trustedSigner(), randomAddr);
    }

    function test_setDelayDuration() public {
        vm.prank(ownerAddr);
        wallet.setDelayDuration(7200);
        assertEq(wallet.delayDuration(), 7200);
    }

    function test_pause_unpause() public {
        vm.prank(ownerAddr);
        wallet.pause();
        assertTrue(wallet.paused());

        // Should revert when paused
        PolicySmartWallet.Operation memory op = _createOp(
            recipient, 1 ether, "", PolicySmartWallet.Decision.ALLOW
        );
        bytes memory ownerSig = _signOp(op, ownerKey);
        bytes memory attestSig = _signOp(op, signerKey);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        wallet.execute(op, ownerSig, attestSig);

        vm.prank(ownerAddr);
        wallet.unpause();
        assertFalse(wallet.paused());
    }

    function test_transferOwnership() public {
        vm.prank(ownerAddr);
        wallet.transferOwnership(randomAddr);
        assertEq(wallet.owner(), randomAddr);
    }

    function test_transferOwnership_notOwner_reverts() public {
        vm.prank(randomAddr);
        vm.expectRevert(PolicySmartWallet.OnlyOwner.selector);
        wallet.transferOwnership(randomAddr);
    }

    function test_allowlist_blocklist() public {
        vm.startPrank(ownerAddr);
        wallet.setAllowlistedTarget(recipient, true);
        assertTrue(wallet.allowlistedTargets(recipient));

        wallet.setBlocklistedTarget(recipient, true);
        assertTrue(wallet.blocklistedTargets(recipient));
        vm.stopPrank();
    }

    // ──────────────────────────────────────────────
    //  Receive ETH
    // ──────────────────────────────────────────────

    function test_receiveEth() public {
        uint256 balBefore = address(wallet).balance;
        vm.deal(address(this), 1 ether);
        (bool ok, ) = address(wallet).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(wallet).balance, balBefore + 1 ether);
    }
}
