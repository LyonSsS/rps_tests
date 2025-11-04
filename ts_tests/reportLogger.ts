import fs from 'fs/promises';
import path from 'path';

let logFile: fs.FileHandle | null = null;
const originalLog = console.log;
const originalError = console.error;
const originalWarn = console.warn;

export async function startLogging(testName: string, env: string): Promise<void> {
  const reportsDir = path.join(process.cwd(), 'reports');
  try {
    await fs.mkdir(reportsDir, { recursive: true });
  } catch {}

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, -5);
  const fileName = `${testName}_${env}_${timestamp}.log`;
  const filePath = path.join(reportsDir, fileName);

  logFile = await fs.open(filePath, 'w');
  
  // Write header
  const header = `\n${'='.repeat(80)}\nTest Run: ${testName}\nEnvironment: ${env}\nStarted: ${new Date().toISOString()}\n${'='.repeat(80)}\n\n`;
  await logFile.write(header);

  // Override console methods
  console.log = (...args: any[]) => {
    originalLog(...args);
    if (logFile) {
      const msg = args.map(a => typeof a === 'object' ? JSON.stringify(a, null, 2) : String(a)).join(' ') + '\n';
      logFile.write(msg).catch(() => {});
    }
  };

  console.error = (...args: any[]) => {
    originalError(...args);
    if (logFile) {
      const msg = args.map(a => typeof a === 'object' ? JSON.stringify(a, null, 2) : String(a)).join(' ') + '\n';
      logFile.write(`[ERROR] ${msg}`).catch(() => {});
    }
  };

  console.warn = (...args: any[]) => {
    originalWarn(...args);
    if (logFile) {
      const msg = args.map(a => typeof a === 'object' ? JSON.stringify(a, null, 2) : String(a)).join(' ') + '\n';
      logFile.write(`[WARN] ${msg}`).catch(() => {});
    }
  };

  console.log(`📄 Logging to: ${filePath}`);
}

export async function stopLogging(): Promise<void> {
  if (logFile) {
    const footer = `\n${'='.repeat(80)}\nFinished: ${new Date().toISOString()}\n${'='.repeat(80)}\n`;
    await logFile.write(footer);
    await logFile.close();
    logFile = null;
  }

  // Restore original console methods
  console.log = originalLog;
  console.error = originalError;
  console.warn = originalWarn;
}

