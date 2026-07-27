import assert from "node:assert/strict";
import test from "node:test";

import {
  normalizeResult,
  normalizeSnapshot,
} from "../lib/normalize.mjs";

const now = new Date("2026-07-27T18:00:00.000Z");

function healthyResult(id, overrides = {}) {
  return {
    source: {
      id,
      label: id === "github" ? "GitHub" : "Website",
    },
    status: "healthy",
    summary: "Current",
    evidenceAt: "2026-07-27T17:59:00.000Z",
    sourceUrl:
      id === "github"
        ? "https://github.com/kylezantos/headroom"
        : "https://headroom.zantos.co",
    metrics: [],
    stages: [],
    signals: [],
    ...overrides,
  };
}

test("all current healthy sources preserve evidence timestamps", () => {
  const snapshot = normalizeSnapshot(
    [healthyResult("github"), healthyResult("website")],
    { now },
  );

  assert.deepEqual(snapshot.overall, {
    status: "healthy",
    completeness: "complete",
    attentionCount: 0,
  });
  assert.equal(snapshot.sources[0].freshness.kind, "current");
  assert.equal(
    snapshot.sources[0].freshness.evidenceAt,
    "2026-07-27T17:59:00.000Z",
  );
});

test("one failed source makes the snapshot partial without hiding healthy sources", () => {
  const snapshot = normalizeSnapshot(
    [
      healthyResult("github"),
      {
        source: { id: "posthog", label: "PostHog" },
        status: "unavailable",
        reasonCode: "request-failed",
        summary: "PostHog could not be refreshed",
        sourceUrl: "https://us.posthog.com",
      },
      healthyResult("website"),
    ],
    { now },
  );

  assert.equal(snapshot.overall.status, "partial");
  assert.equal(snapshot.overall.completeness, "partial");
  assert.deepEqual(
    snapshot.sources.map(({ status }) => status),
    ["healthy", "unavailable", "healthy"],
  );
});

test("a source that has never succeeded is unknown or not configured, never stale", () => {
  const unknown = normalizeResult(
    {
      source: { id: "github", label: "GitHub" },
      status: "unknown",
      reasonCode: "no-history",
      summary: "No collection has completed",
    },
    { now },
  );
  const notConfigured = normalizeResult(
    {
      source: { id: "posthog", label: "PostHog" },
      status: "not-configured",
      reasonCode: "missing-credential",
      summary: "Setup required",
    },
    { now },
  );

  assert.equal(unknown.status, "unknown");
  assert.equal(unknown.freshness.kind, "unknown");
  assert.equal(notConfigured.status, "not-configured");
  assert.equal(notConfigured.freshness.kind, "unknown");
});

test("a failed source retains bounded prior data as explicitly stale", () => {
  const previous = normalizeResult(healthyResult("github"), {
    now: new Date("2026-07-27T17:55:00.000Z"),
  });
  const retained = normalizeResult(
    {
      source: { id: "github", label: "GitHub" },
      status: "unavailable",
      reasonCode: "auth-unavailable",
      summary: "GitHub authentication is unavailable",
    },
    {
      now,
      previous,
      cacheMaxAgeSeconds: 600,
    },
  );

  assert.equal(retained.status, "stale");
  assert.equal(retained.retainedStatus, "healthy");
  assert.equal(retained.freshness.kind, "retained");
  assert.equal(retained.freshness.staleAgeSeconds, 300);
  assert.equal(retained.summary, "GitHub authentication is unavailable");
});

test("expired retained data becomes unknown and drops prior measurements", () => {
  const previous = normalizeResult(
    healthyResult("github", {
      metrics: [{ id: "open-prs", label: "Open PRs", value: 2 }],
    }),
    { now: new Date("2026-07-26T17:00:00.000Z") },
  );
  const expired = normalizeResult(
    {
      source: { id: "github", label: "GitHub" },
      status: "unavailable",
      reasonCode: "request-failed",
      summary: "Refresh failed",
    },
    {
      now,
      previous,
      cacheMaxAgeSeconds: 3600,
    },
  );

  assert.equal(expired.status, "unknown");
  assert.equal(expired.freshness.kind, "unknown");
  assert.deepEqual(expired.metrics, []);
  assert.equal(expired.diagnostic, "cache-expired");
});

test("macOS and iOS release stages remain independently named", () => {
  const release = normalizeResult(
    healthyResult("website", {
      status: "attention",
      stages: [
        {
          id: "macos-published",
          label: "macOS published",
          status: "complete",
        },
        {
          id: "sparkle-accepted",
          label: "Sparkle accepted",
          status: "pending",
        },
        {
          id: "testflight-uploaded",
          label: "TestFlight uploaded",
          status: "complete",
        },
        {
          id: "testflight-available",
          label: "TestFlight available",
          status: "processing",
        },
      ],
    }),
    { now },
  );

  assert.deepEqual(
    release.stages.map(({ id, status }) => [id, status]),
    [
      ["macos-published", "complete"],
      ["sparkle-accepted", "pending"],
      ["testflight-uploaded", "complete"],
      ["testflight-available", "processing"],
    ],
  );
});

test("only allowlisted redacted fields survive normalization", () => {
  const normalized = normalizeResult(
    healthyResult("github", {
      summary: "Contact operator@example.com",
      rawResponse: {
        authorization: "Bearer phx_abcdefghijklmnopqrstuvwxyz0123456789",
      },
      metrics: [
        {
          id: "safe",
          label: "Safe metric",
          value: "sk-proj-abcdefghijklmnopqrstuvwxyz0123456789",
          raw: "must not survive",
        },
      ],
    }),
    { now },
  );
  const serialized = JSON.stringify(normalized);

  assert.equal("rawResponse" in normalized, false);
  assert.equal("raw" in normalized.metrics[0], false);
  assert.doesNotMatch(serialized, /operator@example\.com|sk-proj-|phx_/u);
});
