# Test Strategy Document

## Application Choice: Rock Paper Scissors dApp

I chose to implement a Rock Paper Scissors dApp because:

1. **Clear Game Logic**: The win/loss rules are straightforward (rock beats scissors, paper beats rock, scissors beats paper), making it easy to test correctness.
2. **Confidentiality Requirement**: The commit-reveal scheme demonstrates how to maintain confidentiality in blockchain applications, which is a core requirement of the assignment.
3. **Multiple Phases**: The game has distinct phases (creation, join, reveal, resolution, tie handling), allowing for comprehensive testing at each stage.
4. **Real-World Applicability**: This pattern (commit-reveal) is commonly used in blockchain applications like voting, auctions, and games.

## Main Risks for This Application

### 1. **Front-Running Attacks**
- **Risk**: Player 2 could observe player 1's commitment, wait for their reveal, then front-run with a winning move.
- **Mitigation**: The commit-reveal scheme ensures that player 2 cannot see player 1's move until both have committed. By the time player 2 sees player 1's reveal, they must have already committed their own move.

### 2. **Commitment Validation**
- **Risk**: Players could submit invalid commitments or reveal moves that don't match their commitments.
- **Mitigation**: The contract verifies that `hash(move + salt + nonce) == commitment` before accepting a reveal. This ensures players cannot change their move after seeing the opponent's move.

### 3. **Time-Based Attacks & Prolonged Waiting**
- **Risk**: Players could exploit timing to gain advantages (e.g., waiting until the last second to reveal) or refuse to reveal indefinitely, locking funds.
- **Mitigation**: 
  - A fixed 2-minute reveal deadline ensures both players have equal time to reveal.
  - If a player misses the deadline, they cannot reveal after it expires.
  - **Timeout Resolution**: After the deadline passes, `claimAfterRevealTimeout()` can be called:
    - If **one player revealed** and the other didn't: The revealer wins the full pot by default (prevents prolonged waiting and rewards timely reveals).
    - If **neither player revealed**: Funds are automatically split (prevents indefinite lockup).
  - This mechanism prevents games from being stuck indefinitely while incentivizing timely reveals.

### 4. **Tie Resolution Coordination**
- **Risk**: In tie resolution, players need to coordinate their choices (rematch vs split). If one player doesn't respond, the game could be stuck.
- **Mitigation**: After the tie resolution deadline, funds are automatically split, ensuring the game never gets permanently stuck.

### 5. **Gas Optimization vs Security**
- **Risk**: Complex state tracking could lead to gas inefficiencies or bugs.
- **Mitigation**: Used simple boolean flags for reveal tracking, avoiding complex mappings while maintaining security.

## Test Structure Explanation

The project follows a test pyramid with **Solidity tests** (Foundry) and **TypeScript E2E tests** (viem/ethers.js) for comprehensive coverage.

### Solidity Tests (Foundry)

#### Unit Tests (`sol_tests/RockPaperScissors.t.sol`)

**What they test**: Individual functions in isolation, verifying correctness of each function independently.

**Why this level**:
- **Fast execution**: Unit tests run quickly, allowing rapid iteration during development.
- **Isolated failures**: When a test fails, it's immediately clear which function has the issue.
- **Edge cases**: Easier to test edge cases for individual functions (e.g., invalid stake, wrong game ID).

**Coverage**:
- `createGame()`: Validates stake, emits events, creates game correctly.
- `joinGame()`: Validates all join conditions (game exists, correct status, valid stake, different players).
- `reveal()`: Validates commitment matching, deadline, player authorization.
- `_determineWinner()`: Tests all win/loss combinations (3 win scenarios + 2 tie scenarios).
- `handleTie()`: Tests rematch, split, mixed choices, timeout.
- `cancelGame()`: Validates cancellation conditions and refunds.
- `claimAfterRevealTimeout()`: Single revealer wins pot; none reveal splits; guards (before-deadline, double-claim).

**Win/Loss Combinations Tested**:
- ✅ Rock beats Scissors (P1 wins)
- ✅ Paper beats Rock (P2 wins)
- ✅ Scissors beats Paper (P2 wins)
- ✅ Rock vs Rock (tie)
- ✅ Scissors vs Scissors (tie)
- Note: All 6 win combinations are covered by symmetry; 2 of 3 tie combinations explicitly tested

