import { readFile } from "node:fs/promises";
import { sign } from "node:crypto";

const API_ORIGIN = "https://api.appstoreconnect.apple.com";
const APP_STORE_SOURCE = "https://appstoreconnect.apple.com";
const ANALYTICS_SETUP_SOURCE =
  "https://developer.apple.com/documentation/appstoreconnectapi/post-v1-analyticsreportrequests";
const REQUIRED_ENVIRONMENT_KEYS = [
  "HEADROOM_ASC_KEY_PATH",
  "HEADROOM_ASC_KEY_ID",
  "HEADROOM_ASC_ISSUER_ID",
];
const SUBMITTED_STATES = new Set([
  "IN_REVIEW",
  "PENDING_APPLE_RELEASE",
  "PENDING_DEVELOPER_RELEASE",
  "PROCESSING_FOR_APP_STORE",
  "READY_FOR_DISTRIBUTION",
  "READY_FOR_SALE",
  "WAITING_FOR_REVIEW",
]);
const REJECTED_APP_STORE_STATES = new Set([
  "DEVELOPER_REJECTED",
  "INVALID_BINARY",
  "METADATA_REJECTED",
  "REJECTED",
]);
const FAILED_BUILD_STATES = new Set(["FAILED", "INVALID"]);
const PROCESSING_BUILD_STATES = new Set(["PROCESSING"]);
const DEFAULT_ANALYTICS_REQUEST_LIMIT = 80;
const DEFAULT_ANALYTICS_DEADLINE_MS = 60_000;
const ANALYTICS_COLUMNS = new Map([
  ["Sessions", "sessions"],
  ["Total Downloads", "total-downloads"],
  ["First-Time Downloads", "first-time-downloads"],
  ["Redownloads", "redownloads"],
  ["Installations", "installations"],
]);
const SUPPRESSED_VALUES = new Set([
  "",
  "-",
  "—",
  "Low Data",
  "N/A",
  "null",
]);

function base64url(value) {
  return Buffer.from(value).toString("base64url");
}

export async function createAppStoreConnectToken({
  environment = process.env,
  now = new Date(),
  readFileImpl = readFile,
}) {
  const missing = REQUIRED_ENVIRONMENT_KEYS.filter(
    (key) =>
      typeof environment[key] !== "string"
      || environment[key].length === 0,
  );
  if (missing.length > 0) {
    throw new Error("App Store Connect credentials are incomplete");
  }
  const issuedAt = Math.floor(now.valueOf() / 1000);
  const header = base64url(
    JSON.stringify({
      alg: "ES256",
      kid: environment.HEADROOM_ASC_KEY_ID,
      typ: "JWT",
    }),
  );
  const payload = base64url(
    JSON.stringify({
      iss: environment.HEADROOM_ASC_ISSUER_ID,
      iat: issuedAt,
      exp: issuedAt + 10 * 60,
      aud: "appstoreconnect-v1",
    }),
  );
  const signingInput = `${header}.${payload}`;
  const privateKey = await readFileImpl(
    environment.HEADROOM_ASC_KEY_PATH,
    "utf8",
  );
  const signature = sign("sha256", Buffer.from(signingInput), {
    key: privateKey,
    dsaEncoding: "ieee-p1363",
  }).toString("base64url");
  return `${signingInput}.${signature}`;
}

function safeAPIURL(value) {
  const url = new URL(value, API_ORIGIN);
  if (
    url.origin !== API_ORIGIN
    || url.protocol !== "https:"
    || url.username
    || url.password
  ) {
    throw new TypeError("App Store Connect URL is not allowed");
  }
  return url;
}

export async function defaultAppStoreRequest(
  url,
  {
    token,
    method = "GET",
    signal = AbortSignal.timeout(15_000),
  } = {},
) {
  if (method !== "GET") {
    throw new TypeError("App Store Connect collector permits GET only");
  }
  const safeURL = safeAPIURL(url);
  const response = await fetch(safeURL, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
    },
    redirect: "error",
    signal,
  });
  if (!response.ok) {
    const error = new Error("App Store Connect read failed");
    error.status = response.status;
    throw error;
  }
  return response.json();
}

