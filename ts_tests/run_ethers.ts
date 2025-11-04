import { loadEnv, getDeployedContract, makeCommit } from './client/utils.js';
import { formatEther, parseEther, keccak256, solidityPacked, toUtf8Bytes } from 'ethers';
import { JsonRpcProvider, Wallet, Contract, Interface, ContractFactory, NonceManager } from 'ethers';
import fs from 'fs/promises';
import path from 'path';
import { startLogging, stopLogging } from './reportLogger.js';

type Hex = `0x${string}`;

function sleep(ms: number) { return new Promise((r) => setTimeout(r, ms)); }

function prettyEth(wei: bigint): string {
  const s = formatEther(wei);
  return s.includes('.') ? s.replace(/\.0+$/, '').replace(/(\.\d*?)0+$/, '$1') : s;
}

async function getFees(provider: JsonRpcProvider, isLocal: boolean = false) {
  if (isLocal) return { gasPrice: 0n } as const; // Force zero-fee on Anvil
  const fee = await provider.getFeeData();
  const maxFeePerGas = fee.maxFeePerGas ? (fee.maxFeePerGas * 13n) / 10n : undefined; // 1.3x for Sepolia
  const maxPriorityFeePerGas = fee.maxPriorityFeePerGas ? (fee.maxPriorityFeePerGas * 13n) / 10n : undefined; // 1.3x for Sepolia
  return { maxFeePerGas, maxPriorityFeePerGas } as const;
}

async function estimateWithBuffer(contract: any, method: string, args: any[], value?: bigint, isLocal: boolean = false): Promise<bigint | undefined> {
  try {
    const estObj = (contract as any).estimateGas;
    const estFn = estObj ? estObj[method] : undefined;
    if (typeof estFn !== 'function') {
      // No estimator available (ethers v6 typing/ABI mismatch)
      // On Anvil, return a safe fallback; on Sepolia, provide a conservative cap to avoid OOG
      return isLocal ? 1_500_000n : 300_000n;
    }
    const gas: bigint = await estFn(...args, { value });
    // Only apply 1.3x buffer on Sepolia (not Anvil)
    return isLocal ? gas : (gas * 13n) / 10n;
  } catch (err) {
    // On Anvil, estimation can fail; use conservative fallback
    if (isLocal) {
      return 1_500_000n; // Conservative default for Anvil
    }
    // On Sepolia, provide a conservative cap to avoid OOG
    return 300_000n;
  }
}

