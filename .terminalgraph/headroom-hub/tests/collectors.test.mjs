import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { collectAll } from "../lib/collect.mjs";
import { collectGitHub } from "../lib/sources/github.mjs";
import { collectWebsite } from "../lib/sources/website.mjs";

const fixturesRoot = join(
  dirname(fileURLToPath(import.meta.url)),
  "fixtures",
);
const repositories = [
  "kylezantos/headroom",
  "kylezantos/kz-portfolio",
];
const now = new Date("2026-07-27T18:00:00.000Z");

async function fixture(path, encoding = "utf8") {
  const value = await readFile(join(fixturesRoot, path), encoding);
  return encoding ? value : value;
}

async function jsonFixture(path) {
  return JSON.parse(await fixture(path));
}

function githubRunner(data) {
  return async (args) => {
    const repo = args[args.indexOf("--repo") + 1];
    const resource = data[repo];
    if (args[0] === "pr" && args[1] === "list") {
      return JSON.stringify(resource.prs);
    }
    if (args[0] === "pr" && args[1] === "checks") {
      return JSON.stringify(resource.requiredChecks[args[2]] ?? []);
    }
    if (args[0] === "run" && args[1] === "list") {
      return JSON.stringify(resource.runs);
    }
    if (args[0] === "release" && args[1] === "list") {
      return JSON.stringify(resource.releases);
    }
    throw new Error("unexpected synthetic gh command");
  };
}

async function websiteRequester({ mismatch = false } = {}) {
  const latest = await fixture("website/latest.json");
  const appcast = mismatch
    ? (await fixture("website/appcast.xml"))
        .replaceAll("1.2.0", "1.1.9")
        .replaceAll(">30<", ">29<")
    : await fixture("website/appcast.xml");
  const responses = new Map([
    ["/", { status: 200, body: await fixture("website/page.html") }],
    ["/privacy", { status: 200, body: await fixture("website/privacy.html") }],
    ["/latest.json", { status: 200, body: latest }],
    ["/appcast.xml", { status: 200, body: appcast }],
    [
      "/Headroom.dmg",
      {
        status: 200,
        body: "",
        headers: { "content-length": "7000000" },
      },
    ],
  ]);
  return async (url) => {
    const response = responses.get(new URL(url).pathname);
    if (!response) {
      throw new Error("unexpected synthetic website URL");
    }
    return response;
  };
}

test("GitHub and public distribution fixtures report healthy current state", async () => {
  const githubData = await jsonFixture("github/healthy.json");
  const evidence = await jsonFixture("website/evidence-valid.json");
  const github = await collectGitHub({
    repositories,
    runGh: githubRunner(githubData),
    now,
  });
  const website = await collectWebsite({
    baseUrl: "https://headroom.zantos.co",
    request: await websiteRequester(),
    readEvidence: async () => evidence,
    now,
  });

  assert.equal(github.status, "healthy");
  assert.equal(github.signals.length, 0);
  assert.equal(website.status, "healthy");
  assert.deepEqual(
    website.stages.map(({ id, status }) => [id, status]),
    [
      ["macos-published", "complete"],
      ["sparkle-accepted", "accepted"],
    ],
  );
});

test("a failed required PR check becomes an actionable source-linked signal", async () => {
  const githubData = await jsonFixture("github/failed-pr.json");
  const result = await collectGitHub({
    repositories,
    runGh: githubRunner(githubData),
    now,
  });

  assert.equal(result.status, "attention");
  assert.match(result.signals[0].id, /pr-42/u);
  assert.equal(result.signals[0].repository, "kylezantos/headroom");
  assert.equal(
    result.signals[0].sourceUrl,
    "https://github.com/kylezantos/headroom/pull/42",
  );
  assert.match(result.signals[0].summary, /swift-test/u);
});

test("repositories without workflow history are not configured, not failing", async () => {
  const githubData = await jsonFixture("github/no-workflows.json");
  const result = await collectGitHub({
    repositories,
    runGh: githubRunner(githubData),
    now,
  });

  const workflowMetrics = result.metrics.filter(({ id }) =>
    id.endsWith(".workflow-health"),
  );
  assert.equal(result.status, "healthy");
  assert.deepEqual(
    workflowMetrics.map(({ status }) => status),
    ["not-configured", "not-configured"],
  );
});

test("GitHub failure retains stale GitHub state while website refresh remains current", async () => {
  const githubData = await jsonFixture("github/healthy.json");
  const previous = await collectAll({
    adapters: [
      {
        id: "github",
        label: "GitHub",
        collect: () =>
          collectGitHub({
            repositories,
            runGh: githubRunner(githubData),
            now: new Date("2026-07-27T17:55:00.000Z"),
          }),
      },
    ],
    now: new Date("2026-07-27T17:55:00.000Z"),
  });
  const evidence = await jsonFixture("website/evidence-valid.json");
  const request = await websiteRequester();
  const snapshot = await collectAll({
    adapters: [
      {
        id: "github",
        label: "GitHub",
        sourceUrl: "https://github.com/kylezantos/headroom",
        collect: async () => {
          throw new Error("synthetic auth failure");
        },
      },
      {
        id: "website",
        label: "Website + Sparkle",
        collect: () =>
          collectWebsite({
            baseUrl: "https://headroom.zantos.co",
            request,
            readEvidence: async () => evidence,
            now,
          }),
      },
    ],
    previousSnapshot: previous,
    now,
    cacheMaxAgeSeconds: 600,
  });

  assert.equal(snapshot.overall.status, "partial");
  assert.equal(snapshot.sources[0].status, "stale");
  assert.equal(snapshot.sources[1].status, "healthy");
});

test("manifest and appcast mismatch requires attention", async () => {
  const result = await collectWebsite({
    baseUrl: "https://headroom.zantos.co",
    request: await websiteRequester({ mismatch: true }),
    readEvidence: async () => null,
    now,
  });

  assert.equal(result.status, "attention");
  assert.equal(
    result.stages.find(({ id }) => id === "macos-published").status,
    "pending",
  );
  assert.match(result.signals[0].summary, /do not agree/u);
});

test("public distribution can be healthy while acceptance evidence is unknown", async () => {
  const result = await collectWebsite({
    baseUrl: "https://headroom.zantos.co",
    request: await websiteRequester(),
    readEvidence: async () => null,
    now,
  });

  assert.equal(result.status, "healthy");
  assert.equal(
    result.stages.find(({ id }) => id === "sparkle-accepted").status,
    "unknown",
  );
});

test("expired operator evidence is ignored with a typed diagnostic", async () => {
  const oldEvidence = await jsonFixture("website/evidence-old.json");
  const result = await collectWebsite({
    baseUrl: "https://headroom.zantos.co",
    request: await websiteRequester(),
    readEvidence: async () => oldEvidence,
    now,
    evidenceMaxAgeSeconds: 86_400,
  });

  assert.equal(
    result.metrics.find(({ id }) => id === "operator-evidence").status,
    "unavailable",
  );
  assert.equal(
    result.metrics.find(({ id }) => id === "operator-evidence").detail,
    "evidence-expired",
  );
  assert.equal(
    result.stages.find(({ id }) => id === "sparkle-accepted").status,
    "unknown",
  );
});
