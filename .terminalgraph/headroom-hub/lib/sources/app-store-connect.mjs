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
  "DEVELOPER_REJECTED",
  "IN_REVIEW",
  "PENDING_APPLE_RELEASE",
  "PENDING_DEVELOPER_RELEASE",
  "PROCESSING_FOR_APP_STORE",
  "READY_FOR_DISTRIBUTION",
  "READY_FOR_SALE",
  "WAITING_FOR_REVIEW",
]);
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
  { token, method = "GET" } = {},
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
    signal: AbortSignal.timeout(15_000),
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

export async function defaultDownloadText(url) {
  const response = await fetch(safeSegmentURL(url), {
    method: "GET",
    redirect: "error",
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) {
    throw new Error("analytics report segment download failed");
  }
  return response.text();
}

async function listAll(path, { request, token }) {
  const data = [];
  let next = safeAPIURL(path).toString();
  let pageCount = 0;
  while (next) {
    if (pageCount >= 20) {
      throw new Error("App Store Connect pagination exceeded its safety bound");
    }
    const page = await request(next, { token, method: "GET" });
    if (!Array.isArray(page?.data)) {
      throw new TypeError("App Store Connect list response is invalid");
    }
    data.push(...page.data);
    next = page.links?.next ? safeAPIURL(page.links.next).toString() : null;
    pageCount += 1;
  }
  return data;
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
}) {
  const reportRequests = await listAll(
    `/v1/apps/${encodeURIComponent(appId)}/analyticsReportRequests`,
    { request, token },
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
    { request, token },
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
      { request, token },
    );
    for (const instance of instances.slice(0, 31)) {
      const segments = await listAll(
        `/v1/analyticsReportInstances/${encodeURIComponent(instance.id)}/segments`,
        { request, token },
      );
      for (const segment of segments.slice(0, 4)) {
        const parsed = parseAnalyticsTSV(
          await downloadText(safeSegmentURL(segment.attributes?.url)),
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
    value: metric.numericCount > 0 ? metric.total : null,
    unit: "aggregate events",
    status: metric.numericCount > 0 ? "complete" : "insufficient-data",
    detail:
      metric.numericCount === 0 && metric.suppressed
        ? "privacy-threshold-suppressed"
        : null,
  }));
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
  });
  const processingState = build?.attributes?.processingState ?? "UNKNOWN";
  const buildAvailable = processingState === "VALID" && betaGroups.length > 0;
  const version = appStoreVersions[0] ?? null;
  const appStoreState = version?.attributes?.appStoreState ?? "UNKNOWN";
  const testflightAcceptance = acceptedEvidence(evidence, now);
  const processing = Boolean(build) && processingState !== "VALID";
  const signals = processing
    ? [
        {
          id: "app-store-connect:testflight-processing",
          severity: "info",
          title: "TestFlight build processing",
          summary: `Build ${build.attributes?.version ?? "unknown"} is still processing`,
          sourceUrl: APP_STORE_SOURCE,
        },
      ]
    : [];

  return {
    source: {
      id: "app-store-connect",
      label: "App Store Connect",
    },
    status: processing || !build ? "attention" : "healthy",
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
          : processing
            ? "processing"
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
        status: processing
          ? "processing"
          : buildAvailable
            ? "complete"
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
        status: SUBMITTED_STATES.has(appStoreState) ? "submitted" : "pending",
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