async function runScenario(provider: JsonRpcProvider, w1: any, w2: any, address: Hex, abi: any, isLocal: boolean, scenarioName: string, p1Move: number, p2Move: number, env: any) {
  const iface = new Interface(abi);
  const rps = new Contract(address, abi, provider);
  const c1 = rps.connect(w1);
  const c2 = rps.connect(w2);

  const moveNames = ['ROCK','PAPER','SCISSORS'];
  const stakeAmount = parseEther('0.001');

  const p1Txs: Hex[] = [];
  const p2Txs: Hex[] = [];

  console.log(`\n${'='.repeat(60)}`);
  console.log(`🧪 ${scenarioName}`);
  console.log(`${'='.repeat(60)}`);

  const addr1 = await w1.getAddress();
  const addr2 = await w2.getAddress();
  const b1Before = await provider.getBalance(addr1);
  const b2Before = await provider.getBalance(addr2);
  console.log(`💰 Initial Balances:`);
  console.log(`   P1: ${b1Before} wei`);
  console.log(`   P2: ${b2Before} wei`);

  // Create commitment
  const p1 = makeCommit(p1Move);
  const commitment1 = keccak256(solidityPacked(['uint8','bytes32','bytes32'], [p1.move, p1.salt, p1.nonce] as any));

  // createGame
  const f1 = await getFees(provider, isLocal);
  const gasCreate = await estimateWithBuffer(c1, 'createGame', [commitment1], stakeAmount, isLocal);
  const txCreate = await (c1 as any).createGame(commitment1, { value: stakeAmount, gasLimit: gasCreate, ...f1 });
  const rcCreate = await txCreate.wait();
  p1Txs.push(txCreate.hash as Hex);
  console.log(`   ✅ Game created! TX: ${txCreate.hash}`);

  // Get gameId from logs
  let gameId = 1n;
  for (const log of rcCreate!.logs) {
    try {
      const parsed = iface.parseLog(log);
      if (parsed?.name === 'GameCreated') {
        gameId = BigInt(parsed.args.gameId.toString());
      }
    } catch {}
  }
  console.log(`   🎮 Game ID: ${gameId}`);

  // Player 2 join
  const p2 = makeCommit(p2Move);
  const commitment2 = keccak256(solidityPacked(['uint8','bytes32','bytes32'], [p2.move, p2.salt, p2.nonce] as any));
  const f2 = await getFees(provider, isLocal);
  const gasJoin = await estimateWithBuffer(c2, 'joinGame', [gameId, commitment2], stakeAmount, isLocal);
  const txJoin = await (c2 as any).joinGame(gameId, commitment2, { value: stakeAmount, gasLimit: gasJoin, ...f2 });
  await txJoin.wait();
  p2Txs.push(txJoin.hash as Hex);
  console.log(`   ✅ Player 2 joined! TX: ${txJoin.hash}`);

  // Reveals
  const f3 = await getFees(provider, isLocal);
  const gasRev1 = await estimateWithBuffer(c1, 'reveal', [gameId, p1.move, p1.salt, p1.nonce], undefined, isLocal);
  const txRev1 = await (c1 as any).reveal(gameId, p1.move, p1.salt, p1.nonce, { gasLimit: gasRev1, ...f3 });
  await txRev1.wait();
  p1Txs.push(txRev1.hash as Hex);
  console.log(`   ✅ Player 1 revealed! TX: ${txRev1.hash}`);

  const f4 = await getFees(provider, isLocal);
  const gasRev2 = await estimateWithBuffer(c2, 'reveal', [gameId, p2.move, p2.salt, p2.nonce], undefined, isLocal);
  const txRev2 = await (c2 as any).reveal(gameId, p2.move, p2.salt, p2.nonce, { gasLimit: gasRev2, ...f4 });
  await txRev2.wait();
  p2Txs.push(txRev2.hash as Hex);
  console.log(`   ✅ Player 2 revealed! TX: ${txRev2.hash}`);

  // Wait a bit for any automatic transfers to complete
  await sleep(1000);

  // Read GameResolved event for this gameId
  const gameResolvedTopic = keccak256(toUtf8Bytes('GameResolved(uint256,address,uint8,uint8)'));
  const gameIdPadded = '0x' + gameId.toString(16).padStart(64, '0');
  const filter = { address, topics: [gameResolvedTopic, gameIdPadded, null, null] } as const;
  const logs = await provider.getLogs({ ...(filter as any), fromBlock: 0 });
  let isTie = false;
  if (logs.length > 0) {
    try {
      const parsed = iface.parseLog(logs[logs.length - 1]);
      const winner = (parsed as any).args.winner as string;
      isTie = /^0x0{40}$/i.test(winner);
      console.log(`   ✓ Found GameResolved event (winner: ${winner === '0x0000000000000000000000000000000000000000' ? 'TIE' : winner})`);
    } catch (err) {
      console.log(`   ⚠️  Could not parse GameResolved event: ${err}`);
    }
  }

  // If tie, handleTie with SPLIT choice (2) after deadline
  if (isTie) {
    console.log(`\n📝 Step 4: Player 2 calling handleTie after tie deadline...`);

    // Ensure on-chain time has passed the tieResolutionDeadline
    if (isLocal) {
      try {
        const game = await (rps.connect(w1) as any).getGame(gameId);
        const deadline: bigint = BigInt(game.tieResolutionDeadline?.toString?.() ?? game[7]?.toString?.() ?? '0');
        if (deadline > 0n) {
          const latest = await provider.getBlock('latest');
          const nowTs = BigInt((latest?.timestamp ?? 0).toString());
          const secondsToWarp = deadline > nowTs ? (deadline - nowTs + 1n) : 0n;
          if (secondsToWarp > 0n) {
            await provider.send('evm_increaseTime', [Number(secondsToWarp)]);
            await provider.send('evm_mine', []);
          }
        }
      } catch {}
    } else {
      try {
        const game = await (rps.connect(w1) as any).getGame(gameId);
        const deadline: bigint = BigInt(game.tieResolutionDeadline?.toString?.() ?? game[7]?.toString?.() ?? '0');
        if (deadline > 0n) {
          const buffer = 2n;
          console.log(`   ⏳ Waiting until on-chain time >= tieResolutionDeadline (${deadline}) (up to ~2 min)...`);
          // Poll until latest block timestamp >= deadline
          while (true) {
            const latest = await provider.getBlock('latest');
            const nowTs = BigInt((latest?.timestamp ?? 0).toString());
            if (nowTs + buffer >= deadline) break;
            await sleep(15000);
          }
          console.log(`   ✓ Tie deadline reached on-chain`);
        } else {
          // No deadline available – conservative wait
          console.log(`   ⚠️ tieResolutionDeadline unknown, waiting 2 minutes before handleTie...`);
          await sleep(120000);
        }
      } catch {}
    }

    const f5 = await getFees(provider, isLocal);
    const gasHT = await estimateWithBuffer(c2, 'handleTie', [gameId, 2], undefined, isLocal);
    const txHT = await (c2 as any).handleTie(gameId, 2, { gasLimit: gasHT, ...f5 });
    const receiptHT = await txHT.wait();
    if (receiptHT && receiptHT.status !== 1) {
      throw new Error(`handleTie transaction failed with status ${receiptHT.status}`);
    }
    p2Txs.push(txHT.hash as Hex);
    console.log(`   ✅ Player 2 called handleTie. TX: ${txHT.hash}`);
    // Wait for resolution to be indexed
    if (isLocal) {
      try { await provider.send('evm_mine', []); } catch {}
    } else {
      // Poll for GameResolved again for this gameId
      const topic = keccak256(toUtf8Bytes('GameResolved(uint256,address,uint8,uint8)'));
      const gameIdPadded = '0x' + gameId.toString(16).padStart(64, '0');
      const filter2 = { address, topics: [topic, gameIdPadded, null, null] } as const;
      const start = Date.now();
      console.log(`   ⏳ Waiting up to 2 minutes for GameResolved to be indexed...`);
      while (Date.now() - start < 120000) {
        const logs2 = await provider.getLogs({ ...(filter2 as any), fromBlock: 0 });
        if (logs2.length > 0) break;
        await sleep(10000);
      }
    }
  }

  // Small wait for balance updates (especially on Anvil)
  await sleep(500);

  // Final balances
  const b1After = await provider.getBalance(addr1);
  const b2After = await provider.getBalance(addr2);
  const d1 = b1After - b1Before;
  const d2 = b2After - b2Before;

  console.log(`\n💰 Final Balances:`);
  console.log(`   P1: ${b1After} wei`);
  console.log(`   P2: ${b2After} wei`);

  // Assertions similar to viem runner
  if (isTie) {
    console.log(`\n✅ TIE Scenario - Funds Split:`);
    console.log(`   P1 balance change (from start): ${d1} wei (≈ ${prettyEth(d1)} ETH)`);
    console.log(`   P2 balance change (from start): ${d2} wei (≈ ${prettyEth(d2)} ETH)`);

    // Dynamic gas-based bounds on non-local networks
    if (!isLocal) {
      // Sum actual gas paid per player
      let totalGasP1 = 0n;
      for (const h of p1Txs) {
        const r = await provider.getTransactionReceipt(h);
        if (!r) continue;
        const tx = await provider.getTransaction(h);
        const price = (r as any).effectiveGasPrice ?? tx?.gasPrice ?? 0n;
        totalGasP1 += r.gasUsed * price;
      }
      let totalGasP2 = 0n;
      for (const h of p2Txs) {
        const r = await provider.getTransactionReceipt(h);
        if (!r) continue;
        const tx = await provider.getTransaction(h);
        const price = (r as any).effectiveGasPrice ?? tx?.gasPrice ?? 0n;
        totalGasP2 += r.gasUsed * price;
      }

      const minP1 = -(totalGasP1 * 15n) / 10n;
      const maxP1 = -(totalGasP1 * 5n) / 10n;
      const minP2 = -(totalGasP2 * 15n) / 10n;
      const maxP2 = -(totalGasP2 * 5n) / 10n;
      console.log(`   Sepolia gas totals: P1≈ ${prettyEth(totalGasP1)} ETH, P2≈ ${prettyEth(totalGasP2)} ETH`);
      console.log(`   Dynamic expected P1 range: ${prettyEth(minP1)} to ${prettyEth(maxP1)} ETH`);
      console.log(`   Dynamic expected P2 range: ${prettyEth(minP2)} to ${prettyEth(maxP2)} ETH`);

      if (d1 >= minP1 && d1 <= maxP1 && d2 >= minP2 && d2 <= maxP2) {
        console.log(`   ✅ Assertion passed: Sepolia dynamic gas ranges`);
      } else {
        throw new Error(`TIE balance assertion failed: P1=${d1}, P2=${d2}`);
      }
    } else {
      // On Anvil with zero fees, both should have exactly 0 change (paid 0.001, got 0.001 back)
      if (d1 === 0n && d2 === 0n) {
        console.log(`   ✅ Assertion passed: Anvil zero-fee exact match (both 0)`);
      } else {
        console.log(`   ❌ Assertion FAILED: Expected exactly 0 on Anvil with zero fees`);
        console.log(`   ❌ P1=${prettyEth(d1)} ETH (expected: 0)`);
        console.log(`   ❌ P2=${prettyEth(d2)} ETH (expected: 0)`);
        throw new Error(`TIE balance assertion failed (Anvil): P1=${d1}, P2=${d2}`);
      }
    }
  } else {
    // Win scenario: mirror the viem test ranges
    const isPlayer1Winner = (p1Move === 0 && p2Move === 2) || (p1Move === 1 && p2Move === 0) || (p1Move === 2 && p2Move === 1);
    console.log(`\n✅ WIN Scenario - ${isPlayer1Winner ? 'Player 1' : 'Player 2'} Wins:`);
    console.log(`   P1 balance change: ${d1} wei (≈ ${prettyEth(d1)} ETH)`);
    console.log(`   P2 balance change: ${d2} wei (≈ ${prettyEth(d2)} ETH)`);
    if (isPlayer1Winner) {
      const winnerMin = parseEther('0.0006');
      const winnerMax = parseEther('0.001');
      const loserMin = parseEther('-0.0015');
      const loserMax = parseEther('-0.001');
      console.log(`   Expected P1 (winner): Positive between 0.0006 and 0.001 ETH`);
      console.log(`   Expected P2 (loser): Negative between -0.0015 and -0.001 ETH`);
      if (d1 >= winnerMin && d1 <= winnerMax && d2 >= loserMin && d2 <= loserMax) {
        console.log(`   ✅ Assertion passed: Values within expected ranges`);
      } else {
        console.log(`   ❌ Assertion FAILED: Balance changes outside expected range`);
        console.log(`   ❌ P1=${prettyEth(d1)} ETH (expected: 0.0006 to 0.001)`);
        console.log(`   ❌ P2=${prettyEth(d2)} ETH (expected: -0.0015 to -0.001)`);
        throw new Error(`WIN balance assertion failed: P1=${d1}, P2=${d2}`);
      }
    } else {
      const winnerMin = parseEther('0.0007');
      const winnerMax = parseEther('0.001');
      const loserMin = parseEther('-0.0015');
      const loserMax = parseEther('-0.001');
      console.log(`   Expected P1 (loser): Negative between -0.0015 and -0.001 ETH`);
      console.log(`   Expected P2 (winner): Positive between 0.0007 and 0.001 ETH`);
      if (d2 >= winnerMin && d2 <= winnerMax && d1 >= loserMin && d1 <= loserMax) {
        console.log(`   ✅ Assertion passed: Values within expected ranges`);
      } else {
        console.log(`   ❌ Assertion FAILED: Balance changes outside expected range`);
        console.log(`   ❌ P1=${prettyEth(d1)} ETH (expected: -0.0015 to -0.001)`);
        console.log(`   ❌ P2=${prettyEth(d2)} ETH (expected: 0.0007 to 0.001)`);
        throw new Error(`WIN balance assertion failed: P1=${d1}, P2=${d2}`);
      }
    }
  }

  console.log(`\n✅ === Test PASSED ===`);
  console.log(`   Scenario completed successfully`);
}

