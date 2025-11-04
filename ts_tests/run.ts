import { loadEnv, makeClients, getDeployedContract, makeCommit } from './client/utils.js';
import { keccak256, encodePacked, parseEther, decodeEventLog, Hex, createTestClient, http, formatEther } from 'viem';
import { foundry } from 'viem/chains';
import { startLogging, stopLogging } from './reportLogger.js';

async function runGameScenario(
  publicClient: any,
  wallet1: any,
  wallet2: any,
  account1: any,
  account2: any,
  address: Hex,
  abi: any,
  p1Move: number,
  p2Move: number,
  scenarioName: string,
  isLocal: boolean,
  env: any
) {
  // Simple delay helper
  const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

  // Wait until on-chain time reaches target timestamp (for real networks)
  async function waitUntilOnChainTime(targetTimestamp: bigint, pollMs: number = 15000) {
    // Poll latest block time until it passes targetTimestamp
    // Add small buffer to reduce off-by-a-few-seconds risks
    const bufferSeconds = 2n;
    while (true) {
      const latestBlock = await publicClient.getBlock({ blockTag: 'latest' });
      if ((latestBlock.timestamp + bufferSeconds) >= targetTimestamp) break;
      await sleep(pollMs);
    }
  }

  // Pretty print ETH without scientific notation, trimming trailing zeros
  function prettyEth(wei: bigint): string {
    const s = formatEther(wei);
    // Trim trailing zeros but leave at least one decimal if needed
    const trimmed = s.includes('.') ? s.replace(/\.0+$/,'').replace(/(\.\d*?)0+$/,'$1') : s;
    return trimmed;
  }

  // Wait for an address balance to change from a starting value (or until timeout)
  async function waitForBalanceUpdate(
    addr: Hex,
    startBalance: bigint,
    timeoutMs: number = 90_000,
    pollMs: number = 5_000
  ): Promise<bigint> {
    const start = Date.now();
    let latest = startBalance;
    while (Date.now() - start < timeoutMs) {
      const b = await publicClient.getBalance({ address: addr }) as unknown as bigint;
      if (b !== startBalance) {
        latest = b;
        break;
      }
      await sleep(pollMs);
    }
    return latest;
  }

  const moveNames = ['ROCK', 'PAPER', 'SCISSORS'];
  const statusNames = ['WAITING', 'REVEAL_PHASE', 'TIE_RESOLUTION', 'COMPLETED', 'CANCELLED'];
  const stakeAmount = parseEther('0.001');
  
  // Track transactions by player (for Sepolia dynamic gas-based expectations)
  const p1Txs: Hex[] = [];
  const p2Txs: Hex[] = [];

  async function getTxFeeWei(hash: Hex): Promise<bigint> {
    const receipt = await publicClient.getTransactionReceipt({ hash });
    const gasUsed = receipt.gasUsed as unknown as bigint;
    const effectiveGasPrice = (receipt as any).effectiveGasPrice as bigint | undefined;
    if (effectiveGasPrice && typeof effectiveGasPrice === 'bigint') {
      return gasUsed * effectiveGasPrice;
    }
    const tx = await publicClient.getTransaction({ hash });
    const gasPrice = (tx.gasPrice ?? 0n) as bigint;
    return gasUsed * gasPrice;
  }

  async function sumGasFeesWei(hashes: Hex[]): Promise<bigint> {
    let total = 0n;
    for (const h of hashes) total += await getTxFeeWei(h);
    return total;
  }
  
  // Helper to get gas/fee options
  const getGasOptions = async () => {
    // On Anvil we want truly zero-fee txs for exact assertions
    if (isLocal) {
      return { gasPrice: 0n } as const;
    }
    try {
      // Prefer EIP-1559 fee market
      const fees = await publicClient.estimateFeesPerGas();
      const maxFeePerGas = fees.maxFeePerGas ? (fees.maxFeePerGas * 130n) / 100n : undefined;
      const maxPriorityFeePerGas = fees.maxPriorityFeePerGas ? (fees.maxPriorityFeePerGas * 130n) / 100n : undefined;
      if (maxFeePerGas && maxPriorityFeePerGas) {
        return { maxFeePerGas, maxPriorityFeePerGas };
      }
    } catch {}
    // Fallback to legacy gasPrice with a 20% buffer
    const gasPrice = await publicClient.getGasPrice();
    return { gasPrice: (gasPrice * 130n) / 100n };
  };

  async function estimateGasWithBuffer(
    account: Hex,
    fn: string,
    args: any[],
    value?: bigint
  ): Promise<bigint> {
    try {
      const est = await publicClient.estimateContractGas({
        account,
        address,
        abi,
        functionName: fn as any,
        args: args as any,
        value,
      });
      // Only apply 1.3x buffer on Sepolia (not Anvil)
      return isLocal ? est : (est * 130n) / 100n;
    } catch (err) {
      // If estimation fails, return a conservative default to avoid OOG (still may fail)
      // This is a last-resort; we still rely on node estimation primarily.
      return 1_500_000n;
    }
  }

  console.log(`\n${'='.repeat(60)}`);
  console.log(`🧪 ${scenarioName}`);
  console.log(`${'='.repeat(60)}`);
  
  // Get initial balances
  const balance1Before: bigint = await publicClient.getBalance({ address: account1.address }) as unknown as bigint;
  const balance2Before: bigint = await publicClient.getBalance({ address: account2.address }) as unknown as bigint;
  console.log(`💰 Initial Balances:`);
  console.log(`   P1: ${balance1Before} wei`);
  console.log(`   P2: ${balance2Before} wei`);

  // Step 1: Player 1 creates game
  console.log(`\n📝 Step 1: Player 1 creating game...`);
  const p1 = makeCommit(p1Move);
  const commitment1 = keccak256(encodePacked(['uint8','bytes32','bytes32'], [p1.move, p1.salt, p1.nonce]));
  console.log(`   Move: ${moveNames[p1.move]} (${p1.move})`);
  console.log(`   Commitment: ${commitment1}`);
  
  const gasOpts1 = await getGasOptions();
  const createGas = await estimateGasWithBuffer(account1.address, 'createGame', [commitment1], stakeAmount);
  const createHash = await wallet1.writeContract({ address, abi, functionName: 'createGame', args: [commitment1], value: stakeAmount, gas: createGas, ...gasOpts1 });
  const receipt = await publicClient.waitForTransactionReceipt({ hash: createHash });
  console.log(`   ✅ Game created! TX: ${createHash}`);
  p1Txs.push(createHash as Hex);

  // Fetch gameId
  let gameId: bigint;
  const gameCreatedLog = receipt.logs.find((log: any) => {
    try {
      const decoded = decodeEventLog({ abi, data: log.data, topics: log.topics }) as { eventName: string; args?: any };
      return decoded.eventName === 'GameCreated';
    } catch { return false; }
  });
  if (gameCreatedLog) {
    const decoded = decodeEventLog({ abi, data: gameCreatedLog.data, topics: gameCreatedLog.topics }) as { args?: { gameId?: bigint } };
    gameId = decoded.args?.gameId ?? 1n;
  } else {
    const events = await publicClient.getContractEvents({ address, abi, eventName: 'GameCreated', fromBlock: 0n });
    gameId = events.length > 0 ? ((events[events.length - 1] as any).args?.gameId as bigint) ?? 1n : 1n;
  }
  console.log(`   🎮 Game ID: ${gameId}`);

  // Step 2: Player 2 joins
  console.log(`\n📝 Step 2: Player 2 joining game...`);
  const p2 = makeCommit(p2Move);
  const commitment2 = keccak256(encodePacked(['uint8','bytes32','bytes32'], [p2.move, p2.salt, p2.nonce]));
  console.log(`   Move: ${moveNames[p2.move]} (${p2.move})`);
  console.log(`   Commitment: ${commitment2}`);
  
  const gasOpts2 = await getGasOptions();
  const joinGas = await estimateGasWithBuffer(account2.address, 'joinGame', [gameId, commitment2], stakeAmount);
  const joinHash = await wallet2.writeContract({ address, abi, functionName: 'joinGame', args: [gameId, commitment2], value: stakeAmount, gas: joinGas, ...gasOpts2 });
  await publicClient.waitForTransactionReceipt({ hash: joinHash });
  console.log(`   ✅ Player 2 joined! TX: ${joinHash}`);
  p2Txs.push(joinHash as Hex);

  // Step 3: Both players reveal
  console.log(`\n📝 Step 3: Players revealing moves...`);
  
  console.log(`   Player 1 revealing ${moveNames[p1.move]}...`);
  const gasOpts3 = await getGasOptions();
  const reveal1Gas = await estimateGasWithBuffer(account1.address, 'reveal', [gameId, p1.move, p1.salt, p1.nonce]);
  const reveal1Hash = await wallet1.writeContract({ address, abi, functionName: 'reveal', args: [gameId, p1.move, p1.salt, p1.nonce], gas: reveal1Gas, ...gasOpts3 });
  await publicClient.waitForTransactionReceipt({ hash: reveal1Hash });
  console.log(`   ✅ Player 1 revealed! TX: ${reveal1Hash}`);
  p1Txs.push(reveal1Hash as Hex);
  
  console.log(`   Player 2 revealing ${moveNames[p2.move]}...`);
  const gasOpts4 = await getGasOptions();
  const reveal2Gas = await estimateGasWithBuffer(account2.address, 'reveal', [gameId, p2.move, p2.salt, p2.nonce]);
  const reveal2Hash = await wallet2.writeContract({ address, abi, functionName: 'reveal', args: [gameId, p2.move, p2.salt, p2.nonce], gas: reveal2Gas, ...gasOpts4 });
  await publicClient.waitForTransactionReceipt({ hash: reveal2Hash });
  console.log(`   ✅ Player 2 revealed! TX: ${reveal2Hash}`);
  p2Txs.push(reveal2Hash as Hex);

  // Wait a bit for any transfers to complete
  await new Promise(resolve => setTimeout(resolve, 1000));

  // Step 4: For tie scenario, Player 2 calls handleTie after expiration
  // First, check if this is a tie by checking moves (we know them from the test)
  const isTieFromMoves = (p1Move === p2Move);
  
  // Also check GameResolved event to confirm
  let isTieFromEvent = false;
  try {
    const events = await publicClient.getContractEvents({
      address,
      abi,
      eventName: 'GameResolved',
      fromBlock: 'earliest',
      args: { gameId }
    });
    
    if (events.length > 0) {
      const event = events[events.length - 1];
      const args = event.args as any;
      const winner = args.winner && args.winner !== '0x0000000000000000000000000000000000000000' ? args.winner : null;
      isTieFromEvent = !winner;
    }
  } catch (err) {
    // Continue anyway
  }
  
  const finalIsTie = isTieFromMoves || isTieFromEvent;
  
  // Read game state to get status and moves
  let game: any = null;
  let status: bigint = 0n;
  let move1 = p1Move;
  let move2 = p2Move;
  try {
    game = await publicClient.readContract({ address, abi, functionName: 'games', args: [gameId] });
    if (Array.isArray(game)) {
      status = BigInt(game[9] ?? 0);
      const revealsArray = game[4] as any;
      if (Array.isArray(revealsArray)) {
        move1 = Number(revealsArray[0]);
        move2 = Number(revealsArray[1]);
      }
    } else if (game && typeof game === 'object' && 'status' in game) {
      status = BigInt(game.status ?? 0);
      if (game.reveals && Array.isArray(game.reveals)) {
        move1 = Number(game.reveals[0]);
        move2 = Number(game.reveals[1]);
      }
    }
  } catch (err) {
    // Continue anyway
  }

  // Step 4: Handle tie scenario - Player 2 calls handleTie after expiration
  // Check if it's a tie (by moves) and status is TIE_RESOLUTION (2) or if it's a tie and we need to wait for status
  if (finalIsTie && (status === 2n || isTieFromMoves)) {
    console.log(`\n📝 Step 4: Player 2 calling handleTie after tie resolution deadline expiration...`);
    
    // Get tie resolution deadline from game
    let tieDeadline: bigint = 0n;
    if (game && Array.isArray(game)) {
      tieDeadline = BigInt(game[7] ?? 0); // tieResolutionDeadline is at index 7
    } else if (game && typeof game === 'object' && 'tieResolutionDeadline' in game) {
      tieDeadline = BigInt(game.tieResolutionDeadline ?? 0);
    }
    
    // Warp time forward past tie resolution deadline (only on Anvil),
    // otherwise wait in real time until on-chain time passes the deadline (Sepolia)
    if (isLocal) {
      const testClient = createTestClient({ mode: 'anvil', chain: foundry, transport: http(env.rpcUrl) });
      const currentBlock = await publicClient.getBlockNumber();
      const currentBlockData = await publicClient.getBlock({ blockNumber: currentBlock });
      const currentTimestamp = currentBlockData.timestamp;
      
      if (tieDeadline > 0n) {
        const timeToWarp = Number(tieDeadline - currentTimestamp) + 1; // 1 second past deadline
        if (timeToWarp > 0) {
          await testClient.increaseTime({ seconds: timeToWarp });
          await testClient.mine({ blocks: 1 });
        }
      } else {
        // Fallback: just increase by 2 minutes + 1 second
        await testClient.increaseTime({ seconds: 121 });
        await testClient.mine({ blocks: 1 });
      }
    } else {
      // On Sepolia: wait for real time to pass until the deadline
      if (tieDeadline > 0n) {
        console.log(`   ⏳ Waiting until on-chain time >= tieResolutionDeadline (${tieDeadline})...`);
        await waitUntilOnChainTime(tieDeadline, 15000);
        console.log(`   ✓ Tie deadline reached on-chain`);
      } else {
        // If we cannot read tieDeadline for some reason, wait a conservative 2 minutes
        console.log(`   ⚠️ tieResolutionDeadline unknown, waiting 2 minutes before handleTie...`);
        await sleep(120000);
      }
    }
    
    // Player 2 calls handleTie (after expiration on Anvil, or directly on Sepolia)
    const gasOpts6 = await getGasOptions();
    let handleTie2Hash: Hex | undefined;
    try {
      const handleTieGas = await estimateGasWithBuffer(account2.address, 'handleTie', [gameId, 2]);
      handleTie2Hash = await wallet2.writeContract({ address, abi, functionName: 'handleTie', args: [gameId, 2], gas: handleTieGas, ...gasOpts6 }); // 2 = SPLIT
      const receiptHT = await publicClient.waitForTransactionReceipt({ hash: handleTie2Hash });
      if (receiptHT.status !== 'success') {
        throw new Error(`handleTie failed on-chain (status=${receiptHT.status})`);
      }
      console.log(`   ✅ Player 2 called handleTie after deadline expiration`);
      console.log(`   TX: ${handleTie2Hash}`);
      p2Txs.push(handleTie2Hash as Hex);
      // On Anvil, force mine a block to ensure split is processed
      if (isLocal) {
        const testClient = createTestClient({ mode: 'anvil', chain: foundry, transport: http(env.rpcUrl) });
        await testClient.mine({ blocks: 1 });
      }
    } catch (err) {
      console.log(`   ❌ handleTie failed: ${String(err)}`);
      throw err;
    }
    
    // No additional waits; proceed to balance checks like in the win scenario
  }

  // Step 5: Check final game state and fund transfers
  console.log(`\n📝 Step 5: Checking final game state and fund transfers...`);
  
  // Read from GameResolved event
  const events = await publicClient.getContractEvents({
    address,
    abi,
    eventName: 'GameResolved',
    fromBlock: 'earliest',
    args: { gameId }
  });
  
  let winner: string | null = null;
  let isTie = false;
  
  if (events.length > 0) {
    const event = events[events.length - 1];
    const args = event.args as any;
    move1 = Number(args.move1 ?? move1);
    move2 = Number(args.move2 ?? move2);
    winner = args.winner && args.winner !== '0x0000000000000000000000000000000000000000' ? args.winner : null;
    isTie = !winner;
    console.log(`   ✓ Found GameResolved event`);
    console.log(`   Winner: ${winner || 'TIE'}`);
    console.log(`   Moves: ${moveNames[move1]} vs ${moveNames[move2]}`);
  }

  // Re-read game state to get latest status
  try {
    game = await publicClient.readContract({ address, abi, functionName: 'games', args: [gameId] });
    if (Array.isArray(game)) {
      const revealsArray = game[4] as any;
      if (Array.isArray(revealsArray)) {
        move1 = Number(revealsArray[0]);
        move2 = Number(revealsArray[1]);
      }
      status = BigInt(game[9] ?? 0);
    } else if (game && typeof game === 'object' && 'status' in game) {
      status = BigInt(game.status ?? 0);
      if (game.reveals && Array.isArray(game.reveals)) {
        move1 = Number(game.reveals[0]);
        move2 = Number(game.reveals[1]);
      }
    }
  } catch (err) {
    console.log(`   ⚠️  Could not read game state: ${err}`);
  }

  console.log(`   Revealed moves: ${moveNames[move1]} vs ${moveNames[move2]}`);
  console.log(`   Status: ${statusNames[Number(status)]} (${status})`);

  // Determine if winner or tie
  const isWinner = (move1 !== move2);
  const finalIsTieCheck = isTie || (move1 === move2);

  if (isWinner && status === 3n) {
    // Winner scenario - funds sent AUTOMATICALLY by contract
    console.log(`   💰 Funds sent AUTOMATICALLY by contract (no manual call needed)`);
    console.log(`   ✅ Winner received 0.002 ETH automatically after both reveals`);
  }

  // Check contract balance to see if funds were transferred out
  const contractBalance = await publicClient.getBalance({ address });
  console.log(`   Contract balance: ${contractBalance} wei (should be 0 if winner paid out)`);

  // Check final balances
  const balance1After: bigint = await publicClient.getBalance({ address: account1.address }) as unknown as bigint;
  const balance2After: bigint = await publicClient.getBalance({ address: account2.address }) as unknown as bigint;
  
  console.log(`\n💰 Final Balances:`);
  console.log(`   P1: ${balance1After} wei`);
  console.log(`   P2: ${balance2After} wei`);

  // Calculate balance changes (accounting for gas costs - approximate)
  const balance1Change: bigint = balance1After - balance1Before;
  const balance2Change: bigint = balance2After - balance2Before;
  
  // Expected outcomes
  // Note: Balance changes account for:
  // - Stakes paid (0.001 ETH each)
  // - Gas costs for all transactions (createGame, joinGame, reveal, handleTie if tie)
  // - Funds received (winner gets 0.002 ETH, tie gets 0.001 ETH each)
  
  const stakeWei = stakeAmount; // 0.001 ETH
  const minGas = parseEther('0.00005'); // Minimum expected gas (~0.00005 ETH)
  const maxGas = parseEther('0.002'); // Maximum expected gas (~0.002 ETH - very generous for multiple txns)
  
  if (isTie || move1 === move2) {
    // TIE Scenario:
    // Each player: paid 0.001 ETH stake + gas, received 0.001 ETH back
    // Net change from start: -gas costs only (should be negative, between -0.0015 and -0.001 ETH)
    console.log(`\n✅ TIE Scenario - Funds Split:`);
    console.log(`   P1 balance change (from start): ${balance1Change} wei (≈ ${prettyEth(balance1Change)} ETH)`);
    console.log(`   P2 balance change (from start): ${balance2Change} wei (≈ ${prettyEth(balance2Change)} ETH)`);
    if (!isLocal) console.log(`   Expected range: Negative between -0.0005 and -0.0002 ETH (gas costs only)`);
    console.log(`   (Both paid 0.001 ETH stake + gas, received 0.001 ETH back)`);
    
    // Assertions: Both should have negative balance changes (gas only)
    let tieMin: bigint;
    let tieMax: bigint;
    if (isLocal) {
      // On Anvil with zero fees, both should have exactly 0 change (paid 0.001, got 0.001 back)
      const p1ChangeETHStr = prettyEth(balance1Change);
      const p2ChangeETHStr = prettyEth(balance2Change);
      if (balance1Change === 0n && balance2Change === 0n) {
        console.log(`   ✅ Both players received their stakes back (balance changes reflect gas costs only)`);
        console.log(`   ✅ Assertion passed: P1=${p1ChangeETHStr} ETH, P2=${p2ChangeETHStr} ETH (both exactly 0)`);
      } else {
        console.log(`   ❌ Assertion FAILED: Expected exactly 0 on Anvil with zero fees`);
        console.log(`   ❌ P1=${p1ChangeETHStr} ETH (expected: 0)`);
        console.log(`   ❌ P2=${p2ChangeETHStr} ETH (expected: 0)`);
        throw new Error(`TIE balance assertion failed: P1=${balance1Change}, P2=${balance2Change}`);
      }
      return; // Skip Sepolia logic below
    } else {
      // Sepolia: compute dynamic ranges from actual gas fees (1.5x buffer)
      const p1GasTotal = await sumGasFeesWei(p1Txs);
      const p2GasTotal = await sumGasFeesWei(p2Txs);
      // Accept between -1.5x and -0.5x of observed total gas
      tieMin = -(p1GasTotal * 15n) / 10n; // -1.5x
      tieMax = -(p1GasTotal * 5n) / 10n;  // -0.5x
      const tieMinP2 = -(p2GasTotal * 15n) / 10n;
      const tieMaxP2 = -(p2GasTotal * 5n) / 10n;

      const p1ChangeETHStrDyn = prettyEth(balance1Change);
      const p2ChangeETHStrDyn = prettyEth(balance2Change);
      console.log(`   Sepolia gas totals: P1≈ ${prettyEth(p1GasTotal)} ETH, P2≈ ${prettyEth(p2GasTotal)} ETH`);
      console.log(`   Dynamic expected P1 range: ${prettyEth(tieMin)} to ${prettyEth(tieMax)} ETH`);
      console.log(`   Dynamic expected P2 range: ${prettyEth(tieMinP2)} to ${prettyEth(tieMaxP2)} ETH`);

      // Validate P2 with its own bounds too; if either fails, we fall through to error path
      const p2InRange = balance2Change >= tieMinP2 && balance2Change <= tieMaxP2;
      const p1InRange = balance1Change >= tieMin && balance1Change <= tieMax;
      if (p1InRange && p2InRange) {
        console.log(`   ✅ Both players received their stakes back (gas-only deltas within dynamic ranges)`);
        console.log(`   ✅ Assertion passed: P1=${p1ChangeETHStrDyn} ETH, P2=${p2ChangeETHStrDyn} ETH`);
      } else {
        console.log(`   ❌ Assertion FAILED (dynamic ranges)`);
        console.log(`   ❌ P1=${p1ChangeETHStrDyn} ETH (expected: ${prettyEth(tieMin)} to ${prettyEth(tieMax)})`);
        console.log(`   ❌ P2=${p2ChangeETHStrDyn} ETH (expected: ${prettyEth(tieMinP2)} to ${prettyEth(tieMaxP2)})`);
        throw new Error(`TIE balance assertion failed: P1=${balance1Change}, P2=${balance2Change}`);
      }
      // We fully handled Sepolia case above; skip the static Anvil check path
      return;
    }
    
    const p1ChangeETHStr = prettyEth(balance1Change);
    const p2ChangeETHStr = prettyEth(balance2Change);
    
    if (balance1Change >= tieMin && balance1Change <= tieMax && 
        balance2Change >= tieMin && balance2Change <= tieMax) {
      console.log(`   ✅ Both players received their stakes back (balance changes reflect gas costs only)`);
      console.log(`   ✅ Assertion passed: P1=${p1ChangeETHStr} ETH, P2=${p2ChangeETHStr} ETH (both negative, within range)`);
    } else {
      console.log(`   ❌ Assertion FAILED: Balance changes outside expected range`);
      console.log(`   ❌ P1=${p1ChangeETHStr} ETH (expected: -0.0005 to -0.0002)`);
      console.log(`   ❌ P2=${p2ChangeETHStr} ETH (expected: -0.0005 to -0.0002)`);
      throw new Error(`TIE balance assertion failed: P1=${balance1Change}, P2=${balance2Change}`);
    }
  } else {
    // WIN Scenario:
    // Winner: paid 0.001 ETH stake + gas, received 0.002 ETH (both stakes)
    // Net change: +0.001 ETH - gas (should be positive, between 0.0003 and 0.001 ETH)
    // Loser: paid 0.001 ETH stake + gas, received 0 ETH
    // Net change: -0.001 ETH - gas (should be negative, between -0.0025 and -0.001 ETH)
    const isPlayer1Winner = (move1 === 0 && move2 === 2) || (move1 === 1 && move2 === 0) || (move1 === 2 && move2 === 1);
    const expectedWinner = isPlayer1Winner ? 'Player 1' : 'Player 2';
    
    console.log(`\n✅ WIN Scenario - ${expectedWinner} Wins:`);
    console.log(`   P1 balance change: ${balance1Change} wei (≈ ${prettyEth(balance1Change)} ETH)`);
    console.log(`   P2 balance change: ${balance2Change} wei (≈ ${prettyEth(balance2Change)} ETH)`);
    
    if (isPlayer1Winner) {
      // Player 1: Paid 0.001 + gas, received 0.002 → Net: +0.001 - gas
      // Expected (Sepolia): positive, between 0.0006 and 0.001 ETH
      // Player 2: Paid 0.001 + gas, received 0 → Net: -0.001 - gas
      // Expected (Sepolia): negative, between -0.0015 and -0.001 ETH
      if (isLocal) {
        const p1Exact = parseEther('0.001');
        const p2Exact = parseEther('-0.001');
        const p1ChangeETHStr = prettyEth(balance1Change);
        const p2ChangeETHStr = prettyEth(balance2Change);
        if (balance1Change === p1Exact && balance2Change === p2Exact) {
          console.log(`   ✅ Player 1 received winnings (${p1ChangeETHStr} ETH)`);
          console.log(`   ✅ Player 2 lost stake (${p2ChangeETHStr} ETH)`);
          console.log(`   ✅ Assertion passed: Exact zero-fee values`);
        } else {
          console.log(`   ❌ Assertion FAILED: Expected exact +0.001/-0.001 on Anvil`);
          console.log(`   ❌ P1=${p1ChangeETHStr} ETH (expected: 0.001)`);
          console.log(`   ❌ P2=${p2ChangeETHStr} ETH (expected: -0.001)`);
          throw new Error(`WIN balance assertion failed: P1=${balance1Change}, P2=${balance2Change}`);
        }
        return;
      }
      const winnerMin = parseEther('0.0006'); // Minimum winner gain
      const winnerMax = parseEther('0.001'); // Maximum winner gain
      const loserMin = parseEther('-0.0015'); // Minimum loser loss
      const loserMax = parseEther('-0.001'); // Maximum loser loss
      
      console.log(`   Expected P1 (winner): Positive between 0.0006 and 0.001 ETH`);
      console.log(`   Expected P2 (loser): Negative between -0.0015 and -0.001 ETH`);
      
      const p1ChangeETHStr = prettyEth(balance1Change);
      const p2ChangeETHStr = prettyEth(balance2Change);
      
      if (balance1Change >= winnerMin && balance1Change <= winnerMax && 
          balance2Change >= loserMin && balance2Change <= loserMax) {
        console.log(`   ✅ Player 1 received winnings (${p1ChangeETHStr} ETH)`);
        console.log(`   ✅ Player 2 lost stake (${p2ChangeETHStr} ETH)`);
        console.log(`   ✅ Assertion passed: Values within expected ranges`);
      } else {
        console.log(`   ❌ Assertion FAILED: Balance changes outside expected range`);
        console.log(`   ❌ P1=${p1ChangeETHStr} ETH (expected: 0.0006 to 0.001)`);
        console.log(`   ❌ P2=${p2ChangeETHStr} ETH (expected: -0.0015 to -0.001)`);
        throw new Error(`WIN balance assertion failed: P1=${balance1Change}, P2=${balance2Change}`);
      }
    } else {
      // Player 2 wins
      if (isLocal) {
        const p2Exact = parseEther('0.001');
        const p1Exact = parseEther('-0.001');
        const p1ChangeETHStr = prettyEth(balance1Change);
        const p2ChangeETHStr = prettyEth(balance2Change);
        if (balance2Change === p2Exact && balance1Change === p1Exact) {
          console.log(`   ✅ Player 2 received winnings (${p2ChangeETHStr} ETH)`);
          console.log(`   ✅ Player 1 lost stake (${p1ChangeETHStr} ETH)`);
          console.log(`   ✅ Assertion passed: Exact zero-fee values`);
        } else {
          console.log(`   ❌ Assertion FAILED: Expected exact +0.001/-0.001 on Anvil`);
          console.log(`   ❌ P1=${p1ChangeETHStr} ETH (expected: -0.001)`);
          console.log(`   ❌ P2=${p2ChangeETHStr} ETH (expected: 0.001)`);
          throw new Error(`WIN balance assertion failed: P1=${balance1Change}, P2=${balance2Change}`);
        }
        return;
      }
      const winnerMin = parseEther('0.0007'); // Minimum winner gain
      const winnerMax = parseEther('0.001'); // Maximum winner gain
      const loserMin = parseEther('-0.0015'); // Minimum loser loss
      const loserMax = parseEther('-0.001'); // Maximum loser loss
      
      console.log(`   Expected P1 (loser): Negative between -0.0015 and -0.001 ETH`);
      console.log(`   Expected P2 (winner): Positive between 0.0007 and 0.001 ETH`);
      
      const p1ChangeETHStr = prettyEth(balance1Change);
      const p2ChangeETHStr = prettyEth(balance2Change);
      
      if (balance2Change >= winnerMin && balance2Change <= winnerMax && 
          balance1Change >= loserMin && balance1Change <= loserMax) {
        console.log(`   ✅ Player 2 received winnings (${p2ChangeETHStr} ETH)`);
        console.log(`   ✅ Player 1 lost stake (${p1ChangeETHStr} ETH)`);
        console.log(`   ✅ Assertion passed: Values within expected ranges`);
      } else {
        console.log(`   ❌ Assertion FAILED: Balance changes outside expected range`);
        console.log(`   ❌ P1=${p1ChangeETHStr} ETH (expected: -0.0015 to -0.001)`);
        console.log(`   ❌ P2=${p2ChangeETHStr} ETH (expected: 0.0007 to 0.001)`);
        throw new Error(`WIN balance assertion failed: P1=${balance1Change}, P2=${balance2Change}`);
      }
    }
  }

  console.log(`\n✅ === Test PASSED ===`);
  console.log(`   Scenario completed successfully`);
  console.log(`\n`);
}

