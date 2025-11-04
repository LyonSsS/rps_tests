import { spawn } from 'child_process';
import fs from 'fs/promises';
import path from 'path';

async function main() {
  const reportsDir = path.join(process.cwd(), 'reports');
  try {
    await fs.mkdir(reportsDir, { recursive: true });
  } catch {}

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, -5);
  const fileName = `forge_test_${timestamp}.log`;
  const filePath = path.join(reportsDir, fileName);

  const verbose = process.argv.includes('-vvv') || process.argv.includes('--verbose');
  const forgeArgs = verbose ? ['test', '-vvv'] : ['test'];

  console.log(`📄 Logging to: ${filePath}`);
  console.log(`\n${'='.repeat(80)}`);
  console.log(`Running: forge ${forgeArgs.join(' ')}`);
  console.log(`${'='.repeat(80)}\n`);

  const logFile = await fs.open(filePath, 'w');
  const header = `\n${'='.repeat(80)}\nTest Run: forge test\nStarted: ${new Date().toISOString()}\n${'='.repeat(80)}\n\n`;
  await logFile.write(header);

  const forge = spawn('forge', forgeArgs, {
    shell: true,
    stdio: ['inherit', 'pipe', 'pipe']
  });

  let stdout = '';
  let stderr = '';

  forge.stdout?.on('data', (data: Buffer) => {
    const text = data.toString();
    process.stdout.write(text);
    stdout += text;
    logFile.write(text).catch(() => {});
  });

  forge.stderr?.on('data', (data: Buffer) => {
    const text = data.toString();
    process.stderr.write(text);
    stderr += text;
    logFile.write(`[STDERR] ${text}`).catch(() => {});
  });

  forge.on('close', async (code) => {
    const footer = `\n${'='.repeat(80)}\nFinished: ${new Date().toISOString()}\nExit Code: ${code}\n${'='.repeat(80)}\n`;
    await logFile.write(footer);
    await logFile.close();
    process.exit(code ?? 0);
  });

  forge.on('error', async (err) => {
    await logFile.write(`[ERROR] ${err.message}\n`).catch(() => {});
    await logFile.close();
    process.exit(1);
  });
}

main().catch(async (e) => {
  console.error(e);
  process.exit(1);
});