async function main() {
  const envArg = process.argv.find(a => a.startsWith('--env='))?.split('=')[1] || (process.argv.includes('--env') ? process.argv[process.argv.indexOf('--env') + 1] : undefined);
  const env = loadEnv(envArg);
  const envName = env.isLocal ? 'anvil' : 'sepolia';
  await startLogging('run_ethers', envName);

  const provider = new JsonRpcProvider(env.rpcUrl);
  const w1 = new Wallet(env.privateKey, provider);
  const w2 = new Wallet(env.privateKey2 || env.privateKey, provider);
  // Wrap with NonceManager to avoid nonce-too-low on fast sequences
  const s1 = new NonceManager(w1);
  const s2 = new NonceManager(w2);

  // Fund accounts on Anvil so gas * price + value succeeds
  if (env.isLocal) {
    // Force zero-fee locally to make assertions exact
    try { await provider.send('anvil_setNextBlockBaseFeePerGas', ['0x0']); } catch {}
    try { await provider.send('anvil_setMinGasPrice', ['0x0']); } catch {}
    try { await provider.send('evm_mine', []); } catch {}
    const target = parseEther('100');
    const toHex = (v: bigint) => '0x' + v.toString(16);
    const b1 = await provider.getBalance(w1.address);
    if (b1 < target) {
      console.log(`Funding ${w1.address} with 100 ETH on Anvil...`);
      await provider.send('anvil_setBalance', [w1.address, toHex(target)]);
    }
    if (w2.address.toLowerCase() !== w1.address.toLowerCase()) {
      const b2 = await provider.getBalance(w2.address);
      if (b2 < target) {
        console.log(`Funding ${w2.address} with 100 ETH on Anvil...`);
        await provider.send('anvil_setBalance', [w2.address, toHex(target)]);
      }
    }
  }

  // Resolve contract address & abi: deploy on Anvil if needed
  let address: Hex | undefined = env.contractAddress as Hex | undefined;
  let abi: any | undefined;
  
  if (env.isLocal) {
    if (address) {
      const code = await provider.getCode(address);
      if (!code || code === '0x') address = undefined;
    }
    if (!address) {
      console.log(`\n📦 Deploying contract (ethers)...`);
      const jsonPath = path.join(process.cwd(), 'out', 'RockPaperScissors.sol', 'RockPaperScissors.json');
      const jsonContent = await fs.readFile(jsonPath, 'utf-8');
      const artifact = JSON.parse(jsonContent);
      abi = artifact.abi;
      const bytecode: Hex = (artifact.bytecode?.object || artifact.bytecode) as Hex;
      if (!bytecode || bytecode === '0x') throw new Error('Bytecode not found. Run `forge build` first.');
      const feesData = await provider.getFeeData();
      // No 1.3x multiplier on Anvil - use estimated fees directly
      const maxFeePerGas = feesData.maxFeePerGas ?? undefined;
      const maxPriorityFeePerGas = feesData.maxPriorityFeePerGas ?? undefined;
      const gasPrice = feesData.gasPrice ?? undefined;
      const factory = new ContractFactory(abi, bytecode, s1);
      let contract;
      try {
        contract = await factory.deploy({ maxFeePerGas, maxPriorityFeePerGas });
      } catch {
        // Retry with legacy gasPrice and conservative gasLimit on Anvil
        contract = await factory.deploy({ gasPrice: gasPrice ?? 1_000_000_000n, gasLimit: 3_500_000n });
      }
      await contract.waitForDeployment();
      address = (await contract.getAddress()) as Hex;
      console.log(`   ✅ Contract deployed at: ${address}`);
    }
    if (!abi) {
      const deployed = await getDeployedContract(address as Hex);
      abi = deployed.abi;
    }
  } else {
    if (!env.contractAddress) throw new Error('CONTRACT_ADDRESS must be set in .env when running tests on Sepolia');
    address = env.contractAddress as Hex;
    const deployed = await getDeployedContract(address);
    abi = deployed.abi;
  }

  console.log(`\n🧪 === E2E Test Suite (ethers) ===`);
  console.log(`📡 Network: ${env.isLocal ? 'Anvil (Local)' : 'Sepolia'}`);
  console.log(`📍 Contract: ${address}`);
  console.log(`👤 Player 1: ${w1.address}`);
  console.log(`👤 Player 2: ${w2.address}`);

  // Test 1: ROCK vs SCISSORS (Player 1 wins)
  await runScenario(provider, s1 as unknown as Wallet, s2 as unknown as Wallet, address as Hex, abi, env.isLocal, 'Test 1: ROCK vs SCISSORS (Player 1 Wins)', 0, 2, env);
  // Test 2: PAPER vs PAPER (Tie Split)
  await runScenario(provider, s1 as unknown as Wallet, s2 as unknown as Wallet, address as Hex, abi, env.isLocal, 'Test 2: PAPER vs PAPER (Tie - Split Funds)', 1, 1, env);

  console.log(`\n🎉 All tests completed!\n`);
  await stopLogging();
}

main().catch(async (e) => { 
  console.error(e); 
  await stopLogging().catch(() => {});
  process.exit(1); 
});