async function main() {
  const envArg = process.argv.find(arg => arg.startsWith('--env='))?.split('=')[1] ||
                 (process.argv.includes('--env') ? process.argv[process.argv.indexOf('--env') + 1] : undefined);
  
  const env = loadEnv(envArg);
  const envName = env.isLocal ? 'anvil' : 'sepolia';
  await startLogging('run_viem', envName);
  
  if (!env.isLocal && !env.contractAddress) {
    throw new Error('CONTRACT_ADDRESS must be set in .env when running tests on Sepolia');
  }
  
  /*
   * How fund transfers work:
   * 1. Players pay GAS for all transactions (createGame, joinGame, reveal, handleTie)
   * 2. Contract receives ETH from stakes:
   *    - createGame: Player 1 sends 0.001 ETH → contract balance +0.001 ETH
   *    - joinGame: Player 2 sends 0.001 ETH → contract balance +0.001 ETH
   *    - Total in contract: 0.002 ETH
   * 3. Contract sends funds back using .call{value: amount}(""):
   *    - Winner: gets 0.002 ETH (both stakes)
   *    - Tie split: each player gets 0.001 ETH (their stake back)
   * 4. Contract does NOT need extra ETH for gas - only needs the staked ETH to send back
   */
  
  const { publicClient, walletClient: wallet1, account: account1, isLocal } = await makeClients(env, false);
  const { walletClient: wallet2, account: account2 } = env.privateKey2 ? await makeClients(env, true) : { walletClient: wallet1, account: account1 };
  
  // Fund accounts on Anvil
  if (isLocal) {
    const testClient = createTestClient({ mode: 'anvil', chain: foundry, transport: http(env.rpcUrl) });
    // Force zero-fee locally to make assertions exact
    try {
      await (publicClient as any).request({ method: 'anvil_setNextBlockBaseFeePerGas', params: ['0x0'] });
    } catch {}
    try {
      await (publicClient as any).request({ method: 'anvil_setMinGasPrice', params: ['0x0'] });
    } catch {}
    try {
      // Mine a block so new settings take effect
      await testClient.mine({ blocks: 1 });
    } catch {}
    
    const balance1 = await publicClient.getBalance({ address: account1.address });
    if (balance1 < parseEther('1')) {
      console.log(`Funding ${account1.address} with 100 ETH on Anvil...`);
      await testClient.setBalance({ address: account1.address, value: parseEther('100') });
    }
    
    if (env.privateKey2) {
      const balance2 = await publicClient.getBalance({ address: account2.address });
      if (balance2 < parseEther('1')) {
        console.log(`Funding ${account2.address} with 100 ETH on Anvil...`);
        await testClient.setBalance({ address: account2.address, value: parseEther('100') });
      }
    }
  } else {
    const balance1 = await publicClient.getBalance({ address: account1.address });
    const minBalance = parseEther('0.01');
    if (balance1 < minBalance) {
      throw new Error(`Insufficient Sepolia ETH. ${account1.address} has ${balance1} wei. Need at least ${minBalance} wei.`);
    }
  }
  
  // Get or deploy contract
  let address: Hex;
  if (env.contractAddress) {
    if (isLocal) {
      const code = await publicClient.getBytecode({ address: env.contractAddress });
      if (!code || code === '0x') {
        console.log(`⚠️  CONTRACT_ADDRESS in .env (${env.contractAddress}) has no code on Anvil.`);
        console.log(`   This likely means Anvil was restarted. Deploying new contract...`);
        address = await deployContract(wallet1, publicClient, isLocal);
      } else {
        address = env.contractAddress;
        console.log(`✓ Using existing contract from .env: ${address}`);
      }
    } else {
      address = env.contractAddress;
      console.log(`✓ Using contract from .env: ${address}`);
    }
  } else {
    address = await deployContract(wallet1, publicClient, isLocal);
  }
  
  const { abi } = await getDeployedContract(address as Hex);

  console.log(`\n🧪 === E2E Test Suite ===`);
  console.log(`📡 Network: ${env.isLocal ? 'Anvil (Local)' : 'Sepolia'}`);
  console.log(`📍 Contract: ${address}`);
  console.log(`👤 Player 1: ${account1.address}`);
  console.log(`👤 Player 2: ${account2.address}`);

  // Test 1: ROCK vs SCISSORS (Player 1 wins)
  await runGameScenario(
    publicClient, wallet1, wallet2, account1, account2, address, abi,
    0, // ROCK
    2, // SCISSORS
    'Test 1: ROCK vs SCISSORS (Player 1 Wins)',
    isLocal,
    env
  );

  // Test 2: PAPER vs PAPER (Tie)
  await runGameScenario(
    publicClient, wallet1, wallet2, account1, account2, address, abi,
    1, // PAPER
    1, // PAPER
    'Test 2: PAPER vs PAPER (Tie - Split Funds)',
    isLocal,
    env
  );

  console.log(`\n🎉 All tests completed!\n`);
  await stopLogging();
}

