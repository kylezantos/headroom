import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { collectAll } from "../lib/collect.mjs";
import {
  collectAppStoreConnect,
  createAppStoreConnectToken,
  createAppStoreConnectAdapter,
} from "../lib/sources/app-store-connect.mjs";
import { collectGitHub } from "../lib/sources/github.mjs";
import { collectPostHog } from "../lib/sources/posthog.mjs";
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

async function postHogRequester({ missingInsight = null, failureStatus = null } = {}) {
  const responses = new Map([
    ["page-views-7d", await jsonFixture("posthog/page-views-7d.json")],
    ["page-views-30d", await jsonFixture("posthog/page-views-30d.json")],
    ["downloads-7d", await jsonFixture("posthog/downloads-7d.json")],
    ["downloads-30d", await jsonFixture("posthog/downloads-30d.json")],
  ]);
  return async (url, options) => {
    assert.equal(options.method, "GET");
    const insightID = new URL(url).pathname.split("/").filter(Boolean).at(-1);
    if (failureStatus) {
      throw Object.assign(new Error("synthetic provider body must not survive"), {
        status: failureStatus,
        body: "Authorization: Bearer phx_secret-provider-body",
      });
    }
    if (insightID === missingInsight) {
      throw Object.assign(new Error("synthetic missing insight"), { status: 404 });
    }
    return responses.get(insightID);
  };
}

