import { existsSync } from 'node:fs';
import { readdirSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const __dirname = dirname(fileURLToPath(import.meta.url));
const uiDir = dirname(__dirname);
const viteBin = join(uiDir, 'node_modules', 'vite', 'bin', 'vite.js');
const svelteKitBin = join(uiDir, 'node_modules', '@sveltejs', 'kit', 'svelte-kit.js');
const buildDir = join(uiDir, 'build');

function parseMajor(version) {
  const match = /^v?(\d+)/.exec(version ?? '');
  return match ? Number(match[1]) : null;
}

function findCompatibleNode() {
  const home = process.env.HOME;
  if (!home) return null;

  const installsDir = join(home, '.local', 'share', 'mise', 'installs', 'node');
  if (!existsSync(installsDir)) return null;

  const candidates = readdirSync(installsDir)
    .filter((name) => /^\d+\.\d+\.\d+$/.test(name))
    .map((name) => ({ name, major: Number(name.split('.')[0]) }))
    .filter((entry) => entry.major > 0 && entry.major < 25)
    .sort((a, b) => b.major - a.major || b.name.localeCompare(a.name));

  for (const candidate of candidates) {
    const binary = join(installsDir, candidate.name, 'bin', 'node');
    if (existsSync(binary)) return binary;
  }

  return null;
}

const currentMajor = parseMajor(process.version);
const compatibleNode = currentMajor !== null && currentMajor >= 25 ? findCompatibleNode() : null;
const runtimeNode = compatibleNode ?? process.execPath;

rmSync(buildDir, { recursive: true, force: true });

const syncResult = spawnSync(runtimeNode, [svelteKitBin, 'sync'], {
  cwd: uiDir,
  stdio: 'inherit',
  env: {
    ...process.env,
    NULLHUBX_UI_BUILD_NODE: runtimeNode,
  },
});

if ((syncResult.status ?? 1) !== 0) {
  process.exit(syncResult.status ?? 1);
}

const result = spawnSync(runtimeNode, [viteBin, 'build'], {
  cwd: uiDir,
  stdio: 'inherit',
  env: {
    ...process.env,
    NULLHUBX_UI_BUILD_NODE: runtimeNode,
  },
});
process.exit(result.status ?? 1);
