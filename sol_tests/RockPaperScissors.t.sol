// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {RockPaperScissors} from "../src/RockPaperScissors.sol";

contract RockPaperScissorsTest is Test {
    RockPaperScissors public rps;

    address public player1 = address(0x1);
    address public player2 = address(0x2);
    address public player3 = address(0x3);

    uint256 constant MIN_STAKE = 0.001 ether;

    // Helper function to generate commitment
    function generateCommitment(
        RockPaperScissors.Move move,
        bytes32 salt,
        bytes32 nonce
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(move, salt, nonce));
    }

    function setUp() public {
        rps = new RockPaperScissors();
    }

    // ============ createGame Tests ============

    function test_CreateGame_Success() public {
        vm.deal(player1, 1 ether);
        vm.prank(player1);

        bytes32 moveHash = generateCommitment(
            RockPaperScissors.Move.ROCK,
            keccak256("salt1"),
            keccak256("nonce1")
        );

        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash);

        assertEq(gameId, 1);
        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(game.player1, player1);
        assertEq(game.player2, address(0));
        assertEq(game.stake, MIN_STAKE);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.WAITING));
    }

    function test_CreateGame_Revert_InvalidStake_Underpay() public {
        vm.deal(player1, 1 ether);
        vm.prank(player1);

        bytes32 moveHash = generateCommitment(
            RockPaperScissors.Move.ROCK,
            keccak256("salt1"),
            keccak256("nonce1")
        );

        vm.expectRevert(abi.encodeWithSelector(RockPaperScissors.FixedStakeRequired.selector, MIN_STAKE));
        rps.createGame{value: 0.0005 ether}(moveHash);
    }

    function test_CreateGame_Revert_InvalidStake_Overpay() public {
        vm.deal(player1, 1 ether);
        vm.prank(player1);

        bytes32 moveHash = generateCommitment(
            RockPaperScissors.Move.ROCK,
            keccak256("salt1"),
            keccak256("nonce1")
        );

        vm.expectRevert(abi.encodeWithSelector(RockPaperScissors.FixedStakeRequired.selector, MIN_STAKE));
        rps.createGame{value: 0.002 ether}(moveHash);
    }

    function test_CreateGame_Event() public {
        vm.deal(player1, 1 ether);
        vm.prank(player1);

        bytes32 moveHash = generateCommitment(
            RockPaperScissors.Move.ROCK,
            keccak256("salt1"),
            keccak256("nonce1")
        );

        vm.expectEmit(true, false, false, false);
        emit RockPaperScissors.GameCreated(1, player1, MIN_STAKE);

        rps.createGame{value: MIN_STAKE}(moveHash);
    }

    // ============ joinGame Tests ============

    function test_JoinGame_Success() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        // Player1 creates game
        vm.prank(player1);
        bytes32 moveHash1 = generateCommitment(
            RockPaperScissors.Move.ROCK,
            keccak256("salt1"),
            keccak256("nonce1")
        );
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        // Player2 joins
        vm.prank(player2);
        bytes32 moveHash2 = generateCommitment(
            RockPaperScissors.Move.PAPER,
            keccak256("salt2"),
            keccak256("nonce2")
        );

        vm.expectEmit(true, false, false, false);
        emit RockPaperScissors.GameJoined(gameId, player2);

        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(game.player2, player2);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.REVEAL_PHASE));
        assertEq(game.revealDeadline, block.timestamp + 2 minutes);
    }

    function test_JoinGame_Revert_InvalidGameId() public {
        vm.deal(player2, 1 ether);
        vm.prank(player2);

        bytes32 moveHash = generateCommitment(
            RockPaperScissors.Move.PAPER,
            keccak256("salt2"),
            keccak256("nonce2")
        );

        vm.expectRevert(RockPaperScissors.InvalidGameId.selector);
        rps.joinGame{value: MIN_STAKE}(999, moveHash);
    }

    function test_JoinGame_Revert_GameNotInWaiting() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);
        vm.deal(player3, 1 ether);

        // Create and join game
        vm.prank(player1);
        bytes32 moveHash1 = generateCommitment(
            RockPaperScissors.Move.ROCK,
            keccak256("salt1"),
            keccak256("nonce1")
        );
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(player2);
        bytes32 moveHash2 = generateCommitment(
            RockPaperScissors.Move.PAPER,
            keccak256("salt2"),
            keccak256("nonce2")
        );
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        // Try to join again
        vm.prank(player3);
        bytes32 moveHash3 = generateCommitment(
            RockPaperScissors.Move.SCISSORS,
            keccak256("salt3"),
            keccak256("nonce3")
        );

        vm.expectRevert(RockPaperScissors.GameNotInWaitingStatus.selector);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash3);
    }

    function test_JoinGame_Revert_AlreadyJoined_BySamePlayer2() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        // Create
        vm.prank(player1);
        bytes32 moveHash1 = generateCommitment(
            RockPaperScissors.Move.ROCK,
            keccak256("salt1"),
            keccak256("nonce1")
        );
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        // Join once
        vm.prank(player2);
        bytes32 moveHash2 = generateCommitment(
            RockPaperScissors.Move.PAPER,
            keccak256("salt2"),
            keccak256("nonce2")
        );
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        // Try to join again as player2
        vm.prank(player2);
        vm.expectRevert(RockPaperScissors.GameNotInWaitingStatus.selector);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);
    }

    function test_JoinGame_Revert_SamePlayer() public {
        vm.deal(player1, 1 ether);

        vm.prank(player1);
        bytes32 moveHash1 = generateCommitment(
            RockPaperScissors.Move.ROCK,
            keccak256("salt1"),
            keccak256("nonce1")
        );
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(player1);
        bytes32 moveHash2 = generateCommitment(
            RockPaperScissors.Move.PAPER,
            keccak256("salt2"),
            keccak256("nonce2")
        );

        vm.expectRevert(RockPaperScissors.InvalidPlayer.selector);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);
    }

    function test_JoinGame_Revert_InvalidStake_Underpay() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        vm.prank(player1);
        bytes32 moveHash1 = generateCommitment(
            RockPaperScissors.Move.ROCK,
            keccak256("salt1"),
            keccak256("nonce1")
        );
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(player2);
        bytes32 moveHash2 = generateCommitment(
            RockPaperScissors.Move.PAPER,
            keccak256("salt2"),
            keccak256("nonce2")
        );

        vm.expectRevert(abi.encodeWithSelector(RockPaperScissors.FixedStakeRequired.selector, MIN_STAKE));
        rps.joinGame{value: 0.0005 ether}(gameId, moveHash2);
    }

    function test_JoinGame_Revert_InvalidStake_Overpay() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        vm.prank(player1);
        bytes32 moveHash1 = generateCommitment(
            RockPaperScissors.Move.ROCK,
            keccak256("salt1"),
            keccak256("nonce1")
        );
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(player2);
        bytes32 moveHash2 = generateCommitment(
            RockPaperScissors.Move.PAPER,
            keccak256("salt2"),
            keccak256("nonce2")
        );

        vm.expectRevert(abi.encodeWithSelector(RockPaperScissors.FixedStakeRequired.selector, MIN_STAKE));
        rps.joinGame{value: 0.002 ether}(gameId, moveHash2);
    }

    // ============ reveal Tests ============

    function test_Reveal_Success() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

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

        // Create game
        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        // Join game
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        // Reveal moves
        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);

        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.PAPER, salt2, nonce2);

        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.reveals[0]), uint256(RockPaperScissors.Move.ROCK));
        assertEq(uint256(game.reveals[1]), uint256(RockPaperScissors.Move.PAPER));
    }

    function test_Reveal_Revert_InvalidCommitment() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

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

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        // Try to reveal with wrong salt/nonce
        vm.prank(player1);
        vm.expectRevert(RockPaperScissors.InvalidCommitment.selector);
        rps.reveal(
            gameId,
            RockPaperScissors.Move.ROCK,
            keccak256("wrong_salt"),
            nonce1
        );
    }

    function test_Reveal_Revert_DifferentMove_SameSecrets() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

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

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        // Player1 tries to reveal with same salt/nonce but different move (PAPER instead of ROCK)
        vm.prank(player1);
        vm.expectRevert(RockPaperScissors.InvalidCommitment.selector);
        rps.reveal(gameId, RockPaperScissors.Move.PAPER, salt1, nonce1);
    }

    function test_Reveal_Revert_SameMove_DifferentSecrets() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

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

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        // Player1 tries to reveal ROCK with different salt/nonce
        vm.prank(player1);
        vm.expectRevert(RockPaperScissors.InvalidCommitment.selector);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, keccak256("salt1_wrong"), nonce1);
    }

    function test_Reveal_Revert_DoubleReveal_SamePlayer() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

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

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);

        // Try to reveal again
        vm.prank(player1);
        vm.expectRevert(RockPaperScissors.MoveAlreadyRevealed.selector);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);
    }

    function test_Reveal_Revert_DeadlinePassed() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

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

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        // Warp past deadline
        vm.warp(block.timestamp + 2 minutes + 1 seconds);

        vm.prank(player1);
        vm.expectRevert(RockPaperScissors.RevealDeadlinePassed.selector);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);
    }

    function test_Reveal_Revert_InvalidPlayer() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);
        vm.deal(player3, 1 ether);

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

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        // Player3 tries to reveal
        vm.prank(player3);
        vm.expectRevert(RockPaperScissors.InvalidPlayer.selector);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, keccak256("salt3"), keccak256("nonce3"));
    }

    // ===== Reveal timeout handling =====

    function test_RevealTimeout_OnlyPlayer1Revealed_WinsPot() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("salt1");
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 moveHash1 = generateCommitment(RockPaperScissors.Move.ROCK, salt1, nonce1);
        bytes32 salt2 = keccak256("salt2");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 moveHash2 = generateCommitment(RockPaperScissors.Move.PAPER, salt2, nonce2);

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        // Only player1 reveals
        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);

        uint256 b1 = player1.balance;

        // After deadline, anyone can call timeout claim
        vm.warp(block.timestamp + 2 minutes + 1);
        rps.claimAfterRevealTimeout(gameId);

        assertEq(player1.balance, b1 + MIN_STAKE * 2);
        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.COMPLETED));
    }

    function test_RevealTimeout_OnlyPlayer2Revealed_WinsPot() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("salt1");
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 moveHash1 = generateCommitment(RockPaperScissors.Move.ROCK, salt1, nonce1);
        bytes32 salt2 = keccak256("salt2");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 moveHash2 = generateCommitment(RockPaperScissors.Move.PAPER, salt2, nonce2);

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        // Only player2 reveals
        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.PAPER, salt2, nonce2);

        uint256 b2 = player2.balance;

        vm.warp(block.timestamp + 2 minutes + 1);
        rps.claimAfterRevealTimeout(gameId);

        assertEq(player2.balance, b2 + MIN_STAKE * 2);
    }

    function test_RevealTimeout_NoneRevealed_Splits() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("salt1");
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 moveHash1 = generateCommitment(RockPaperScissors.Move.ROCK, salt1, nonce1);
        bytes32 salt2 = keccak256("salt2");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 moveHash2 = generateCommitment(RockPaperScissors.Move.PAPER, salt2, nonce2);

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        uint256 b1 = player1.balance;
        uint256 b2 = player2.balance;

        vm.warp(block.timestamp + 2 minutes + 1);
        rps.claimAfterRevealTimeout(gameId);

        assertEq(player1.balance, b1 + MIN_STAKE);
        assertEq(player2.balance, b2 + MIN_STAKE);
    }

    function test_RevealTimeout_BeforeDeadline_Reverts() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("salt1");
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 moveHash1 = generateCommitment(RockPaperScissors.Move.ROCK, salt1, nonce1);
        bytes32 salt2 = keccak256("salt2");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 moveHash2 = generateCommitment(RockPaperScissors.Move.PAPER, salt2, nonce2);

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        vm.expectRevert(RockPaperScissors.RevealDeadlinePassed.selector);
        rps.claimAfterRevealTimeout(gameId);
    }

    function test_RevealTimeout_DoubleClaim_Reverts() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("salt1");
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 moveHash1 = generateCommitment(RockPaperScissors.Move.ROCK, salt1, nonce1);
        bytes32 salt2 = keccak256("salt2");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 moveHash2 = generateCommitment(RockPaperScissors.Move.PAPER, salt2, nonce2);

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        // Only player1 reveals
        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);

        vm.warp(block.timestamp + 2 minutes + 1);
        rps.claimAfterRevealTimeout(gameId);

        // Second call should revert (not in reveal phase anymore)
        vm.expectRevert(RockPaperScissors.GameNotInRevealPhase.selector);
        rps.claimAfterRevealTimeout(gameId);
    }

    // ============ Win Logic Tests ============

    function test_DetermineWinner_RockBeatsScissors() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

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
            RockPaperScissors.Move.SCISSORS,
            salt2,
            nonce2
        );

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        // Reveal
        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);

        uint256 balanceBefore = player1.balance;

        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.SCISSORS, salt2, nonce2);

        // Player1 should win (rock beats scissors)
        assertEq(player1.balance, balanceBefore + MIN_STAKE * 2);
        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.COMPLETED));
    }

    function test_DetermineWinner_PaperBeatsRock() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

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

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);

        uint256 balanceBefore = player2.balance;

        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.PAPER, salt2, nonce2);

        // Player2 should win (paper beats rock)
        assertEq(player2.balance, balanceBefore + MIN_STAKE * 2);
    }

    function test_DetermineWinner_ScissorsBeatsPaper() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("salt1");
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 moveHash1 = generateCommitment(
            RockPaperScissors.Move.PAPER,
            salt1,
            nonce1
        );

        bytes32 salt2 = keccak256("salt2");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 moveHash2 = generateCommitment(
            RockPaperScissors.Move.SCISSORS,
            salt2,
            nonce2
        );

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.PAPER, salt1, nonce1);

        uint256 balanceBefore = player2.balance;

        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.SCISSORS, salt2, nonce2);

        // Player2 should win (scissors beats paper)
        assertEq(player2.balance, balanceBefore + MIN_STAKE * 2);
    }

    function test_DetermineWinner_Tie() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

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
            RockPaperScissors.Move.ROCK,
            salt2,
            nonce2
        );

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);

        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt2, nonce2);

        // Should enter tie resolution
        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.TIE_RESOLUTION));
        assertEq(game.tieResolutionDeadline, block.timestamp + 2 minutes);
    }

    function test_DetermineWinner_Tie_ScissorsVsScissors() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("salt1");
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 moveHash1 = generateCommitment(
            RockPaperScissors.Move.SCISSORS,
            salt1,
            nonce1
        );

        bytes32 salt2 = keccak256("salt2");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 moveHash2 = generateCommitment(
            RockPaperScissors.Move.SCISSORS,
            salt2,
            nonce2
        );

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.SCISSORS, salt1, nonce1);
        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.SCISSORS, salt2, nonce2);

        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.TIE_RESOLUTION));
        assertEq(game.tieResolutionDeadline, block.timestamp + 2 minutes);
    }

    // ============ cancelGame Tests ============

    function test_CancelGame_Success() public {
        vm.deal(player1, 1 ether);

        vm.prank(player1);
        bytes32 moveHash1 = generateCommitment(
            RockPaperScissors.Move.ROCK,
            keccak256("salt1"),
            keccak256("nonce1")
        );
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        uint256 balanceBefore = player1.balance;

        vm.prank(player1);
        vm.expectEmit(true, false, false, false);
        emit RockPaperScissors.GameCancelled(gameId);

        rps.cancelGame(gameId);

        assertEq(player1.balance, balanceBefore + MIN_STAKE);
        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.CANCELLED));
    }

    function test_CancelGame_Revert_OnlyPlayer1() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        vm.prank(player1);
        bytes32 moveHash1 = generateCommitment(
            RockPaperScissors.Move.ROCK,
            keccak256("salt1"),
            keccak256("nonce1")
        );
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(player2);
        vm.expectRevert(RockPaperScissors.OnlyPlayer1CanCancel.selector);
        rps.cancelGame(gameId);
    }

    function test_CancelGame_Revert_GameNotWaiting() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

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

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        vm.prank(player1);
        vm.expectRevert(RockPaperScissors.GameNotInWaitingStatus.selector);
        rps.cancelGame(gameId);
    }

    // ============ handleTie Tests ============

    function test_HandleTie_Rematch() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

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
            RockPaperScissors.Move.ROCK,
            salt2,
            nonce2
        );

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);

        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt2, nonce2);

        // Both choose rematch
        vm.prank(player1);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.REMATCH);

        vm.prank(player2);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.REMATCH);

        // Game should restart
        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.WAITING));
        assertEq(game.commitments[0], bytes32(0));
        assertEq(game.commitments[1], bytes32(0));
    }

    function test_HandleTie_Split() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

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
            RockPaperScissors.Move.ROCK,
            salt2,
            nonce2
        );

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);

        uint256 balance1Before = player1.balance;
        uint256 balance2Before = player2.balance;

        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt2, nonce2);

        // Both choose split
        vm.prank(player1);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.SPLIT);

        vm.prank(player2);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.SPLIT);

        // Funds should be split
        assertEq(player1.balance, balance1Before + MIN_STAKE);
        assertEq(player2.balance, balance2Before + MIN_STAKE);

        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.COMPLETED));
    }

    function test_HandleTie_MixedChoices_Splits() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

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
            RockPaperScissors.Move.ROCK,
            salt2,
            nonce2
        );

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);

        uint256 balance1Before = player1.balance;
        uint256 balance2Before = player2.balance;

        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt2, nonce2);

        // Mixed choices: one wants rematch, one wants split
        vm.prank(player1);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.REMATCH);

        vm.prank(player2);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.SPLIT);

        // Should split (not both want rematch)
        assertEq(player1.balance, balance1Before + MIN_STAKE);
        assertEq(player2.balance, balance2Before + MIN_STAKE);
    }

    function test_HandleTie_Timeout_Splits() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

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
            RockPaperScissors.Move.ROCK,
            salt2,
            nonce2
        );

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);

        uint256 balance1Before = player1.balance;
        uint256 balance2Before = player2.balance;

        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt2, nonce2);

        // Warp past deadline
        vm.warp(block.timestamp + 2 minutes + 1 seconds);

        // Any call after deadline should split
        vm.prank(player1);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.SPLIT);

        assertEq(player1.balance, balance1Before + MIN_STAKE);
        assertEq(player2.balance, balance2Before + MIN_STAKE);
    }

    function test_HandleTie_TimeoutVsTimeout_Splits_OnFirstCall() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("salt1");
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 moveHash1 = generateCommitment(RockPaperScissors.Move.ROCK, salt1, nonce1);
        bytes32 salt2 = keccak256("salt2");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 moveHash2 = generateCommitment(RockPaperScissors.Move.ROCK, salt2, nonce2);

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);
        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);
        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt2, nonce2);

        uint256 b1 = player1.balance;
        uint256 b2 = player2.balance;

        vm.warp(block.timestamp + 2 minutes + 1);

        // First call after timeout splits
        vm.prank(player1);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.REMATCH);
        assertEq(player1.balance, b1 + MIN_STAKE);
        assertEq(player2.balance, b2 + MIN_STAKE);
    }

    function test_HandleTie_TimeoutVsOtherChoice_Splits() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("salt1");
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 moveHash1 = generateCommitment(RockPaperScissors.Move.ROCK, salt1, nonce1);
        bytes32 salt2 = keccak256("salt2");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 moveHash2 = generateCommitment(RockPaperScissors.Move.ROCK, salt2, nonce2);

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);
        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);
        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt2, nonce2);

        uint256 b1 = player1.balance;
        uint256 b2 = player2.balance;

        // Player1 picks REMATCH before timeout; player2 times out, then calls any choice
        vm.prank(player1);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.REMATCH);

        vm.warp(block.timestamp + 2 minutes + 1);
        vm.prank(player2);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.REMATCH);

        assertEq(player1.balance, b1 + MIN_STAKE);
        assertEq(player2.balance, b2 + MIN_STAKE);
    }

    // ============ Additional Tie Resolution Tests ============

    function test_HandleTie_NobodyCallsAfterExpiration_FundsStayLocked() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("salt1");
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 moveHash1 = generateCommitment(RockPaperScissors.Move.ROCK, salt1, nonce1);
        bytes32 salt2 = keccak256("salt2");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 moveHash2 = generateCommitment(RockPaperScissors.Move.ROCK, salt2, nonce2);

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);
        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);
        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt2, nonce2);

        uint256 expectedLocked = MIN_STAKE * 2; // Both stakes

        // Warp past tie resolution deadline
        vm.warp(block.timestamp + 2 minutes + 1);

        // Nobody calls handleTie - funds should remain locked
        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.TIE_RESOLUTION));
        assertEq(address(rps).balance, expectedLocked); // Contract should still hold both stakes
        
        // Verify players didn't receive funds
        assertEq(player1.balance, 1 ether - MIN_STAKE);
        assertEq(player2.balance, 1 ether - MIN_STAKE);
    }

    function test_HandleTie_Player1CallsAfterExpiration_AutoSplits() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("salt1");
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 moveHash1 = generateCommitment(RockPaperScissors.Move.ROCK, salt1, nonce1);
        bytes32 salt2 = keccak256("salt2");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 moveHash2 = generateCommitment(RockPaperScissors.Move.ROCK, salt2, nonce2);

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);
        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);
        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt2, nonce2);

        uint256 balance1Before = player1.balance;
        uint256 balance2Before = player2.balance;

        // Warp past tie resolution deadline
        vm.warp(block.timestamp + 2 minutes + 1);

        // Player 1 calls handleTie after expiration - should auto-split regardless of choice
        vm.prank(player1);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.REMATCH); // Choice doesn't matter after timeout

        // Both players should receive their stake back
        assertEq(player1.balance, balance1Before + MIN_STAKE);
        assertEq(player2.balance, balance2Before + MIN_STAKE);
        
        // Contract should have no funds left
        assertEq(address(rps).balance, 0);
        
        // Game status should be COMPLETED
        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.COMPLETED));
    }

    function test_HandleTie_Player2CallsAfterExpiration_AutoSplits() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("salt1");
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 moveHash1 = generateCommitment(RockPaperScissors.Move.ROCK, salt1, nonce1);
        bytes32 salt2 = keccak256("salt2");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 moveHash2 = generateCommitment(RockPaperScissors.Move.ROCK, salt2, nonce2);

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);
        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);
        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt2, nonce2);

        uint256 balance1Before = player1.balance;
        uint256 balance2Before = player2.balance;

        // Warp past tie resolution deadline
        vm.warp(block.timestamp + 2 minutes + 1);

        // Player 2 calls handleTie after expiration - should auto-split
        vm.prank(player2);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.SPLIT); // Choice doesn't matter after timeout

        // Both players should receive their stake back
        assertEq(player1.balance, balance1Before + MIN_STAKE);
        assertEq(player2.balance, balance2Before + MIN_STAKE);
        
        // Contract should have no funds left
        assertEq(address(rps).balance, 0);
    }

    function test_HandleTie_SamePlayerCallsTwiceDuringPeriod_UpdatesChoice() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("salt1");
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 moveHash1 = generateCommitment(RockPaperScissors.Move.ROCK, salt1, nonce1);
        bytes32 salt2 = keccak256("salt2");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 moveHash2 = generateCommitment(RockPaperScissors.Move.ROCK, salt2, nonce2);

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);
        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);
        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt2, nonce2);

        // Player 1 calls handleTie first with REMATCH
        vm.prank(player1);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.REMATCH);

        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.tieChoices[0]), uint256(RockPaperScissors.TieChoice.REMATCH));

        // Player 1 calls handleTie again with SPLIT - should update their choice
        vm.prank(player1);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.SPLIT);

        game = rps.getGame(gameId);
        assertEq(uint256(game.tieChoices[0]), uint256(RockPaperScissors.TieChoice.SPLIT));
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.TIE_RESOLUTION));
        
        // Player 2 calls with REMATCH - should split (different choices)
        vm.prank(player2);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.REMATCH);

        // Should have split funds
        assertEq(player1.balance, 1 ether - MIN_STAKE + MIN_STAKE); // Got stake back
        assertEq(player2.balance, 1 ether - MIN_STAKE + MIN_STAKE); // Got stake back
    }

    function test_HandleTie_CalledAfterAlreadyHandled_Reverts() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("salt1");
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 moveHash1 = generateCommitment(RockPaperScissors.Move.ROCK, salt1, nonce1);
        bytes32 salt2 = keccak256("salt2");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 moveHash2 = generateCommitment(RockPaperScissors.Move.ROCK, salt2, nonce2);

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);
        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);
        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt2, nonce2);

        // Both players call handleTie to split
        vm.prank(player1);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.SPLIT);
        vm.prank(player2);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.SPLIT);

        // Game should be COMPLETED now
        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.COMPLETED));

        // Try to call handleTie again - should revert
        vm.prank(player1);
        vm.expectRevert(RockPaperScissors.GameNotInTieResolution.selector);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.SPLIT);
    }

}

