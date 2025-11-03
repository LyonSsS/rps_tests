# Rock Paper Scissors dApp

A confidential Rock Paper Scissors decentralized application using a commit-reveal scheme for move confidentiality. Players commit their moves as hashes, then reveal within a 2-minute window after both players have committed.

## Features

- **Confidential Moves**: Uses commit-reveal scheme - players can see commitments but not actual moves until reveal
- **Stake-based Gameplay**: Each game requires 0.001 ETH stake from both players
- **Automatic Resolution**: Winner receives full stake (0.002 ETH total)
- **Tie Resolution**: Players can choose rematch or split funds
- **Game Discovery**: Games discoverable via on-chain events
- **Time Limits**: 2-minute reveal phase, 2-minute tie resolution phase

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- Git installed
- For testnet deployment: Sepolia ETH in your wallet

## Installation

1. Clone the repository:
```bash
git clone https://github.com/LyonSsS/rps_tests.git
cd rps_tests
```

2. Install test library dependency (forge-std) and set remapping:
```bash
# Add forge-std test utils
forge install foundry-rs/forge-std@v1.9.5

# Ensure remapping exists (once)
printf '\nremappings = ["forge-std/=lib/forge-std/src/"]\n' >> foundry.toml
```

3. (Optional) Clean and build to verify setup:
```bash
forge clean
forge build
```

4. Create `.env` file (copy from `.env.example`):
```bash
cp .env.example .env
```

5. Fill in your `.env` file:
```
PRIVATE_KEY=your_private_key_here
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/your_key
ETHERSCAN_API_KEY=your_etherscan_key
```

Note on PRIVATE_KEY format:
- Use a 0x-prefixed hex private key (example: `0x0123abcd...`).
- If your key is missing the prefix in your current shell session, you can export it as:
```bash
export PRIVATE_KEY=0x$PRIVATE_KEY
```
Then re-run the deploy command.

## Quick Start

### Run All Tests

```bash
forge test
```

This single command runs all tests (unit, integration, and E2E).

### Test Layers (what each suite covers)

- Unit (`test/RockPaperScissors.t.sol`): function-level logic, revert reasons, edge cases, all winner/tie branches, double-reveal, commitment mismatches, fixed-stake enforcement, timeout-claim unit cases.
- Integration (`test/RockPaperScissorsIntegration.t.sol`): full contract flows and state transitions (create → join → reveal → resolve), tie flows (SPLIT/REMATCH), multiple concurrent games, and timeout-claim flows.
- E2E (`test/RockPaperScissorsE2E.t.sol`): client-perspective journeys using events and balance assertions (complete happy path, discovery, cancel, rematch, and timeout-claim where only one player reveals or none reveal).

Rationale: follow a test-pyramid – many fast unit tests, fewer integration, few E2E – for speed, debuggability, and realistic coverage.

### Run Specific Test Suites

```bash
# Unit tests only
forge test --match-path test/RockPaperScissors.t.sol

# Integration tests only
forge test --match-path test/RockPaperScissorsIntegration.t.sol

# E2E tests only
forge test --match-path test/RockPaperScissorsE2E.t.sol
```

### Run Tests with Verbose Output

```bash
forge test -vvv
```

### Build Contracts

```bash
forge build
```

## How It Works

### Game Flow

1. **Game Creation**: Player 1 creates a game with a hashed move commitment and stakes 0.001 ETH
   - Game emits `GameCreated` event (discoverable by other players)
   - Game stays open indefinitely until someone joins

2. **Game Join**: Player 2 joins with their own move commitment and stakes 0.001 ETH
   - Emits `GameJoined` event
   - Starts 2-minute reveal phase

3. **Reveal Phase**: Both players reveal their moves within 2 minutes
   - Contract verifies commitments match hashes
   - Emits `GameRevealed` event

4. **Resolution**: 
   - If winner: Winner receives full stake (0.002 ETH)
   - If tie: Enters 2-minute tie resolution phase

5. **Tie Resolution** (if applicable):
   - Both players choose REMATCH or SPLIT
   - Both REMATCH: Game restarts (same game ID)
   - Otherwise: Funds split (0.001 ETH each)
   - Timeout: Auto-split funds