#### Integration Tests (`sol_tests/RockPaperScissorsIntegration.t.sol`)

**What they test**: Full game flows with multiple function calls, testing how different functions work together.

**Why this level**:
- **Real-world scenarios**: Tests complete user journeys (create → join → reveal → resolve).
- **State transitions**: Verifies game state transitions correctly through all phases.
- **Edge cases**: Tests failure scenarios in the context of a full game (e.g., reveal after deadline, double reveal).

**Coverage**:
- Happy path: Full game with winner determination.
- Tie resolution: Rematch flow and split flow.
- Failure cases: Invalid reveals, timeouts, double operations.
- Multiple games: Ensures games are isolated and don't interfere.
- Timeout-claim flows: Only P1 revealed → P1 wins; only P2 revealed → P2 wins; none revealed → split.

#### End-to-End Tests (`sol_tests/RockPaperScissorsE2E.t.sol`)

**What they test**: Complete user journey from a client's perspective, simulating how real users would interact with the contract.

**Why this level**:
- **Client perspective**: Tests simulate off-chain commitment generation and event discovery.
- **Real-world workflow**: Shows how players would discover games via events, join, and interact.
- **Event-based discovery**: Verifies that game discovery via events works correctly.

**Coverage**:
- Complete user journey: Discovery → Join → Reveal → Resolution.
- Event-based discovery: Multiple games, players choosing which to join.
- Tie resolution with rematch.
- Game cancellation when no one joins.
- Timeout claim: Only one player reveals then `claimAfterRevealTimeout`, and none-revealed split.

### TypeScript E2E Tests

#### Viem-based Tests (`ts_tests/run.ts`)

**What they test**: Real-world interaction with the contract using `viem` library, simulating how a frontend or dApp would interact.

**Environments**:
- **Anvil (Local)**: Zero-fee setup for exact balance assertions (perfect math)
- **Sepolia (Testnet)**: Real-time event listening, dynamic gas estimation with 1.3x multiplier, time-based waiting

**Coverage**:
- Complete game scenarios (WIN and TIE) with real balance assertions
- Event listening and polling for Sepolia
- Gas fee calculation and dynamic assertion ranges
- Automatic contract deployment on Anvil
- Time-warping for tie resolution on Anvil

#### Ethers.js-based Tests (`ts_tests/run_ethers.ts`)

**What they test**: Same scenarios as viem tests but using `ethers.js` library for alternative client implementation.

**Environments**:
- **Anvil (Local)**: Zero-fee setup, exact balance assertions
- **Sepolia (Testnet)**: Real-time waiting, dynamic gas estimation

**Coverage**:
- Mirrors viem test coverage with ethers.js implementation
- Nonce management for sequential transactions
- EIP-1559 gas fee handling


## Test Execution

### Solidity Tests (Foundry)

All Solidity tests use Foundry (Forge), providing:
- Fast execution (compiled to EVM bytecode)
- Built-in fuzzing capabilities
- Local Anvil node for testing
- Sepolia testnet integration

**Run all Solidity tests**:
```bash
yarn test:sol
```

This runs all test suites via `tsx ts_tests/runForgeTest.ts` which wraps `forge test` with verbose output and captures logs to `reports/` folder.

**Run specific test level** (direct forge commands):
```bash
forge test --match-path sol_tests/RockPaperScissors.t.sol          # Unit tests
forge test --match-path sol_tests/RockPaperScissorsIntegration.t.sol # Integration tests
forge test --match-path sol_tests/RockPaperScissorsE2E.t.sol        # E2E tests
```

**Verbose output for debugging**:
```bash
forge test -vvv
```

### TypeScript E2E Tests

TypeScript tests provide real-world validation against local and testnet environments.

**Viem-based Tests**:
```bash
# Anvil (Local) - requires: yarn anvil:zero in separate terminal
yarn test:ts:anvil

# Sepolia (Testnet)
yarn test:ts:sepolia
```

