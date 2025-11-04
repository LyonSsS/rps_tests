// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {RockPaperScissors} from "../src/RockPaperScissors.sol";

contract RockPaperScissorsIntegrationTest is Test {
    RockPaperScissors public rps;

    address public player1 = address(0x1);
    address public player2 = address(0x2);

    uint256 constant MIN_STAKE = 0.001 ether;

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

    // ============ Happy Path Tests ============

    function test_FullGameFlow_Player1Wins() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        // Player 1 creates game
        bytes32 salt1 = keccak256("salt1");
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 moveHash1 = generateCommitment(
            RockPaperScissors.Move.ROCK,
            salt1,
            nonce1
        );

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        // Verify game created
        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(game.player1, player1);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.WAITING));

        // Player 2 joins game
        bytes32 salt2 = keccak256("salt2");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 moveHash2 = generateCommitment(
            RockPaperScissors.Move.SCISSORS,
            salt2,
            nonce2
        );

        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        // Verify game in reveal phase
        game = rps.getGame(gameId);
        assertEq(game.player2, player2);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.REVEAL_PHASE));
        assertEq(game.revealDeadline, block.timestamp + 2 minutes);

        // Both players reveal
        uint256 balance1Before = player1.balance;

        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);

        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.SCISSORS, salt2, nonce2);

        // Verify game completed and player1 won (rock beats scissors)
        game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.COMPLETED));
        assertEq(player1.balance, balance1Before + MIN_STAKE * 2);
        assertEq(uint256(game.reveals[0]), uint256(RockPaperScissors.Move.ROCK));
        assertEq(uint256(game.reveals[1]), uint256(RockPaperScissors.Move.SCISSORS));
    }

    function test_FullGameFlow_Player2Wins() public {
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

        uint256 balance2Before = player2.balance;

        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);

        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.PAPER, salt2, nonce2);

        // Player2 wins (paper beats rock)
        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.COMPLETED));
        assertEq(player2.balance, balance2Before + MIN_STAKE * 2);
    }

    function test_FullGameFlow_Tie_Rematch() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        // First game - tie
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

        // Enter tie resolution
        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.TIE_RESOLUTION));

        // Both choose rematch
        vm.prank(player1);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.REMATCH);

        vm.prank(player2);
        rps.handleTie(gameId, RockPaperScissors.TieChoice.REMATCH);

        // Game restarts
        game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.WAITING));

        // Play rematch - new commitments
        bytes32 salt1Rematch = keccak256("salt1_rematch");
        bytes32 nonce1Rematch = keccak256("nonce1_rematch");
        bytes32 moveHash1Rematch = generateCommitment(
            RockPaperScissors.Move.PAPER,
            salt1Rematch,
            nonce1Rematch
        );

        bytes32 salt2Rematch = keccak256("salt2_rematch");
        bytes32 nonce2Rematch = keccak256("nonce2_rematch");
        bytes32 moveHash2Rematch = generateCommitment(
            RockPaperScissors.Move.SCISSORS,
            salt2Rematch,
            nonce2Rematch
        );

        // Note: In rematch, players would need to create new commitments
        // But the contract expects them to commit again, so we'd need a different approach
        // For now, we verify the game is back in WAITING state

        // Actually, the rematch should allow players to create new commitments
        // But since createGame creates a new gameId, we'd need to modify the contract
        // or have a different rematch flow. For this test, we verify the game state is reset
        assertEq(game.commitments[0], bytes32(0));
        assertEq(game.commitments[1], bytes32(0));
    }

    function test_FullGameFlow_Tie_Split() public {
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

        // Funds split
        assertEq(player1.balance, balance1Before + MIN_STAKE);
        assertEq(player2.balance, balance2Before + MIN_STAKE);

        RockPaperScissors.Game memory game = rps.getGame(gameId);
        assertEq(uint256(game.status), uint256(RockPaperScissors.GameStatus.COMPLETED));
    }

    // ============ Failure Cases ============

    function test_EdgeCase_RevealAfterDeadline_Reverts() public {
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

        // Try to reveal after deadline
        vm.prank(player1);
        vm.expectRevert(RockPaperScissors.RevealDeadlinePassed.selector);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);
    }

    function test_EdgeCase_InvalidCommitment_Reverts() public {
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

        // Try to reveal with wrong move
        vm.prank(player1);
        vm.expectRevert(RockPaperScissors.InvalidCommitment.selector);
        rps.reveal(gameId, RockPaperScissors.Move.PAPER, salt1, nonce1); // Wrong move
    }

    function test_EdgeCase_DoubleReveal_Reverts() public {
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

    // ============ Reveal Timeout Integration Paths ============

    function test_TimeoutClaim_OnlyPlayer1Revealed_WinsPot() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("t_salt1");
        bytes32 nonce1 = keccak256("t_nonce1");
        bytes32 moveHash1 = generateCommitment(RockPaperScissors.Move.ROCK, salt1, nonce1);
        bytes32 salt2 = keccak256("t_salt2");
        bytes32 nonce2 = keccak256("t_nonce2");
        bytes32 moveHash2 = generateCommitment(RockPaperScissors.Move.PAPER, salt2, nonce2);

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        vm.prank(player1);
        rps.reveal(gameId, RockPaperScissors.Move.ROCK, salt1, nonce1);

        uint256 b1 = player1.balance;
        vm.warp(block.timestamp + 2 minutes + 1);
        rps.claimAfterRevealTimeout(gameId);
        assertEq(player1.balance, b1 + MIN_STAKE * 2);
    }

    function test_TimeoutClaim_OnlyPlayer2Revealed_WinsPot() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("t2_salt1");
        bytes32 nonce1 = keccak256("t2_nonce1");
        bytes32 moveHash1 = generateCommitment(RockPaperScissors.Move.ROCK, salt1, nonce1);
        bytes32 salt2 = keccak256("t2_salt2");
        bytes32 nonce2 = keccak256("t2_nonce2");
        bytes32 moveHash2 = generateCommitment(RockPaperScissors.Move.PAPER, salt2, nonce2);

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);
        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        vm.prank(player2);
        rps.reveal(gameId, RockPaperScissors.Move.PAPER, salt2, nonce2);

        uint256 b2 = player2.balance;
        vm.warp(block.timestamp + 2 minutes + 1);
        rps.claimAfterRevealTimeout(gameId);
        assertEq(player2.balance, b2 + MIN_STAKE * 2);
    }

    function test_TimeoutClaim_NoneRevealed_Splits() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("t3_salt1");
        bytes32 nonce1 = keccak256("t3_nonce1");
        bytes32 moveHash1 = generateCommitment(RockPaperScissors.Move.ROCK, salt1, nonce1);
        bytes32 salt2 = keccak256("t3_salt2");
        bytes32 nonce2 = keccak256("t3_nonce2");
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

    function test_EdgeCase_CancelGame_AfterJoin() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        bytes32 salt1 = keccak256("salt1");
        bytes32 nonce1 = keccak256("nonce1");
        bytes32 moveHash1 = generateCommitment(
            RockPaperScissors.Move.ROCK,
            salt1,
            nonce1
        );

        vm.prank(player1);
        uint256 gameId = rps.createGame{value: MIN_STAKE}(moveHash1);

        bytes32 salt2 = keccak256("salt2");
        bytes32 nonce2 = keccak256("nonce2");
        bytes32 moveHash2 = generateCommitment(
            RockPaperScissors.Move.PAPER,
            salt2,
            nonce2
        );

        vm.prank(player2);
        rps.joinGame{value: MIN_STAKE}(gameId, moveHash2);

        // Try to cancel after join (should revert)
        vm.prank(player1);
        vm.expectRevert(RockPaperScissors.GameNotInWaitingStatus.selector);
        rps.cancelGame(gameId);
    }

    function test_EdgeCase_MultipleGames_Simultaneously() public {
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        // Create multiple games
        bytes32 salt1 = keccak256("salt1_game1");
        bytes32 nonce1 = keccak256("nonce1_game1");
        bytes32 moveHash1 = generateCommitment(
            RockPaperScissors.Move.ROCK,
            salt1,
            nonce1
        );

        vm.prank(player1);
        uint256 gameId1 = rps.createGame{value: MIN_STAKE}(moveHash1);

        bytes32 salt2 = keccak256("salt1_game2");
        bytes32 nonce2 = keccak256("nonce1_game2");
        bytes32 moveHash2 = generateCommitment(
            RockPaperScissors.Move.PAPER,
            salt2,
            nonce2
        );

        vm.prank(player1);
        uint256 gameId2 = rps.createGame{value: MIN_STAKE}(moveHash2);

        // Verify both games exist independently
        RockPaperScissors.Game memory game1 = rps.getGame(gameId1);
        RockPaperScissors.Game memory game2 = rps.getGame(gameId2);

        assertEq(game1.player1, player1);
        assertEq(game2.player1, player1);
        assertEq(gameId1, 1);
        assertEq(gameId2, 2);
    }
}

