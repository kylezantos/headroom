import assert from "node:assert/strict";
import test from "node:test";

import {
  REDACTED,
  redactText,
} from "../lib/redact.mjs";
import {
  preflight,
  validateConfig,
} from "../lib/config.mjs";

const validConfig = {
  schemaVersion: 1,
  github: {
    repositories: [
      "kylezantos/headroom",
      "kylezantos/kz-portfolio",
    ],
  },
  website: {
    baseUrl: "https://headroom.zantos.co",
  },
  posthog: {
    host: "https://us.posthog.com",
    projectId: "12345",
    insightIds: {
      pageViews: "abc123",
      downloads: "def456",
    },
  },
  appStoreConnect: {
    appId: "987654321",
  },
};

test("redacts tokens, authorization headers, email addresses, and private key paths", () => {
  const input = [
    "Authorization: Bearer phx_abcdefghijklmnopqrstuvwxyz0123456789",
    "token=sk-proj-abcdefghijklmnopqrstuvwxyz0123456789",
    "{\"access_token\":\"synthetic-short-secret\"}",
    "operator@example.com",
    "HEADROOM_ASC_KEY_PATH=/synthetic/Secrets/AuthKey_ABC123.p8",
    "-----BEGIN PRIVATE KEY-----",
    "not-real-private-key-material",
    "-----END PRIVATE KEY-----",
  ].join("\n");

  const output = redactText(input);

  assert.match(output, new RegExp(REDACTED, "u"));
  assert.doesNotMatch(output, /phx_/u);
  assert.doesNotMatch(output, /sk-proj-/u);
  assert.doesNotMatch(output, /synthetic-short-secret/u);
  assert.doesNotMatch(output, /operator@example\.com/u);
  assert.doesNotMatch(output, /\/synthetic\/Secrets/u);
  assert.doesNotMatch(output, /BEGIN PRIVATE KEY/u);
});

test("valid non-secret source identifiers pass preflight without echoing credential values", () => {
  const environment = {
    HEADROOM_POSTHOG_API_KEY: "phx_not-a-real-key-but-still-secret",
    HEADROOM_ASC_KEY_PATH: "/private/keys/AuthKey_TEST.p8",
    HEADROOM_ASC_KEY_ID: "TESTKEY123",
    HEADROOM_ASC_ISSUER_ID: "00000000-0000-0000-0000-000000000000",
  };

  const result = preflight(validConfig, { environment, githubAuthenticated: true });
  const serialized = JSON.stringify(result);

  assert.equal(result.ok, true);
  assert.equal(result.credentials.github.status, "ready");
  assert.equal(result.credentials.posthog.status, "ready");
  assert.equal(result.credentials.appStoreConnect.status, "ready");
  for (const secret of Object.values(environment)) {
    assert.equal(serialized.includes(secret), false);
  }
});

test("an incomplete App Store Connect credential set reports only the missing variable", () => {
  const environment = {
    HEADROOM_POSTHOG_API_KEY: "phx_not-a-real-key-but-still-secret",
    HEADROOM_ASC_KEY_PATH: "/private/keys/AuthKey_TEST.p8",
    HEADROOM_ASC_KEY_ID: "TESTKEY123",
  };

  const result = preflight(validConfig, { environment, githubAuthenticated: true });
  const serialized = JSON.stringify(result);

  assert.equal(result.ok, false);
  assert.deepEqual(result.credentials.appStoreConnect, {
    status: "incomplete",
    missing: ["HEADROOM_ASC_ISSUER_ID"],
  });
  assert.equal(serialized.includes(environment.HEADROOM_ASC_KEY_PATH), false);
  assert.equal(serialized.includes(environment.HEADROOM_ASC_KEY_ID), false);
});

test("unexpected or non-HTTPS hosts are rejected before collection", () => {
  const unsafeConfigs = [
    {
      ...validConfig,
      website: { baseUrl: "http://headroom.zantos.co" },
    },
    {
      ...validConfig,
      posthog: { ...validConfig.posthog, host: "https://posthog.example.com" },
    },
  ];

  for (const config of unsafeConfigs) {
    assert.throws(
      () => validateConfig(config),
      /not allowed|must use HTTPS/u,
    );
  }
});