**Ethers.js-based Tests**:
```bash
# Anvil (Local) - requires: yarn anvil:zero in separate terminal
yarn test:ethers:anvil

# Sepolia (Testnet)
yarn test:ethers:sepolia
```

### Test Reports

All test output is automatically logged to the `reports/` folder:
- Format: `{testName}_{environment}_{timestamp}.log`
- Examples:
  - `run_viem_anvil_2025-11-04T18-02-30.log`
  - `run_ethers_sepolia_2025-11-04T18-08-19.log`
  - `forge_test_solidity_2025-11-04T18-10-45.log`

Reports capture all console output, making it easy to review test runs and debug failures.

## Reflection

### Completed Enhancements

1. ✅ **TypeScript/viem E2E Tests**: Added comprehensive E2E tests using `viem` library for real-world validation
   - Tests run against both Anvil (local) and Sepolia (testnet)
   - Includes real-time event listening, gas estimation, and balance assertions
   - Automatic contract deployment on Anvil

2. ✅ **Ethers.js E2E Tests**: Added alternative implementation using `ethers.js` library
   - Mirrors viem test coverage for cross-library validation
   - Includes nonce management and EIP-1559 gas handling

3. ✅ **Test Reporting**: Automatic log capture to `reports/` folder with timestamps
   - All test output (Solidity and TypeScript) is saved for review
   - Helps with debugging and test history tracking

4. ✅ **Network-Specific Testing**: Differentiated test behavior for Anvil vs Sepolia
   - Anvil: Zero-fee setup for exact balance assertions (perfect math)
   - Sepolia: Dynamic gas estimation with 1.3x multiplier, real-time waiting

5. ✅ **Gas Optimization**: Implemented robust gas estimation with buffers for testnet reliability

### If I had more time:

1. **Gas Benchmarking**: More detailed gas cost analysis and optimization metrics.
2. **Time Manipulation Edge Cases**: More comprehensive tests for deadline boundaries (exactly at deadline, 1 second before/after).
3. **Multiple Simultaneous Games**: Test scenarios with many active games to ensure no interference.
4. **Rematch Flow Enhancement**: The current rematch requires manual commitment again. Could add a helper function to streamline rematch commitments.
5. **Event Indexing Tests**: Test event filtering and querying patterns that a real dApp would use.
6. **CI/CD Integration**: Enhanced GitHub Actions workflow to run all test suites (Solidity + TypeScript) automatically.

### AI coding assistance: 

**What worked well**:
- Code structure suggestions: AI helped organize the contract structure with clear separation of concerns.
- Test pattern generation: AI suggested good patterns for testing state transitions and edge cases.
- Error handling: AI helped identify potential revert conditions and appropriate error messages.
- General set-up: fixed to solve dependency issues and integration missoncfiguration
- Compare various approaches beneffits vs disadvantages

**What did not work well**:
- Complex logic refinement: Initial reveal logic was overcomplicated; required manual simplification.
- Context preservation: Sometimes AI would lose track of the full game flow when making incremental changes.
- Wehn debating scenario covers AI did missed a lot of edge case scenarios.
- AI missed to understand the logic of the contract to what will happen if someone will not reveal in the reveal period ( as the funds where locked indefitinie). I had to redeploy a new contract with updated logic
- Generated incorrect assertions based on my requirements. Also the assertions had to be double checked and enforced as scenarios passed even with incorrect values. 


**Overall**: In the end 90% ++ of the code here is generated by AI based on my requirements and I was the one overseeing, checking and reviewing all that is done. I am using cursor and usually I do use ts + etherjs ( +ABI of the contract) to interrecat with my needs and a lot of RPC "read" from chian methods to validate assertsion ( based on parsed events in 90% of the cases). 
My recent projects where I am testing a solver that does swap, I did found a cool set-up in golang with W3vm which I had no idea how it worked and did not knew go, but I managed with AI to make comprehensive tests done on eth fork and base fork, where I querry Dune for cowSwap last 30 days top 50 pairs sorted by USD value then create them into a JSON file with scenarios and feed it to this go set-up to execute scenarios on a forked state of eth or base chain. 
I would not be great at live coding but I can handle what ever task I have in front of me with the help of AI. 