function safeSegmentURL(value) {
  const url = new URL(value);
  if (
    url.protocol !== "https:"
    || url.username
    || url.password
    || (
      url.hostname !== "api.appstoreconnect.apple.com"
      && !url.hostname.endsWith(".amazonaws.com")
    )
  ) {
    throw new TypeError("analytics report segment URL is not allowed");
  }
  return url;
}

export async function defaultDownloadText(
  url,
  { signal = AbortSignal.timeout(15_000) } = {},
) {
  const response = await fetch(safeSegmentURL(url), {
    method: "GET",
    redirect: "error",
    signal,
  });
  if (!response.ok) {
    throw new Error("analytics report segment download failed");
  }
  return response.text();
}

function budgetFailure() {
  const error = new Error("App Store Connect analytics request budget exhausted");
  error.code = "ANALYTICS_REQUEST_BUDGET_EXHAUSTED";
  return error;
}

function consumeBudget(budget) {
  if (!budget) {
    return null;
  }
  const remainingMilliseconds = budget.deadlineAt - budget.now();
  if (budget.remaining <= 0 || remainingMilliseconds <= 0) {
    throw budgetFailure();
  }
  budget.remaining -= 1;
  return AbortSignal.timeout(Math.max(1, Math.min(15_000, remainingMilliseconds)));
}

async function withBudget(budget, operation) {
  if (!budget) {
    return operation(undefined);
  }
  const signal = consumeBudget(budget);
  try {
    const result = await operation(signal);
    if (budget.now() >= budget.deadlineAt) {
      throw budgetFailure();
    }
    return result;
  } catch (error) {
    if (budget.now() >= budget.deadlineAt) {
      throw budgetFailure();
    }
    throw error;
  }
}

async function listAll(
  path,
  {
    request,
    token,
    budget = null,
    maxItems = Number.POSITIVE_INFINITY,
  },
) {
  const data = [];
  let next = safeAPIURL(path).toString();
  let pageCount = 0;
  while (next && data.length < maxItems) {
    if (pageCount >= 20) {
      throw new Error("App Store Connect pagination exceeded its safety bound");
    }
    const page = await withBudget(
      budget,
      (signal) => request(next, { token, method: "GET", signal }),
    );
    if (!Array.isArray(page?.data)) {
      throw new TypeError("App Store Connect list response is invalid");
    }
    data.push(...page.data);
    next = page.links?.next ? safeAPIURL(page.links.next).toString() : null;
    pageCount += 1;
  }
  return data.slice(0, maxItems);
}

function parseAnalyticsTSV(value) {
  const lines = value
    .replace(/^\uFEFF/u, "")
    .split(/\r?\n/u)
    .filter((line) => line.length > 0);
  if (lines.length < 2) {
    return new Map();
  }
  const headers = lines[0].split("\t");
  const selectedColumns = headers
    .map((header, index) => ({
      header,
      id: ANALYTICS_COLUMNS.get(header),
      index,
    }))
    .filter(({ id }) => id);
  const values = new Map(
    selectedColumns.map(({ header, id }) => [
      id,
      {
        id,
        label: header,
        total: 0,
        numericCount: 0,
        suppressed: false,
      },
    ]),
  );
  for (const line of lines.slice(1)) {
    const columns = line.split("\t");
    for (const { id, index } of selectedColumns) {
      const raw = columns[index]?.trim() ?? "";
      const value = Number(raw);
      const metric = values.get(id);
      if (raw !== "" && Number.isFinite(value)) {
        metric.total += value;
        metric.numericCount += 1;
      } else if (SUPPRESSED_VALUES.has(raw) || !Number.isFinite(value)) {
        metric.suppressed = true;
      }
    }
  }
  return values;
}

