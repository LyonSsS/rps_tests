// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title RockPaperScissors
 * @notice A confidential Rock Paper Scissors dApp using commit-reveal scheme
 * @dev Players commit moves via hash, then reveal within 2 minutes after both commit
 */
contract RockPaperScissors {
    /// @notice Possible moves in the game
    enum Move {
        ROCK,      // 0
        PAPER,     // 1
        SCISSORS   // 2
    }

    /// @notice Game status lifecycle
    enum GameStatus {
        WAITING,           // Game created, waiting for player 2
        REVEAL_PHASE,      // Both committed, reveal phase active
        TIE_RESOLUTION,    // Tie occurred, players choosing rematch/split
        COMPLETED,         // Game completed
        CANCELLED          // Game cancelled by player 1
    }

    /// @notice Tie resolution choices
    enum TieChoice {
        NONE,      // 0 - No choice made yet
        REMATCH,   // 1 - Request rematch
        SPLIT      // 2 - Request to split funds
    }

    /// @notice Game structure
    struct Game {
        address player1;
        address player2;
        uint256 stake;
        bytes32[2] commitments;          // [player1, player2]
        Move[2] reveals;                  // [player1, player2]
        bool[2] revealed;                 // [player1, player2] - track if revealed
        uint256 revealDeadline;           // Timestamp when reveal phase ends
        uint256 tieResolutionDeadline;    // Timestamp when tie resolution ends
        TieChoice[2] tieChoices;          // [player1, player2]
        GameStatus status;
    }

    /// @notice Fixed stake required to play (0.001 ETH exact)
    uint256 public constant FIXED_STAKE = 0.001 ether;

    /// @notice Reveal phase duration (2 minutes)
    uint256 public constant REVEAL_DURATION = 2 minutes;

    /// @notice Tie resolution duration (2 minutes)
    uint256 public constant TIE_RESOLUTION_DURATION = 2 minutes;

    /// @notice Game counter
    uint256 private gameCounter;

    /// @notice Games mapping: gameId => Game
    mapping(uint256 => Game) public games;

    /// @notice Events
    event GameCreated(uint256 indexed gameId, address indexed player1, uint256 stake);
    event GameJoined(uint256 indexed gameId, address indexed player2);
    event GameRevealed(uint256 indexed gameId, Move player1Move, Move player2Move);
    event GameResolved(uint256 indexed gameId, address indexed winner, Move move1, Move move2);
    event TieHandled(uint256 indexed gameId, TieChoice player1Choice, TieChoice player2Choice, bool isRematch);
    event GameCancelled(uint256 indexed gameId);

    /// @notice Errors
    /// @notice Exact fixed stake is required
    error FixedStakeRequired(uint256 required);
    error InvalidGameId();
    error GameNotInWaitingStatus();
    error GameNotInRevealPhase();
    error GameNotInTieResolution();
    error PlayerAlreadyJoined();
    error InvalidPlayer();
    error RevealDeadlinePassed();
    error TieResolutionDeadlinePassed();
    error InvalidCommitment();
    error MoveAlreadyRevealed();
    error InvalidGameStatus();
    error OnlyPlayer1CanCancel();

    /**
     * @notice Create a new game
     * @param moveHash Hash of (move + salt + nonce)
     * @return gameId The ID of the created game
     */
    function createGame(bytes32 moveHash) external payable returns (uint256 gameId) {
        if (msg.value != FIXED_STAKE) {
            revert FixedStakeRequired(FIXED_STAKE);
        }

        gameId = ++gameCounter;

        games[gameId] = Game({
            player1: msg.sender,
            player2: address(0),
            stake: msg.value,
            commitments: [moveHash, bytes32(0)],
            reveals: [Move.ROCK, Move.ROCK], // Placeholder, will be set on reveal
            revealed: [false, false],
            revealDeadline: 0,
            tieResolutionDeadline: 0,
            tieChoices: [TieChoice.NONE, TieChoice.NONE],
            status: GameStatus.WAITING
        });

        emit GameCreated(gameId, msg.sender, msg.value);
        return gameId;
    }

    /**
     * @notice Join an existing game
     * @param gameId The ID of the game to join
     * @param moveHash Hash of (move + salt + nonce)
     */
    function joinGame(uint256 gameId, bytes32 moveHash) external payable {
        Game storage game = games[gameId];

        if (game.player1 == address(0)) {
            revert InvalidGameId();
        }

        if (game.status != GameStatus.WAITING) {
            revert GameNotInWaitingStatus();
        }

        if (game.player2 != address(0)) {
            revert PlayerAlreadyJoined();
        }

        if (msg.sender == game.player1) {
            revert InvalidPlayer();
        }

        if (msg.value != game.stake) {
            revert FixedStakeRequired(game.stake);
        }

        game.player2 = msg.sender;
        game.commitments[1] = moveHash;
        game.revealDeadline = block.timestamp + REVEAL_DURATION;
        game.status = GameStatus.REVEAL_PHASE;

        emit GameJoined(gameId, msg.sender);
    }

    /**
     * @notice Reveal move within the deadline
     * @param gameId The ID of the game
     * @param move The move to reveal (ROCK, PAPER, or SCISSORS)
     * @param salt The salt used in the commitment
     * @param nonce The nonce used in the commitment
     */
    function reveal(uint256 gameId, Move move, bytes32 salt, bytes32 nonce) external {
        Game storage game = games[gameId];

        if (game.player1 == address(0)) {
            revert InvalidGameId();
        }

        if (game.status != GameStatus.REVEAL_PHASE) {
            revert GameNotInRevealPhase();
        }

        if (block.timestamp > game.revealDeadline) {
            revert RevealDeadlinePassed();
        }

        // Determine which player is revealing
        uint256 playerIndex;
        if (msg.sender == game.player1) {
            playerIndex = 0;
        } else if (msg.sender == game.player2) {
            playerIndex = 1;
        } else {
            revert InvalidPlayer();
        }

        // Verify commitment
        bytes32 commitment = _commitHash(move, salt, nonce);
        if (commitment != game.commitments[playerIndex]) {
            revert InvalidCommitment();
        }

        // Check if already revealed
        if (game.revealed[playerIndex]) {
            revert MoveAlreadyRevealed();
        }

        // Store the reveal
        game.reveals[playerIndex] = move;
        game.revealed[playerIndex] = true;

        emit GameRevealed(gameId, game.reveals[0], game.reveals[1]);

        // Resolve game if both players have revealed
        if (game.revealed[0] && game.revealed[1]) {
            _resolveGame(gameId);
        }
    }

    /**
     * @notice Handle tie resolution
     * @param gameId The ID of the game
     * @param choice The choice: REMATCH or SPLIT
     */
    function handleTie(uint256 gameId, TieChoice choice) external {
        Game storage game = games[gameId];

        if (game.player1 == address(0)) {
            revert InvalidGameId();
        }

        if (game.status != GameStatus.TIE_RESOLUTION) {
            revert GameNotInTieResolution();
        }

        // Check if deadline passed - auto-split if timeout
        if (block.timestamp > game.tieResolutionDeadline) {
            _splitFunds(gameId);
            return;
        }

        if (choice != TieChoice.REMATCH && choice != TieChoice.SPLIT) {
            revert InvalidGameStatus();
        }

        // Determine player index
        uint256 playerIndex;
        if (msg.sender == game.player1) {
            playerIndex = 0;
        } else if (msg.sender == game.player2) {
            playerIndex = 1;
        } else {
            revert InvalidPlayer();
        }

        game.tieChoices[playerIndex] = choice;

        // Check if both players made their choice
        if (game.tieChoices[0] != TieChoice.NONE && game.tieChoices[1] != TieChoice.NONE) {
            bool bothWantRematch = (game.tieChoices[0] == TieChoice.REMATCH && 
                                   game.tieChoices[1] == TieChoice.REMATCH);

            emit TieHandled(gameId, game.tieChoices[0], game.tieChoices[1], bothWantRematch);

            if (bothWantRematch) {
                // Restart game - reset to WAITING state, clear commitments and reveals
                game.commitments[0] = bytes32(0);
                game.commitments[1] = bytes32(0);
                game.reveals[0] = Move.ROCK;
                game.reveals[1] = Move.ROCK;
                game.revealed[0] = false;
                game.revealed[1] = false;
                game.revealDeadline = 0;
                game.tieResolutionDeadline = 0;
                game.tieChoices[0] = TieChoice.NONE;
                game.tieChoices[1] = TieChoice.NONE;
                game.status = GameStatus.WAITING;
            } else {
                // Split funds
                _splitFunds(gameId);
            }
        }
    }

    /**
     * @notice Split funds between players (internal helper)
     * @param gameId The ID of the game
     */
    function _splitFunds(uint256 gameId) internal {
        Game storage game = games[gameId];
        game.status = GameStatus.COMPLETED;

        (bool success1, ) = payable(game.player1).call{value: game.stake}("");
        (bool success2, ) = payable(game.player2).call{value: game.stake}("");

        require(success1 && success2, "Transfer failed");
    }

    /**
     * @notice Cancel a game if no one joined
     */
    function cancelGame(uint256 gameId) external {
        Game storage game = games[gameId];

        if (game.player1 == address(0)) {
            revert InvalidGameId();
        }

        if (game.status != GameStatus.WAITING) {
            revert GameNotInWaitingStatus();
        }

        if (msg.sender != game.player1) {
            revert OnlyPlayer1CanCancel();
        }

        game.status = GameStatus.CANCELLED;

        (bool success, ) = payable(game.player1).call{value: game.stake}("");
        require(success, "Refund failed");

        emit GameCancelled(gameId);
    }

    /**
     * @notice Get game details
     * @param gameId The ID of the game
     * @return The game structure
     */
    function getGame(uint256 gameId) external view returns (Game memory) {
        return games[gameId];
    }

    /**
     * @notice Check if reveal deadline has passed
     * @param gameId The ID of the game
     * @return True if deadline passed
     */
    function isRevealDeadlinePassed(uint256 gameId) external view returns (bool) {
        Game memory game = games[gameId];
        if (game.status != GameStatus.REVEAL_PHASE) {
            return false;
        }
        return block.timestamp > game.revealDeadline;
    }

    /**
     * @notice Resolve game after both reveals
     * @param gameId The ID of the game
     */
    function _resolveGame(uint256 gameId) internal {
        Game storage game = games[gameId];

        // Determine winner (0 = tie, 1 = player1, 2 = player2)
        uint256 winner = _determineWinner(game.reveals[0], game.reveals[1]);

        if (winner == 0) {
            // Tie - enter tie resolution phase
            game.status = GameStatus.TIE_RESOLUTION;
            game.tieResolutionDeadline = block.timestamp + TIE_RESOLUTION_DURATION;
            emit GameResolved(gameId, address(0), game.reveals[0], game.reveals[1]);
        } else {
            // Winner determined - transfer funds
            game.status = GameStatus.COMPLETED;
            address winnerAddress = winner == 1 ? game.player1 : game.player2;
            uint256 totalStake = game.stake * 2;

            (bool success, ) = payable(winnerAddress).call{value: totalStake}("");
            require(success, "Transfer failed");

            emit GameResolved(gameId, winnerAddress, game.reveals[0], game.reveals[1]);
        }
    }

    /**
     * @notice Claim outcome after reveal deadline if both players did not reveal
     * @dev If exactly one player revealed, the revealer wins the full pot. If none revealed, funds are split.
     */
    function claimAfterRevealTimeout(uint256 gameId) external {
        Game storage game = games[gameId];

        if (game.player1 == address(0)) {
            revert InvalidGameId();
        }

        if (game.status != GameStatus.REVEAL_PHASE) {
            revert GameNotInRevealPhase();
        }

        if (block.timestamp <= game.revealDeadline) {
            revert RevealDeadlinePassed(); // reuse as generic timing guard (not yet passed)
        }

        bool p1 = game.revealed[0];
        bool p2 = game.revealed[1];

        // Both revealed should have already resolved; treat as invalid state
        require(!(p1 && p2), "Already both revealed");

        game.status = GameStatus.COMPLETED;

        if (p1 && !p2) {
            // Player1 wins
            address winnerAddress = game.player1;
            uint256 totalStake = game.stake * 2;
            (bool success, ) = payable(winnerAddress).call{value: totalStake}("");
            require(success, "Transfer failed");
            emit GameResolved(gameId, winnerAddress, game.reveals[0], game.reveals[1]);
        } else if (!p1 && p2) {
            // Player2 wins
            address winnerAddress = game.player2;
            uint256 totalStake = game.stake * 2;
            (bool success, ) = payable(winnerAddress).call{value: totalStake}("");
            require(success, "Transfer failed");
            emit GameResolved(gameId, winnerAddress, game.reveals[0], game.reveals[1]);
        } else {
            // None revealed → split
            (bool success1, ) = payable(game.player1).call{value: game.stake}("");
            (bool success2, ) = payable(game.player2).call{value: game.stake}("");
            require(success1 && success2, "Transfer failed");
            emit GameResolved(gameId, address(0), game.reveals[0], game.reveals[1]);
        }
    }

    /**
     * @notice Determine winner (0 = tie, 1 = player1, 2 = player2)
     * @param move1 Player 1's move
     * @param move2 Player 2's move
     * @return Winner: 0 = tie, 1 = player1, 2 = player2
     */
    function _determineWinner(Move move1, Move move2) internal pure returns (uint256) {
        // Same moves = tie
        if (move1 == move2) {
            return 0;
        }

        // Rock beats Scissors
        if (move1 == Move.ROCK && move2 == Move.SCISSORS) {
            return 1;
        }
        if (move1 == Move.SCISSORS && move2 == Move.ROCK) {
            return 2;
        }

        // Paper beats Rock
        if (move1 == Move.PAPER && move2 == Move.ROCK) {
            return 1;
        }
        if (move1 == Move.ROCK && move2 == Move.PAPER) {
            return 2;
        }

        // Scissors beats Paper
        if (move1 == Move.SCISSORS && move2 == Move.PAPER) {
            return 1;
        }
        if (move1 == Move.PAPER && move2 == Move.SCISSORS) {
            return 2;
        }

        return 0; // Should never reach here
    }

    /**
     * @notice Generate commitment hash
     * @param move The move
     * @param salt The salt
     * @param nonce The nonce
     * @return The hash commitment
     */
    function _commitHash(Move move, bytes32 salt, bytes32 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(move, salt, nonce));
    }
}