async function deployContract(walletClient: any, publicClient: any, isLocal: boolean): Promise<Hex> {
  console.log(`\n📦 Deploying contract...`);
  const fs = await import('fs/promises');
  const path = await import('path');
  const jsonPath = path.join(process.cwd(), 'out', 'RockPaperScissors.sol', 'RockPaperScissors.json');
  const jsonContent = await fs.readFile(jsonPath, 'utf-8');
  const abiJson = JSON.parse(jsonContent);
  const abi = abiJson.abi;
  
  const bytecode = (abiJson.bytecode?.object || abiJson.bytecode) as Hex;
  if (!bytecode || bytecode === '0x') {
    throw new Error('Bytecode not found. Run `forge build` first.');
  }
  
  const gasOpts = isLocal ? {} : { gasPrice: ((await publicClient.getGasPrice()) * 120n) / 100n };
  
  const hash = await walletClient.deployContract({ abi, bytecode, ...gasOpts });
  console.log(`   Deployment TX: ${hash}`);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (!receipt.contractAddress) throw new Error('Deployment failed: no contract address');
  console.log(`   ✅ Contract deployed at: ${receipt.contractAddress}\n`);
  return receipt.contractAddress;
}

main().catch(async (e) => { 
  console.error(e); 
  await stopLogging().catch(() => {});
  process.exit(1); 
});