async function collectAnalytics({
  appId,
  requestedReportID,
  request,
  token,
  downloadText,
  requestLimit = DEFAULT_ANALYTICS_REQUEST_LIMIT,
  deadlineMilliseconds = DEFAULT_ANALYTICS_DEADLINE_MS,
  clock = Date.now,
}) {
  const budget = {
    remaining: requestLimit,
    deadlineAt: clock() + deadlineMilliseconds,
    now: clock,
  };
  try {
    const reportRequests = await listAll(
      `/v1/apps/${encodeURIComponent(appId)}/analyticsReportRequests`,
      { request, token, budget },
    );
    const reportRequest = requestedReportID
      ? reportRequests.find(({ id }) => id === requestedReportID)
      : reportRequests.find(
          ({ attributes }) =>
            attributes?.accessType === "ONGOING"
            && attributes?.stoppedDueToInactivity !== true,
        );
    if (!reportRequest) {
      return [
        {
          id: "analytics.configuration",
          label: "App analytics reports",
          value: null,
          status: "not-configured",
          detail: "operator-report-request-required",
        },
      ];
    }

    const reports = await listAll(
      `/v1/analyticsReportRequests/${encodeURIComponent(reportRequest.id)}/reports?limit=200`,
      { request, token, budget, maxItems: 200 },
    );
    const selectedReports = reports
      .filter(({ attributes }) =>
        /session|download|usage|installation/iu.test(
          `${attributes?.name ?? ""} ${attributes?.category ?? ""}`,
        ),
      )
      .slice(0, 8);
    const aggregate = new Map();
    for (const report of selectedReports) {
      const instances = await listAll(
        `/v1/analyticsReports/${encodeURIComponent(report.id)}/instances?limit=31`,
        { request, token, budget, maxItems: 31 },
      );
      for (const instance of instances) {
        const segments = await listAll(
          `/v1/analyticsReportInstances/${encodeURIComponent(instance.id)}/segments`,
          { request, token, budget, maxItems: 4 },
        );
        for (const segment of segments) {
          const parsed = parseAnalyticsTSV(
            await withBudget(
              budget,
              (signal) =>
                downloadText(
                  safeSegmentURL(segment.attributes?.url),
                  { signal },
                ),
            ),
          );
          for (const [id, metric] of parsed) {
            const existing = aggregate.get(id) ?? {
              ...metric,
              total: 0,
              numericCount: 0,
              suppressed: false,
            };
            existing.total += metric.total;
            existing.numericCount += metric.numericCount;
            existing.suppressed ||= metric.suppressed;
            aggregate.set(id, existing);
          }
        }
      }
    }
    if (aggregate.size === 0) {
      return [
        {
          id: "analytics.availability",
          label: "App analytics",
          value: null,
          status: "insufficient-data",
          detail: "no-generated-aggregate-data",
        },
      ];
    }
    return [...aggregate.values()].map((metric) => ({
      id: `analytics.${metric.id}`,
      label: metric.label,
      value: metric.suppressed ? null : metric.total,
      unit: "aggregate events",
      status: metric.suppressed ? "insufficient-data" : "complete",
      detail:
        metric.suppressed ? "privacy-threshold-suppressed" : null,
    }));
  } catch (error) {
    return [
      {
        id: "analytics.availability",
        label: "App analytics",
        value: null,
        status: "unavailable",
        detail: error?.code === "ANALYTICS_REQUEST_BUDGET_EXHAUSTED"
          ? "request-budget-exhausted"
          : "analytics-read-failed",
      },
    ];
  }
}

function acceptedEvidence(evidence, now) {
  if (
    evidence?.schemaVersion !== 1
    || !/^docs\/release\/[a-z0-9._/-]+\.md$/u.test(
      evidence?.sourceReference ?? "",
    )
    || evidence.sourceReference.includes("..")
  ) {
    return null;
  }
  const recordedAt = new Date(evidence.recordedAt);
  if (
    Number.isNaN(recordedAt.valueOf())
    || now.valueOf() - recordedAt.valueOf() > 30 * 24 * 60 * 60 * 1000
  ) {
    return null;
  }
  return evidence.stages?.testflightAccepted?.status === "accepted"
    ? evidence.stages.testflightAccepted
    : null;
}

