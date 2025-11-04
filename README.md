# Rock Paper Scissors dApp

A confidential Rock Paper Scissors decentralized application using a commit-reveal scheme for move confidentiality. Players commit their moves as hashes, then reveal within a 2-minute window after both players have committed.

**Deployed Sepolia Contract:** [0xDa929CFa4E076d9928674Ba4a3adf5E02E71f64C](https://sepolia.etherscan.io/address/0xDa929CFa4E076d9928674Ba4a3adf5E02E71f64C)

## Features

- **Confidential Moves**: Uses commit-reveal scheme - players can see commitments but not actual moves until reveal
- **Stake-based Gameplay**: Each game requires 0.001 ETH stake from both players
- **Automatic Resolution**: Winner receives full stake (0.002 ETH total)
- **Tie Resolution**: Players can choose rematch or split funds
- **Game Discovery**: Games discoverable via on-chain events
- **Time Limits**: 2-minute reveal phase, 2-minute tie resolution phase

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- Node.js 18+ and Yarn
- Git installed
- For testnet tests: Sepolia ETH in your wallet

## Installation

1. Clone the repository:
```bash
git clone https://github.com/LyonSsS/rps_tests.git
cd rps_tests
```

2. Install dependencies:
```bash
# Install forge-std test library
forge install foundry-rs/forge-std@v1.9.5

# Install Node.js dependencies (for TypeScript tests)
yarn install

# Build contracts (generates ABIs needed for TS tests)
forge build
```

3. Create `.env` file:
```bash
cp .env.example .env
```

4. Configure `.env` file:
```bash
# Required for all tests
PRIVATE_KEY=0x...              # First wallet (player1)
PRIVATE_KEY_2=0x...            # Second wallet (player2) - optional

# Required for Sepolia tests
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/your_key
CONTRACT_ADDRESS=0xDa929CFa4E076d9928674Ba4a3adf5E02E71f64C  # Pre-deployed Sepolia contract

# Optional
ANVIL_RPC_URL=http://127.0.0.1:8545  # Default if not set
ETHERSCAN_API_KEY=your_etherscan_key
```

**Note:** Use 0x-prefixed hex private keys (e.g., `0x0123abcd...`).

## Running Tests

All test commands are available via Yarn scripts in `package.json`. Test reports are automatically saved to the `reports/` folder.

### Solidity Tests (Foundry)

Run all Solidity tests:
```bash
yarn test:sol
```

This runs all test suites:
- **Unit Tests** (`sol_tests/RockPaperScissors.t.sol`): Function-level logic, revert reasons, edge cases
- **Integration Tests** (`sol_tests/RockPaperScissorsIntegration.t.sol`): Full contract flows and state transitions
- **E2E Tests** (`sol_tests/RockPaperScissorsE2E.t.sol`): Complete user journeys with events and balance assertions



### TypeScript E2E Tests

#### Viem-based Tests

**Anvil (Local):**
```bash
# Terminal 1: Start Anvil with zero fees for exact assertions
yarn anvil:zero

# Terminal 2: Run tests
yarn test:ts:anvil
```

**Sepolia (Testnet):**
```bash
yarn test:ts:sepolia
```

#### Ethers.js-based Tests

**Anvil (Local):**
```bash
# Terminal 1: Start Anvil with zero fees
yarn anvil:zero

# Terminal 2: Run tests
yarn test:ethers:anvil
```

**Sepolia (Testnet):**
```bash
yarn test:ethers:sepolia
```

### Test Features

- **Anvil Tests**: Zero-fee setup for exact balance assertions (perfect math)
- **Sepolia Tests**: 
  - Real-time event listening and polling
  - Dynamic gas estimation with 1.3x multiplier
  - Automatic gas fee calculation for balance assertions
  - Time-based waiting for tie resolution deadlines

### Test Reports

All test output is automatically logged to the `reports/` folder with timestamps:
- Format: `{testName}_{environment}_{timestamp}.log`
- Examples:
  - `run_viem_anvil_2025-11-04T18-02-30.log`
  - `run_ethers_sepolia_2025-11-04T18-08-19.log`
  - `forge_test_solidity_2025-11-04T18-10-45.log`

## Project Structure

```
.
├── src/
│   └── RockPaperScissors.sol           # Main smart contract
├── sol_tests/                           # Solidity test suites (Foundry)
│   ├── RockPaperScissors.t.sol         # Unit tests
│   ├── RockPaperScissorsIntegration.t.sol  # Integration tests
│   └── RockPaperScissorsE2E.t.sol      # E2E tests
├── ts_tests/                            # TypeScript E2E tests
│   ├── run.ts                           # Viem-based test runner
│   ├── run_ethers.ts                    # Ethers.js-based test runner
│   ├── runForgeTest.ts                  # Foundry test wrapper
│   ├── reportLogger.ts                  # Test report generator
│   └── client/
│       └── utils.ts                     # Test utilities
├── reports/                              # Generated test reports (gitignored)
├── script/
│   └── Deploy.s.sol                     # Deployment script
├── docs/
│   └── TEST_STRATEGY.md                 # Testing strategy document
├── .github/workflows/
│   └── ci.yml                           # CI/CD pipeline
├── foundry.toml                         # Foundry configuration
├── package.json                         # Node.js dependencies and scripts
├── tsconfig.json                        # TypeScript configuration
└── README.md                             # This file
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

## Testing Strategy

### Test Pyramid

The project follows a test pyramid approach:

- **Unit Tests** (`sol_tests/RockPaperScissors.t.sol`): Fast, isolated function tests
  - Function-level logic and revert reasons
  - Edge cases (timeouts, invalid commitments, double operations)
  - All winner/tie combinations
  - Fixed-stake enforcement

- **Integration Tests** (`sol_tests/RockPaperScissorsIntegration.t.sol`): Full contract flows
  - State transitions (create → join → reveal → resolve)
  - Tie flows (SPLIT/REMATCH)
  - Multiple concurrent games
  - Timeout-claim flows

- **E2E Tests** (`sol_tests/RockPaperScissorsE2E.t.sol` + TypeScript): Client-perspective journeys
  - Complete happy paths
  - Game discovery via events
  - Balance assertions
  - Real network interaction (Anvil + Sepolia)

See [TEST_STRATEGY.md](./TEST_STRATEGY.md) for detailed testing strategy.

### Test Coverage

- ✅ All core functions (create, join, reveal, handleTie, cancel)
- ✅ Win/loss logic (3 wins to cover all 6 combinations + 2 tie scenarios)
- ✅ Edge cases (timeouts, invalid commitments, double operations)
- ✅ State transitions
- ✅ Fund transfers with exact balance assertions
- ✅ Event emissions
- ✅ Gas optimization testing

## Deployment

### Local (Anvil)

```bash
# Start Anvil
yarn anvil:zero  # or just: anvil

# Deploy (in another terminal)
forge script script/Deploy.s.sol:DeployScript --rpc-url http://localhost:8545 --broadcast
```

### Sepolia Testnet

The contract is already deployed at: [0xDa929CFa4E076d9928674Ba4a3adf5E02E71f64C](https://sepolia.etherscan.io/address/0xDa929CFa4E076d9928674Ba4a3adf5E02E71f64C)

To deploy a new instance:
```bash
forge script script/Deploy.s.sol:DeployScript --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
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

