import 'dotenv/config';
import { createPublicClient, createWalletClient, http, parseEther, getContract, Hex } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { foundry, sepolia } from 'viem/chains';
import abiJson from '../../out/RockPaperScissors.sol/RockPaperScissors.json' assert { type: 'json' };

export type Env = {
  rpcUrl: string;
  privateKey: Hex;
  privateKey2?: Hex;
  contractAddress?: Hex;
  isLocal: boolean;
};

export function loadEnv(envArg?: string): Env {
  const envName = envArg || process.env.TEST_ENV || 'anvil';
  
  let rpcUrl: string;
  let isLocal: boolean;
  
  if (envName === 'sepolia') {
    rpcUrl = process.env.SEPOLIA_RPC_URL || '';
    if (!rpcUrl) throw new Error('SEPOLIA_RPC_URL must be set in .env for sepolia tests');
    isLocal = false;
  } else {
    rpcUrl = process.env.ANVIL_RPC_URL || 'http://127.0.0.1:8545';
    isLocal = true;
  }
  
  const pk = process.env.PRIVATE_KEY as Hex | undefined;
  if (!pk) throw new Error('PRIVATE_KEY is required in .env');
  
  const pk2 = process.env.PRIVATE_KEY_2 as Hex | undefined;
  
  return {
    rpcUrl,
    privateKey: pk,
    privateKey2: pk2,
    contractAddress: process.env.CONTRACT_ADDRESS as Hex | undefined,
    isLocal
  };
}

export async function makeClients(env: Env, useSecondWallet = false) {
  const pk = useSecondWallet && env.privateKey2 ? env.privateKey2 : env.privateKey;
  if (!pk) throw new Error(useSecondWallet ? 'PRIVATE_KEY_2 required but not set in .env' : 'PRIVATE_KEY required');
  
  const account = privateKeyToAccount(pk);
  const chain = env.isLocal ? foundry : sepolia;
  const transport = http(env.rpcUrl);
  
  const publicClient = createPublicClient({ chain, transport });
  const walletClient = createWalletClient({ account, chain, transport });
  
  return { publicClient, walletClient, account, isLocal: env.isLocal };
}

export async function getDeployedContract(address: Hex) {
  const abi = (abiJson as any).abi;
  return { abi, address } as const;
}

export function makeCommit(move: number) {
  // Use crypto to generate random 32-byte salt/nonce
  const salt = crypto.getRandomValues(new Uint8Array(32));
  const nonce = crypto.getRandomValues(new Uint8Array(32));
  // viem encodePacked/keccak256 convenience: we'll compute on-chain; commitment is done client-side typically,
  // but for this harness we pass hash precomputed by the contract via solidity equivalence if needed.
  // We'll use viem to compute keccak256 of packed types.
  return { move, salt: ('0x' + Buffer.from(salt).toString('hex')) as Hex, nonce: ('0x' + Buffer.from(nonce).toString('hex')) as Hex };
}