export async function collectAppStoreConnect({
  config,
  request = defaultAppStoreRequest,
  tokenProvider,
  downloadText = defaultDownloadText,
  readEvidence = async () => null,
  now = new Date(),
  analyticsRequestLimit = DEFAULT_ANALYTICS_REQUEST_LIMIT,
  analyticsDeadlineMilliseconds = DEFAULT_ANALYTICS_DEADLINE_MS,
  analyticsClock = Date.now,
}) {
  if (!config.appId) {
    return {
      source: { id: "app-store-connect", label: "App Store Connect" },
      status: "not-configured",
      reasonCode: "missing-configuration",
      summary: "App Store Connect app identifier is not configured",
      sourceUrl: APP_STORE_SOURCE,
    };
  }
  let token;
  try {
    token = await tokenProvider();
  } catch {
    return {
      source: { id: "app-store-connect", label: "App Store Connect" },
      status: "not-configured",
      reasonCode: "missing-credential",
      summary: "App Store Connect read access requires operator setup",
      sourceUrl: APP_STORE_SOURCE,
    };
  }

  const [builds, appStoreVersions, evidence] = await Promise.all([
    listAll(
      `/v1/builds?filter[app]=${encodeURIComponent(config.appId)}&sort=-uploadedDate&limit=1`,
      { request, token },
    ),
    listAll(
      `/v1/apps/${encodeURIComponent(config.appId)}/appStoreVersions?limit=10`,
      { request, token },
    ),
    readEvidence(),
  ]);
  const build = builds[0] ?? null;
  const betaGroups = build
    ? await listAll(`/v1/builds/${encodeURIComponent(build.id)}/betaGroups`, {
        request,
        token,
      })
    : [];
  const analyticsMetrics = await collectAnalytics({
    appId: config.appId,
    requestedReportID: config.analyticsReportRequestId,
    request,
    token,
    downloadText,
    requestLimit: analyticsRequestLimit,
    deadlineMilliseconds: analyticsDeadlineMilliseconds,
    clock: analyticsClock,
  });
  const processingState = build?.attributes?.processingState ?? "UNKNOWN";
  const buildFailed = FAILED_BUILD_STATES.has(processingState);
  const processing = PROCESSING_BUILD_STATES.has(processingState);
  const buildStateUnknown =
    Boolean(build) && !buildFailed && !processing && processingState !== "VALID";
  const buildAvailable = processingState === "VALID" && betaGroups.length > 0;
  const version = appStoreVersions[0] ?? null;
  const appStoreState = version?.attributes?.appStoreState ?? "UNKNOWN";
  const appStoreRejected = REJECTED_APP_STORE_STATES.has(appStoreState);
  const testflightAcceptance = acceptedEvidence(evidence, now);
  const analyticsUnavailable = analyticsMetrics.some(
    ({ status }) => status === "unavailable",
  );
  const signals = [];
  if (processing) {
    signals.push({
      id: "app-store-connect:testflight-processing",
      severity: "info",
      title: "TestFlight build processing",
      summary: `Build ${build.attributes?.version ?? "unknown"} is still processing`,
      sourceUrl: APP_STORE_SOURCE,
    });
  }
  if (buildFailed) {
    signals.push({
      id: "app-store-connect:testflight-rejected",
      severity: "critical",
      title: "TestFlight build rejected",
      summary: "The latest build did not pass App Store Connect processing",
      sourceUrl: APP_STORE_SOURCE,
    });
  }
  if (buildStateUnknown) {
    signals.push({
      id: "app-store-connect:testflight-state-unknown",
      severity: "attention",
      title: "TestFlight build state is unknown",
      summary: "The latest build returned an unrecognized processing state",
      sourceUrl: APP_STORE_SOURCE,
    });
  }
  if (appStoreRejected) {
    signals.push({
      id: "app-store-connect:app-review-rejected",
      severity: "critical",
      title: "App Store submission rejected",
      summary: "The current App Store version is in a rejected state",
      sourceUrl: APP_STORE_SOURCE,
    });
  }
  if (analyticsUnavailable) {
    signals.push({
      id: "app-store-connect:analytics-unavailable",
      severity: "attention",
      title: "App analytics unavailable",
      summary: "Analytics could not be refreshed within the safe read boundary",
      sourceUrl: APP_STORE_SOURCE,
    });
  }

  return {
    source: {
      id: "app-store-connect",
      label: "App Store Connect",
    },
    status:
      processing
      || buildFailed
      || buildStateUnknown
      || appStoreRejected
      || analyticsUnavailable
      || !build
        ? "attention"
        : "healthy",
    summary: build
      ? `Latest iOS build ${build.attributes?.version ?? "unknown"} is ${processingState.toLowerCase()}`
      : "No App Store Connect build is available",
    evidenceAt:
      build?.attributes?.uploadedDate
      ?? version?.attributes?.createdDate
      ?? now.toISOString(),
    sourceUrl: APP_STORE_SOURCE,
    metrics: [
      {
        id: "ios-build",
        label: "Latest iOS build",
        value: build?.attributes?.version ?? null,
        status: build ? "complete" : "unknown",
      },
      {
        id: "testflight-groups",
        label: "Assigned TestFlight groups",
        value: betaGroups.length,
        status: buildAvailable
          ? "complete"
          : buildFailed
            ? "rejected"
            : processing
              ? "processing"
              : buildStateUnknown
                ? "unknown"
                : "pending",
      },
      {
        id: "app-store-version",
        label: "App Store version",
        value: version?.attributes?.versionString ?? null,
        status: version ? "complete" : "unknown",
        detail: appStoreState,
      },
      ...analyticsMetrics,
    ],
    stages: [
      {
        id: "testflight-uploaded",
        label: "TestFlight uploaded",
        status: build ? "complete" : "unknown",
        evidenceAt: build?.attributes?.uploadedDate ?? null,
      },
      {
        id: "testflight-available",
        label: "TestFlight available",
        status: buildAvailable
          ? "complete"
          : buildFailed
            ? "rejected"
            : processing
              ? "processing"
              : buildStateUnknown
                ? "unknown"
                : "pending",
        evidenceAt: buildAvailable ? build.attributes?.uploadedDate : null,
      },
      {
        id: "testflight-accepted",
        label: "TestFlight accepted",
        status: testflightAcceptance ? "accepted" : "unknown",
        evidenceAt: testflightAcceptance?.evidenceAt ?? null,
      },
      {
        id: "app-store-submitted",
        label: "App Store submitted",
        status: appStoreRejected
          ? "rejected"
          : SUBMITTED_STATES.has(appStoreState)
            ? "submitted"
            : "pending",
        evidenceAt: version?.attributes?.createdDate ?? null,
        detail: appStoreState,
      },
    ],
    signals,
  };
}

export function createAppStoreConnectAdapter({
  config,
  environment = process.env,
  request = defaultAppStoreRequest,
  downloadText = defaultDownloadText,
  readEvidence,
  now,
}) {
  const credentialSetComplete = REQUIRED_ENVIRONMENT_KEYS.every(
    (key) =>
      typeof environment[key] === "string"
      && environment[key].length > 0,
  );
  return {
    id: "app-store-connect",
    label: "App Store Connect",
    sourceUrl: APP_STORE_SOURCE,
    collect: () => {
      if (!credentialSetComplete) {
        return {
          source: {
            id: "app-store-connect",
            label: "App Store Connect",
          },
          status: "not-configured",
          reasonCode: "missing-credential",
          summary: "App Store Connect read access requires operator setup",
          sourceUrl: APP_STORE_SOURCE,
          setupUrl: ANALYTICS_SETUP_SOURCE,
        };
      }
      return collectAppStoreConnect({
        config: config.appStoreConnect,
        request,
        tokenProvider: () =>
          createAppStoreConnectToken({
            environment,
            now: now?.() ?? new Date(),
          }),
        downloadText,
        readEvidence,
        now: now?.() ?? new Date(),
      });
    },
  };
}
