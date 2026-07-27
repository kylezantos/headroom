import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  loadConfig,
  readSnapshot,
  writeSnapshot,
} from "../lib/collect.mjs";

test("snapshot persistence is private and corrupt state fails closed", async (context) => {
  const directory = await mkdtemp(join(tmpdir(), "headroom-hub-"));
  context.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, "snapshot.json");
  const snapshot = { schemaVersion: 1, overall: { status: "healthy" } };

  await writeSnapshot(path, snapshot);

  assert.deepEqual(await readSnapshot(path), snapshot);
  assert.equal((await stat(path)).mode & 0o777, 0o600);
  await writeFile(path, "{invalid", "utf8");
  assert.equal(await readSnapshot(path), null);
});

test("missing local config uses the example but malformed local config is rejected", async (context) => {
  const directory = await mkdtemp(join(tmpdir(), "headroom-config-"));
  context.after(() => rm(directory, { recursive: true, force: true }));
  const localPath = join(directory, "config.json");
  const examplePath = join(directory, "config.example.json");
  const validConfig = {
    schemaVersion: 1,
    github: { repositories: ["kylezantos/headroom"] },
    website: { baseUrl: "https://headroom.zantos.co" },
    posthog: {
      host: "https://us.posthog.com",
      projectId: "",
      insightIds: {},
    },
    appStoreConnect: {
      appId: "",
      analyticsReportRequestId: "",
    },
    refresh: {
      intervalSeconds: 300,
      staleAfterSeconds: 900,
      cacheMaxAgeSeconds: 86400,
    },
  };
  await writeFile(examplePath, JSON.stringify(validConfig), "utf8");

  assert.deepEqual(
    await loadConfig({
      localConfigPath: localPath,
      exampleConfigPath: examplePath,
    }),
    validConfig,
  );
  await writeFile(localPath, "{invalid", "utf8");
  await assert.rejects(
    loadConfig({
      localConfigPath: localPath,
      exampleConfigPath: examplePath,
    }),
    SyntaxError,
  );
  assert.equal(await readFile(localPath, "utf8"), "{invalid");
});
