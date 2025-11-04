// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {RockPaperScissors} from "../src/RockPaperScissors.sol";

/**
 * @title RockPaperScissorsE2E
 * @notice End-to-end tests simulating complete user journey from client perspective
 */
contract RockPaperScissorsE2E is Test {
    RockPaperScissors public rps;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant MIN_STAKE = 0.001 ether;

    function generateCommitment(
        RockPaperScissors.Move move,
        bytes32 salt,
        bytes32 nonce
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(move, salt, nonce));
    }

    function setUp() public {
        // Simulate contract deployment
        rps = new RockPaperScissors();

        // Fund users
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    /**
     * @notice E2E Test: Complete user journey from discovery to resolution
     * Simulates:
     * 1. Alice creates a game (visible via event)
     * 2. Bob discovers the game via event
     * 3. Bob joins the game
     * 4. Both players reveal
     * 5. Winner determined and funds distributed
     */
    function test_E2E_CompleteUserJourney_AliceWins() public {
        // === Phase 1: Alice creates game ===
        // Off-chain: Alice generates commitment
        bytes32 saltAlice = keccak256("alice_secret_salt");
        bytes32 nonceAlice = keccak256("alice_nonce");
        bytes32 moveHashAlice = generateCommitment(
            RockPaperScissors.Move.ROCK,
            saltAlice,
            nonceAlice
        );

        // Alice creates game on-chain
        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit RockPaperScissors.GameCreated(1, alice, MIN_STAKE);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHashAlice);

        // Off-chain: Bob queries events and finds Alice's game
        // (In real scenario, Bob would listen to GameCreated events)
        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(game.player1, alice);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.WAITING));

        // === Phase 2: Bob joins game ===
        // Off-chain: Bob generates commitment
        bytes32 saltBob = keccak256("bob_secret_salt");
        bytes32 nonceBob = keccak256("bob_nonce");
        bytes32 moveHashBob = generateCommitment(
            RockPaperScissors.Move.SCISSORS,
            saltBob,
            nonceBob
        );

        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;

        // Bob joins game
        vm.prank(bob);
        vm.expectEmit(true, false, false, false);
        emit RockPaperScissors.GameJoined(gameId, bob);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHashBob);

        // Verify game entered reveal phase
        game = rps.getGame(gameId);
        assertEq(game.player2, bob);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.REVEAL_PHASE));
        assertGt(game.revealDeadline, block.timestamp);

        // === Phase 3: Reveal phase ===
        // Both players reveal within deadline
        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit RockPaperScissors.GameRevealed(gameId, RockPaperScissors.Move.ROCK, RockPaperScissors.Move.SCISSORS);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, saltAlice, nonceAlice);

        vm.prank(bob);
        // Expect GameResolved on the second reveal which triggers resolution
        vm.expectEmit(true, false, false, false);
        emit RockPaperScissors.GameResolved(gameId, alice, RockPaperScissors.Move.ROCK, RockPaperScissors.Move.SCISSORS);
        rps.reveal(gameId, RockPaperScissors.Move.SCISSORS, saltBob, nonceBob);

        // === Phase 4: Game resolution ===
        // Verify game completed
        game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.COMPLETED));
        assertEq(uint256(game.reveals[0]), uint256(RockPaperScissors.Move.ROCK));
        assertEq(uint256(game.reveals[1]), uint256(RockPaperScissors.Move.SCISSORS));

        // Verify funds: Alice wins (rock beats scissors)
        assertEq(alice.balance, aliceBalanceBefore + MIN_STAKE * 2);
        assertEq(bob.balance, bobBalanceBefore - MIN_STAKE);

        // Event assertion was done immediately before Bob's reveal
    }

    /**
     * @notice E2E Test: Event-based game discovery
     * Simulates how players would discover games via events
     */
    function test_E2E_GameDiscoveryViaEvents() public {
        // Alice creates multiple games
        bytes32 salt1 = keccak256("salt1");
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 moveHash1 = generateCommitment(
            RockPaperScissors.Move.ROCK,
            salt1,
            nonce1
        );

        bytes32 salt2 = keccak256("salt2");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 moveHash2 = generateCommitment(
            RockPaperScissors.Move.PAPER,
            salt2,
            nonce2
        );

        vm.prank(alice);
        uint256 gameId1 = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(alice);
        uint256 gameId2 = rps.createGame{value: MIN_STAKE}(moveHash2);

        // Off-chain: Bob queries for available games
        // In real scenario: Query GameCreated events filtered by status == WAITING
        RockPaperScissors.Game memory game1 = rps.getGame(gameId1);
        RockPaperScissors.Game memory game2 = rps.getGame(gameId2);

        assertEq(uint256(game1.status), uint256(RockPaperScissors.GameStatus.WAITING));
        assertEq(uint256(game2.status), uint256(RockPaperScissors.GameStatus.WAITING));

        // Bob chooses to join game1
        bytes32 saltBob = keccak256("bob_salt");
        bytes32 nonceBob = keccak256("bob_nonce");
        bytes32 moveHashBob = generateCommitment(
            RockPaperScissors.Move.SCISSORS,
            saltBob,
            nonceBob
        );

        vm.prank(bob);
        rps.joinGame{value: MIN_STAKE}(gameId1, moveHashBob);

        // Verify game1 is no longer waiting, game2 still is
        game1 = rps.getGame(gameId1);
        game2 = rps.getGame(gameId2);

        assertEq(uint256(game1.status), uint256(RockPaperScissors.GameStatus.REVEAL_PHASE));
        assertEq(uint256(game2.status), uint256(RockPaperScissors.GameStatus.WAITING));
    }

    /**
     * @notice E2E Test: Tie resolution with rematch
     */
    function test_E2E_TieResolution_Rematch() public {
        // Create game and play to tie
        bytes32 saltAlice = keccak256("alice_salt");
        bytes32 nonceAlice = keccak256("alice_nonce");
        bytes32 moveHashAlice = generateCommitment(
            RockPaperScissors.Move.ROCK,
            saltAlice,
            nonceAlice
        );

        bytes32 saltBob = keccak256("bob_salt");
        bytes32 nonceBob = keccak256("bob_nonce");
        bytes32 moveHashBob = generateCommitment(
            RockPaperScissors.Move.ROCK,
            saltBob,
            nonceBob
        );

        vm.prank(alice);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHashAlice);

        vm.prank(bob);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHashBob);

        vm.prank(alice);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, saltAlice, nonceAlice);

        vm.prank(bob);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, saltBob, nonceBob);

        // Verify tie resolution phase
        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.TIE_RESOLUTION));

        // Both choose rematch
        vm.prank(alice);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.REMATCH);

        vm.prank(bob);
        vm.expectEmit(true, false, false, false);
        emit RockPaperScissors.TieHandled(gameId, RockPaperScissors.TieChoice.REMATCH, RockPaperScissors.TieChoice.REMATCH, true);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.REMATCH);

        // Verify game restarted
        game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.WAITING));
        assertEq(game.commitments[0], bytes32(0));
        assertEq(game.commitments[1], bytes32(0));
    }

    /**
     * @notice E2E Test: Cancel game when no one joins
     */
    function test_E2E_CancelGame_NoJoin() public {
        bytes32 saltAlice = keccak256("alice_salt");
        bytes32 nonceAlice = keccak256("alice_nonce");
        bytes32 moveHashAlice = generateCommitment(
            RockPaperScissors.Move.ROCK,
            saltAlice,
            nonceAlice
        );

        vm.prank(alice);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHashAlice);

        uint256 aliceBalanceBefore = alice.balance;

        // Simulate time passing with no one joining
        vm.warp(block.timestamp + 1 hours);

        // Alice cancels the game
        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit RockPaperScissors.GameCancelled(gameId);
        rps.cancelGame(gameId);

        // Verify refund
        assertEq(alice.balance, aliceBalanceBefore + MIN_STAKE);

        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.CANCELLED));
    }

    /**
     * @notice E2E Test: Timeout claim when only one player reveals
     */
    function test_E2E_TimeoutClaim_SingleRevealWins() public {
        // Alice commits ROCK
        bytes32 saltAlice = keccak256("alice_salt_timeout");
        bytes32 nonceAlice = keccak256("alice_nonce_timeout");
        bytes32 moveHashAlice = generateCommitment(
            RockPaperScissors.Move.ROCK,
            saltAlice,
            nonceAlice
        );

        // Bob commits PAPER
        bytes32 saltBob = keccak256("bob_salt_timeout");
        bytes32 nonceBob = keccak256("bob_nonce_timeout");
        bytes32 moveHashBob = generateCommitment(
            RockPaperScissors.Move.PAPER,
            saltBob,
            nonceBob
        );

        // Create + join
        vm.prank(alice);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHashAlice);

        vm.prank(bob);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHashBob);

        // Only Alice reveals
        vm.prank(alice);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, saltAlice, nonceAlice);

        uint256 aliceBefore = alice.balance;

        // Warp past deadline and claim
        vm.warp(block.timestamp + 2 minutes + 1);
        rps.claimAfterRevealTimeout(gameId);

        // Alice should receive full pot
        assertEq(alice.balance, aliceBefore + MIN_STAKE * 2);
        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.COMPLETED));
    }

    /**
     * @notice E2E Test: Timeout claim when Bob is the only revealer
     */
    function test_E2E_TimeoutClaim_SingleRevealWins_Bob() public {
        // Commitments
        bytes32 saltAlice = keccak256("alice_salt_timeout2");
        bytes32 nonceAlice = keccak256("alice_nonce_timeout2");
        bytes32 moveHashAlice = generateCommitment(
            RockPaperScissors.Move.ROCK,
            saltAlice,
            nonceAlice
        );

        bytes32 saltBob = keccak256("bob_salt_timeout2");
        bytes32 nonceBob = keccak256("bob_nonce_timeout2");
        bytes32 moveHashBob = generateCommitment(
            RockPaperScissors.Move.SCISSORS,
            saltBob,
            nonceBob
        );

        vm.prank(alice);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHashAlice);
        vm.prank(bob);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHashBob);

        // Only Bob reveals
        vm.prank(bob);
        rps.reveal(gameId, RockPaperScissors.Move.SCISSORS, saltBob, nonceBob);

        uint256 bobBefore = bob.balance;
        vm.warp(block.timestamp + 2 minutes + 1);
        rps.claimAfterRevealTimeout(gameId);
        assertEq(bob.balance, bobBefore + MIN_STAKE * 2);
    }

    /**
     * @notice E2E Test: Timeout claim when none revealed → split
     */
    function test_E2E_TimeoutClaim_NoneRevealed_Splits() public {
        bytes32 saltAlice = keccak256("alice_salt_timeout3");
        bytes32 nonceAlice = keccak256("alice_nonce_timeout3");
        bytes32 moveHashAlice = generateCommitment(
            RockPaperScissors.Move.ROCK,
            saltAlice,
            nonceAlice
        );

        bytes32 saltBob = keccak256("bob_salt_timeout3");
        bytes32 nonceBob = keccak256("bob_nonce_timeout3");
        bytes32 moveHashBob = generateCommitment(
            RockPaperScissors.Move.PAPER,
            saltBob,
            nonceBob
        );

        vm.prank(alice);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHashAlice);
        vm.prank(bob);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHashBob);

        uint256 aBefore = alice.balance;
        uint256 bBefore = bob.balance;
        vm.warp(block.timestamp + 2 minutes + 1);
        rps.claimAfterRevealTimeout(gameId);
        assertEq(alice.balance, aBefore + MIN_STAKE);
        assertEq(bob.balance, bBefore + MIN_STAKE);
    }
}