async function appStoreRequester({
  processing = false,
  emptyReportRequests = false,
  processingState = null,
  appStoreState = null,
} = {}) {
  const calls = [];
  const build = await jsonFixture(
    processing
      ? "app-store-connect/builds-processing.json"
      : "app-store-connect/builds-processed.json",
  );
  const betaGroups = await jsonFixture("app-store-connect/beta-groups.json");
  const versions = await jsonFixture(
    "app-store-connect/app-store-versions.json",
  );
  if (processingState) {
    build.data[0].attributes.processingState = processingState;
  }
  if (appStoreState) {
    versions.data[0].attributes.appStoreState = appStoreState;
  }
  const firstRequestsPage = await jsonFixture(
    emptyReportRequests
      ? "app-store-connect/report-requests-empty.json"
      : "app-store-connect/report-requests-page-1.json",
  );
  const secondRequestsPage = await jsonFixture(
    "app-store-connect/report-requests-page-2.json",
  );
  const reports = await jsonFixture("app-store-connect/reports.json");
  const instances = await jsonFixture("app-store-connect/instances.json");
  const segments = await jsonFixture("app-store-connect/segments.json");

  return {
    calls,
    request: async (url, options) => {
      calls.push({ url, method: options.method });
      assert.equal(options.method, "GET");
      const parsed = new URL(url);
      if (parsed.pathname === "/v1/builds") {
        return build;
      }
      if (parsed.pathname.endsWith("/betaGroups")) {
        return betaGroups;
      }
      if (parsed.pathname.endsWith("/appStoreVersions")) {
        return versions;
      }
      if (parsed.pathname.endsWith("/analyticsReportRequests")) {
        return parsed.searchParams.get("cursor") === "next"
          ? secondRequestsPage
          : firstRequestsPage;
      }
      if (parsed.pathname.endsWith("/reports")) {
        return reports;
      }
      if (parsed.pathname.endsWith("/instances")) {
        return instances;
      }
      if (parsed.pathname.endsWith("/segments")) {
        return segments;
      }
      throw new Error(`unexpected synthetic App Store Connect path: ${parsed.pathname}`);
    },
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

test("GitHub reports when the open PR result set may be truncated", async () => {
  const githubData = await jsonFixture("github/healthy.json");
  const template = githubData["kylezantos/headroom"].prs[0] ?? {
    title: "Synthetic open PR",
    url: "https://github.com/kylezantos/headroom/pull/1",
    updatedAt: now.toISOString(),
  };
  githubData["kylezantos/headroom"].prs = Array.from(
    { length: 100 },
    (_, index) => ({
      ...template,
      number: index + 1,
      url: `https://github.com/kylezantos/headroom/pull/${index + 1}`,
    }),
  );

  const result = await collectGitHub({
    repositories,
    runGh: githubRunner(githubData),
    now,
  });

  assert.equal(result.status, "attention");
  assert.ok(
    result.signals.some(({ id }) => id.endsWith("open-pr-result-limit")),
  );
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

test("PostHog returns aggregate page-view and download windows", async () => {
  const result = await collectPostHog({
    config: {
      host: "https://us.posthog.com",
      projectId: "12345",
      insightIds: {
        pageViews7d: "page-views-7d",
        pageViews30d: "page-views-30d",
        downloads7d: "downloads-7d",
        downloads30d: "downloads-30d",
      },
    },
    apiKey: "phx_synthetic-secret",
    request: await postHogRequester(),
    now,
  });

  assert.equal(result.status, "healthy");
  assert.deepEqual(
    result.metrics.map(({ id, value }) => [id, value]),
    [
      ["page-views-7d", 120],
      ["page-views-30d", 480],
      ["downloads-7d", 8],
      ["downloads-30d", 25],
    ],
  );
  assert.doesNotMatch(JSON.stringify(result), /phx_synthetic/u);
});

test("one missing PostHog insight does not erase the remaining metrics", async () => {
  const result = await collectPostHog({
    config: {
      host: "https://us.posthog.com",
      projectId: "12345",
      insightIds: {
        pageViews7d: "page-views-7d",
        downloads7d: "missing-downloads",
      },
    },
    apiKey: "phx_synthetic-secret",
    request: await postHogRequester({ missingInsight: "missing-downloads" }),
    now,
  });

  assert.equal(result.status, "attention");
  assert.equal(result.metrics[0].value, 120);
  assert.equal(result.metrics[1].status, "unavailable");
  assert.equal(result.signals.length, 1);
});

test("PostHog rate-limit failure becomes stale without retaining response text", async () => {
  const config = {
    host: "https://us.posthog.com",
    projectId: "12345",
    insightIds: { pageViews7d: "page-views-7d" },
  };
  const successfulRequest = await postHogRequester();
  const previous = await collectAll({
    adapters: [
      {
        id: "posthog",
        label: "PostHog",
        collect: () =>
          collectPostHog({
            config,
            apiKey: "phx_synthetic-secret",
            request: successfulRequest,
            now: new Date("2026-07-27T17:55:00.000Z"),
          }),
      },
    ],
    now: new Date("2026-07-27T17:55:00.000Z"),
  });
  const failedRequest = await postHogRequester({ failureStatus: 429 });
  const current = await collectAll({
    adapters: [
      {
        id: "posthog",
        label: "PostHog",
        collect: () =>
          collectPostHog({
            config,
            apiKey: "phx_synthetic-secret",
            request: failedRequest,
            now,
          }),
      },
    ],
    previousSnapshot: previous,
    now,
    cacheMaxAgeSeconds: 600,
  });

  assert.equal(current.sources[0].status, "stale");
  assert.doesNotMatch(
    JSON.stringify(current),
    /secret-provider-body|Authorization|phx_/u,
  );
});

test("App Store Connect keeps upload, availability, acceptance, and review states distinct", async () => {
  const requester = await appStoreRequester();
  const result = await collectAppStoreConnect({
    config: {
      appId: "123456789",
      analyticsReportRequestId: "request-1",
    },
    request: requester.request,
    tokenProvider: async () => "synthetic-jwt",
    downloadText: async () =>
      fixture("app-store-connect/analytics.tsv"),
    readEvidence: async () => null,
    now,
  });

  assert.equal(result.status, "healthy");
  assert.deepEqual(
    result.stages.map(({ id, status }) => [id, status]),
    [
      ["testflight-uploaded", "complete"],
      ["testflight-available", "complete"],
      ["testflight-accepted", "unknown"],
      ["app-store-submitted", "pending"],
    ],
  );
  assert.equal(
    result.metrics.find(({ id }) => id === "analytics.sessions").value,
    12,
  );
  assert.equal(
    result.metrics.find(({ id }) => id === "analytics.total-downloads").value,
    4,
  );
  assert.ok(
    requester.calls.some(({ url }) => new URL(url).searchParams.get("cursor") === "next"),
  );
  assert.ok(requester.calls.every(({ method }) => method === "GET"));
});

test("a processing build is uploaded but not yet available", async () => {
  const requester = await appStoreRequester({ processing: true });
  const result = await collectAppStoreConnect({
    config: {
      appId: "123456789",
      analyticsReportRequestId: "request-1",
    },
    request: requester.request,
    tokenProvider: async () => "synthetic-jwt",
    downloadText: async () =>
      fixture("app-store-connect/analytics.tsv"),
    readEvidence: async () => null,
    now,
  });

  assert.equal(result.status, "attention");
  assert.equal(result.stages[0].status, "complete");
  assert.equal(result.stages[1].status, "processing");
});

test("failed Apple processing and rejected review are not labeled processing or submitted", async () => {
  const requester = await appStoreRequester({
    processingState: "FAILED",
    appStoreState: "DEVELOPER_REJECTED",
  });
  const result = await collectAppStoreConnect({
    config: {
      appId: "123456789",
      analyticsReportRequestId: "request-1",
    },
    request: requester.request,
    tokenProvider: async () => "synthetic-jwt",
    downloadText: async () =>
      fixture("app-store-connect/analytics.tsv"),
    readEvidence: async () => null,
    now,
  });

  assert.equal(result.status, "attention");
  assert.equal(result.stages[1].status, "rejected");
  assert.equal(result.stages[3].status, "rejected");
  assert.ok(
    result.signals.some(
      ({ id }) => id === "app-store-connect:testflight-rejected",
    ),
  );
  assert.ok(
    result.signals.some(
      ({ id }) => id === "app-store-connect:app-review-rejected",
    ),
  );
});

test("Apple analytics stops at its read budget without hiding release state", async () => {
  const requester = await appStoreRequester();
  let downloadCount = 0;
  const result = await collectAppStoreConnect({
    config: {
      appId: "123456789",
      analyticsReportRequestId: "request-1",
    },
    request: requester.request,
    tokenProvider: async () => "synthetic-jwt",
    downloadText: async () => {
      downloadCount += 1;
      return fixture("app-store-connect/analytics.tsv");
    },
    readEvidence: async () => null,
    now,
    analyticsRequestLimit: 1,
  });

  assert.equal(result.status, "attention");
  assert.equal(result.stages[1].status, "complete");
  assert.equal(
    result.metrics.find(({ id }) => id === "analytics.availability").detail,
    "request-budget-exhausted",
  );
  assert.equal(downloadCount, 0);
  assert.equal(requester.calls.length, 4);
});

test("Apple analytics stops at its refresh deadline", async () => {
  const requester = await appStoreRequester();
  let clock = 0;
  const result = await collectAppStoreConnect({
    config: {
      appId: "123456789",
      analyticsReportRequestId: "request-1",
    },
    request: async (...arguments_) => {
      const response = await requester.request(...arguments_);
      clock += 60;
      return response;
    },
    tokenProvider: async () => "synthetic-jwt",
    downloadText: async () =>
      fixture("app-store-connect/analytics.tsv"),
    readEvidence: async () => null,
    now,
    analyticsDeadlineMilliseconds: 100,
    analyticsClock: () => clock,
  });

  assert.equal(result.status, "attention");
  assert.equal(result.stages[1].status, "complete");
  assert.equal(
    result.metrics.find(({ id }) => id === "analytics.availability").detail,
    "request-budget-exhausted",
  );
});

test("App Store Connect refresh failure retains only the prior normalized state", async () => {
  const requester = await appStoreRequester();
  const previous = await collectAll({
    adapters: [
      {
        id: "app-store-connect",
        label: "App Store Connect",
        collect: () =>
          collectAppStoreConnect({
            config: {
              appId: "123456789",
              analyticsReportRequestId: "request-1",
            },
            request: requester.request,
            tokenProvider: async () => "synthetic-jwt",
            downloadText: async () =>
              fixture("app-store-connect/analytics.tsv"),
            now: new Date("2026-07-27T17:55:00.000Z"),
          }),
      },
    ],
    now: new Date("2026-07-27T17:55:00.000Z"),
  });
  const current = await collectAll({
    adapters: [
      {
        id: "app-store-connect",
        label: "App Store Connect",
        sourceUrl: "https://appstoreconnect.apple.com",
        collect: () =>
          collectAppStoreConnect({
            config: {
              appId: "123456789",
              analyticsReportRequestId: "request-1",
            },
            request: async () => {
              throw new Error("Authorization: Bearer synthetic-provider-body");
            },
            tokenProvider: async () => "synthetic-jwt",
            now,
          }),
      },
    ],
    previousSnapshot: previous,
    now,
    cacheMaxAgeSeconds: 600,
  });

  assert.equal(current.sources[0].status, "stale");
  assert.doesNotMatch(
    JSON.stringify(current),
    /synthetic-provider-body|Authorization|Bearer/u,
  );
});

test("threshold-suppressed Apple analytics are insufficient data, not zero", async () => {
  const requester = await appStoreRequester();
  const result = await collectAppStoreConnect({
    config: {
      appId: "123456789",
      analyticsReportRequestId: "request-1",
    },
    request: requester.request,
    tokenProvider: async () => "synthetic-jwt",
    downloadText: async () =>
      fixture("app-store-connect/analytics-suppressed.tsv"),
    readEvidence: async () => null,
    now,
  });

  const analytics = result.metrics.filter(({ id }) =>
    id.startsWith("analytics."),
  );
  assert.ok(analytics.length > 0);
  assert.ok(analytics.every(({ value }) => value === null));
  assert.ok(
    analytics.every(({ status }) => status === "insufficient-data"),
  );
  assert.ok(
    analytics.every(({ detail }) => detail === "privacy-threshold-suppressed"),
  );
});

test("a privacy-suppressed analytics row invalidates an otherwise numeric aggregate", async () => {
  const requester = await appStoreRequester();
  const result = await collectAppStoreConnect({
    config: {
      appId: "123456789",
      analyticsReportRequestId: "request-1",
    },
    request: requester.request,
    tokenProvider: async () => "synthetic-jwt",
    downloadText: async () => [
      "Date\tApp Name\tSessions\tTotal Downloads",
      "2026-07-26\tHeadroom\t12\t4",
      "2026-07-27\tHeadroom\tLow Data\tLow Data",
    ].join("\n"),
    readEvidence: async () => null,
    now,
  });

  const analytics = result.metrics.filter(({ id }) =>
    id.startsWith("analytics."),
  );
  assert.ok(analytics.length > 0);
  assert.ok(analytics.every(({ value }) => value === null));
  assert.ok(
    analytics.every(({ status }) => status === "insufficient-data"),
  );
  assert.ok(
    analytics.every(({ detail }) => detail === "privacy-threshold-suppressed"),
  );
});

test("no analytics report request is not configured and performs no write method", async () => {
  const requester = await appStoreRequester({ emptyReportRequests: true });
  const result = await collectAppStoreConnect({
    config: {
      appId: "123456789",
      analyticsReportRequestId: "",
    },
    request: requester.request,
    tokenProvider: async () => "synthetic-jwt",
    downloadText: async () => {
      throw new Error("segments must not be requested");
    },
    readEvidence: async () => null,
    now,
  });

  assert.equal(
    result.metrics.find(({ id }) => id === "analytics.configuration").status,
    "not-configured",
  );
  assert.ok(requester.calls.every(({ method }) => method === "GET"));
  assert.equal(
    requester.calls.some(({ url }) => new URL(url).pathname.endsWith("/reports")),
    false,
  );
});

test("missing App Store Connect credentials produce setup state without making a request", async () => {
  let requestCount = 0;
  const adapter = createAppStoreConnectAdapter({
    config: {
      appStoreConnect: {
        appId: "123456789",
        analyticsReportRequestId: "",
      },
    },
    environment: {},
    request: async () => {
      requestCount += 1;
      throw new Error("request must not run");
    },
  });
  const result = await adapter.collect();

  assert.equal(result.status, "not-configured");
  assert.equal(result.reasonCode, "missing-credential");
  assert.equal(requestCount, 0);
  assert.doesNotMatch(JSON.stringify(result), /KEY_PATH|ISSUER_ID|JWT/u);
});

test("App Store Connect authentication creates a short-lived ES256 token without logging key material", async () => {
  const { privateKey } = generateKeyPairSync("ec", {
    namedCurve: "P-256",
  });
  const privateKeyPEM = privateKey.export({
    format: "pem",
    type: "pkcs8",
  });
  const token = await createAppStoreConnectToken({
    environment: {
      HEADROOM_ASC_KEY_PATH: "/synthetic/AuthKey_TEST.p8",
      HEADROOM_ASC_KEY_ID: "TESTKEY",
      HEADROOM_ASC_ISSUER_ID: "00000000-0000-0000-0000-000000000000",
    },
    now,
    readFileImpl: async () => privateKeyPEM,
  });
  const [encodedHeader, encodedPayload, signature] = token.split(".");
  const header = JSON.parse(
    Buffer.from(encodedHeader, "base64url").toString("utf8"),
  );
  const payload = JSON.parse(
    Buffer.from(encodedPayload, "base64url").toString("utf8"),
  );

  assert.deepEqual(header, {
    alg: "ES256",
    kid: "TESTKEY",
    typ: "JWT",
  });
  assert.equal(payload.aud, "appstoreconnect-v1");
  assert.equal(payload.exp - payload.iat, 600);
  assert.ok(signature.length > 0);
  assert.doesNotMatch(token, /PRIVATE KEY|synthetic\/AuthKey/u);
});
