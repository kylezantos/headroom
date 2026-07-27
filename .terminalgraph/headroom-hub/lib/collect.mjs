import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

import { normalizeSnapshot } from "./normalize.mjs";

export async function readSnapshot(path) {
  try {
    return JSON.parse(await readFile(path, "utf8"));
  } catch {
    return null;
  }
}

export async function writeSnapshot(path, snapshot) {
  await mkdir(dirname(path), { recursive: true });
  const temporaryPath = `${path}.${process.pid}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(snapshot, null, 2)}\n`, {
    encoding: "utf8",
    mode: 0o600,
  });
  await rename(temporaryPath, path);
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