### Example Usage

```solidity
// Generate commitment off-chain
bytes32 salt = keccak256("my_secret_salt");
bytes32 nonce = keccak256("my_nonce");
bytes32 moveHash = keccak256(abi.encodePacked(Move.ROCK, salt, nonce));

// Player 1 creates game
uint256 gameId = rps.createGame{value: 0.001 ether}(moveHash);

// Player 2 joins (after discovering via event)
rps.joinGame{value: 0.001 ether}(gameId, moveHash2);

// Both reveal
rps.reveal(gameId, Move.ROCK, salt, nonce);
rps.reveal(gameId, Move.PAPER, salt2, nonce2);

// Winner automatically receives funds
```

## Contract Functions

### Core Functions

- `createGame(bytes32 moveHash)`: Create a new game with stake
- `joinGame(uint256 gameId, bytes32 moveHash)`: Join an existing game
- `reveal(uint256 gameId, Move move, bytes32 salt, bytes32 nonce)`: Reveal your move
- `handleTie(uint256 gameId, TieChoice choice)`: Handle tie resolution (REMATCH or SPLIT)
- `cancelGame(uint256 gameId)`: Cancel a game if no one joined

### View Functions

- `getGame(uint256 gameId)`: Get game details
- `isRevealDeadlinePassed(uint256 gameId)`: Check if reveal deadline passed

### Events

- `GameCreated(uint256 indexed gameId, address indexed player1, uint256 stake)`
- `GameJoined(uint256 indexed gameId, address indexed player2)`
- `GameRevealed(uint256 indexed gameId, Move player1Move, Move player2Move)`
- `GameResolved(uint256 indexed gameId, address indexed winner, Move move1, Move move2)`
- `TieHandled(uint256 indexed gameId, TieChoice player1Choice, TieChoice player2Choice, bool isRematch)`
- `GameCancelled(uint256 indexed gameId)`

## Testing

### Test Structure

- **Unit Tests** (`test/RockPaperScissors.t.sol`): Test individual functions
- **Integration Tests** (`test/RockPaperScissorsIntegration.t.sol`): Test full game flows
- **E2E Tests** (`test/RockPaperScissorsE2E.t.sol`): Test complete user journeys

See [TEST_STRATEGY.md](./docs/TEST_STRATEGY.md) for detailed testing strategy.

### Test Coverage

Tests cover:
- ✅ All core functions (create, join, reveal, handleTie, cancel)
- ✅ Win/loss logic (all combinations)
- ✅ Edge cases (timeouts, invalid commitments, double operations)
- ✅ State transitions
- ✅ Fund transfers
- ✅ Event emissions

## Deployment

### Local (Anvil)

```bash
# Start Anvil
anvil

# Deploy (in another terminal)
forge script script/Deploy.s.sol:DeployScript --rpc-url http://localhost:8545 --broadcast
```

### Sepolia Testnet

```bash
forge script script/Deploy.s.sol:DeployScript --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

## Project Structure

```
.
├── src/
│   └── RockPaperScissors.sol      # Main contract
├── test/
│   ├── RockPaperScissors.t.sol              # Unit tests
│   ├── RockPaperScissorsIntegration.t.sol  # Integration tests
│   └── RockPaperScissorsE2E.t.sol            # E2E tests
├── script/
│   └── Deploy.s.sol               # Deployment script
├── docs/
│   └── TEST_STRATEGY.md           # Testing strategy document
├── .github/workflows/
│   └── ci.yml                     # CI/CD pipeline
├── foundry.toml                   # Foundry configuration
├── .env.example                   # Environment variables template
└── README.md                       # This file
```

## Security Considerations

- **Commit-Reveal**: Prevents front-running by hiding moves until both committed
- **Deadline Enforcement**: Prevents indefinite games
- **Automatic Split**: Tie resolution timeout prevents stuck games
- **Access Control**: Only authorized players can interact with their games

## License

MIT

## Author

Homework submission for confidential dApp with comprehensive testing strategy.

