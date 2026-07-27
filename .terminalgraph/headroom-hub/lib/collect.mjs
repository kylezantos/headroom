import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { preflight, validateConfig } from "./config.mjs";
import { normalizeSnapshot } from "./normalize.mjs";
import {
  createAppStoreConnectAdapter,
} from "./sources/app-store-connect.mjs";
import {
  createGitHubAdapter,
  defaultRunGh,
} from "./sources/github.mjs";
import { createPostHogAdapter } from "./sources/posthog.mjs";
import { createWebsiteAdapter } from "./sources/website.mjs";

const HUB_ROOT = new URL("../", import.meta.url);
const LOCAL_CONFIG_URL = new URL("config.json", HUB_ROOT);
const EXAMPLE_CONFIG_URL = new URL("config.example.json", HUB_ROOT);
const SNAPSHOT_URL = new URL("data/snapshot.json", HUB_ROOT);
const EVIDENCE_URL = new URL("evidence/release.json", HUB_ROOT);

export async function readSnapshot(path) {
  try {
    return JSON.parse(await readFile(path, "utf8"));
  } catch {
    return null;
  }
}

export async function writeSnapshot(path, snapshot) {
  const filePath = path instanceof URL ? fileURLToPath(path) : path;
  await mkdir(dirname(filePath), { recursive: true });
  const temporaryPath = `${filePath}.${process.pid}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(snapshot, null, 2)}\n`, {
    encoding: "utf8",
    mode: 0o600,
  });
  await rename(temporaryPath, filePath);
}

async function readJSON(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

export async function loadConfig({
  localConfigPath = LOCAL_CONFIG_URL,
  exampleConfigPath = EXAMPLE_CONFIG_URL,
} = {}) {
  let config;
  try {
    config = await readJSON(localConfigPath);
  } catch (error) {
    if (error?.code !== "ENOENT") {
      throw error;
    }
    config = await readJSON(exampleConfigPath);
  }
  return validateConfig(config);
}

export async function collectAll({
  adapters,
  previousSnapshot = null,
  now = new Date(),
  cacheMaxAgeSeconds = 86_400,
}) {
  const settled = await Promise.allSettled(
    adapters.map(async (adapter) => {
      const result = await adapter.collect();
      return {
        ...result,
        source: {
          id: adapter.id,
          label: adapter.label,
        },
      };
    }),
  );

  const results = settled.map((entry, index) => {
    const adapter = adapters[index];
    if (entry.status === "fulfilled") {
      return entry.value;
    }
    return {
      source: {
        id: adapter.id,
        label: adapter.label,
      },
      status: "unavailable",
      reasonCode: "collector-failed",
      summary: `${adapter.label} could not be refreshed`,
      sourceUrl: adapter.sourceUrl,
    };
  });

  return normalizeSnapshot(results, {
    now,
    previousSnapshot,
    cacheMaxAgeSeconds,
  });
}

export async function runHubCollection({
  config,
  environment = process.env,
  snapshotPath = SNAPSHOT_URL,
  evidencePath = EVIDENCE_URL,
  now = new Date(),
  runGh,
} = {}) {
  const resolvedConfig = config ?? await loadConfig();
  const previousSnapshot = await readSnapshot(snapshotPath);
  const readEvidence = () => readSnapshot(evidencePath);
  const nowProvider = () => now;
  const adapters = [
    createGitHubAdapter({
      config: resolvedConfig,
      runGh,
      now: nowProvider,
    }),
    createWebsiteAdapter({
      config: resolvedConfig,
      readEvidence,
      now: nowProvider,
    }),
    createPostHogAdapter({
      config: resolvedConfig,
      environment,
      now: nowProvider,
    }),
    createAppStoreConnectAdapter({
      config: resolvedConfig,
      environment,
      readEvidence,
      now: nowProvider,
    }),
  ];
  const snapshot = await collectAll({
    adapters,
    previousSnapshot,
    now,
    cacheMaxAgeSeconds:
      resolvedConfig.refresh?.cacheMaxAgeSeconds ?? 86_400,
  });
  await writeSnapshot(snapshotPath, snapshot);
  return snapshot;
}

async function githubAuthenticated() {
  try {
    await defaultRunGh(["auth", "status", "--hostname", "github.com"]);
    return true;
  } catch {
    return false;
  }
}

async function main() {
  const config = await loadConfig();
  if (process.argv.includes("--preflight")) {
    const result = preflight(config, {
      environment: process.env,
      githubAuthenticated: await githubAuthenticated(),
    });
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    return;
  }
  const snapshot = await runHubCollection({ config });
  process.stdout.write(
    `HEADROOM_HUB_REFRESH=${snapshot.overall.status} sources=${snapshot.sources.length}\n`,
  );
}

if (
  process.argv[1]
  && pathToFileURL(process.argv[1]).href === import.meta.url
) {
  main().catch(() => {
    process.stderr.write("Headroom hub refresh failed safely.\n");
    process.exitCode = 1;
  });
}
