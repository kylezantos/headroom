const ALLOWED_HOSTS = new Set(["us.posthog.com", "eu.posthog.com"]);

function metricID(key) {
  return key
    .replace(/([a-z0-9])([A-Z])/gu, "$1-$2")
    .replace(/([a-z])(\d)/giu, "$1-$2")
    .replace(/[^a-z0-9-]/giu, "-")
    .toLowerCase();
}

function metricLabel(key) {
  return key
    .replace(/([a-z0-9])([A-Z])/gu, "$1 $2")
    .replace(/([a-z])(\d)/giu, "$1 $2")
    .replace(/(\d+)(d)$/iu, "$1 days")
    .replace(/^./u, (character) => character.toUpperCase());
}

function insightValue(payload) {
  if (typeof payload?.result === "number") {
    return payload.result;
  }
  if (Array.isArray(payload?.result)) {
    const counts = payload.result
      .map(({ count }) => count)
      .filter(Number.isFinite);
    if (counts.length > 0) {
      return counts.reduce((total, count) => total + count, 0);
    }
  }
  return null;
}

function newestTimestamp(values, fallback) {
  const dates = values
    .map((value) => new Date(value).valueOf())
    .filter(Number.isFinite);
  return dates.length > 0
    ? new Date(Math.max(...dates)).toISOString()
    : fallback.toISOString();
}

export async function defaultPostHogRequest(
  url,
  { apiKey, method = "GET" } = {},
) {
  if (method !== "GET") {
    throw new TypeError("PostHog collector permits GET only");
  }
  const response = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${apiKey}`,
    },
    redirect: "error",
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) {
    const error = new Error("PostHog read failed");
    error.status = response.status;
    throw error;
  }
  return response.json();
}

export async function collectPostHog({
  config,
  apiKey,
  request = defaultPostHogRequest,
  now = new Date(),
}) {
  const host = new URL(config.host);
  if (host.protocol !== "https:" || !ALLOWED_HOSTS.has(host.hostname)) {
    throw new TypeError("PostHog host is not allowed");
  }
  const configuredInsights = Object.entries(config.insightIds ?? {}).filter(
    ([, insightID]) => typeof insightID === "string" && insightID.length > 0,
  );
  if (!config.projectId || configuredInsights.length === 0 || !apiKey) {
    return {
      source: { id: "posthog", label: "PostHog" },
      status: "not-configured",
      reasonCode: "missing-configuration",
      summary: "PostHog read-only insights are not configured",
      sourceUrl: config.host,
    };
  }

  const metrics = [];
  const signals = [];
  const evidenceTimestamps = [];
  for (const [key, insightID] of configuredInsights) {
    const insightURL =
      `${host.origin}/api/projects/${encodeURIComponent(config.projectId)}`
      + `/insights/${encodeURIComponent(insightID)}/`;
    try {
      const payload = await request(insightURL, {
        apiKey,
        method: "GET",
      });
      const value = insightValue(payload);
      evidenceTimestamps.push(payload.last_refresh ?? payload.updated_at);
      metrics.push({
        id: metricID(key),
        label: metricLabel(key),
        value,
        unit: key.toLowerCase().includes("download")
          ? "downloads"
          : "views",
        status: value === null ? "insufficient-data" : "complete",
      });
    } catch (error) {
      if (error?.status !== 404) {
        throw new Error("PostHog insight read failed");
      }
      metrics.push({
        id: metricID(key),
        label: metricLabel(key),
        value: null,
        status: "unavailable",
        detail: "insight-not-found",
      });
      signals.push({
        id: `posthog:${metricID(key)}:missing`,
        severity: "attention",
        title: `${metricLabel(key)} unavailable`,
        summary: "The configured PostHog insight no longer exists",
        sourceUrl: `${host.origin}/project/${encodeURIComponent(config.projectId)}`,
      });
    }
  }

  return {
    source: { id: "posthog", label: "PostHog" },
    status: signals.length > 0 ? "attention" : "healthy",
    summary: signals.length > 0
      ? `${signals.length} PostHog insight needs attention`
      : "Configured aggregate website insights are current",
    evidenceAt: newestTimestamp(evidenceTimestamps, now),
    sourceUrl: `${host.origin}/project/${encodeURIComponent(config.projectId)}`,
    metrics,
    stages: [],
    signals,
  };
}

export function createPostHogAdapter({
  config,
  environment = process.env,
  request = defaultPostHogRequest,
  now,
}) {
  return {
    id: "posthog",
    label: "PostHog",
    sourceUrl: config.posthog.host,
    collect: () =>
      collectPostHog({
        config: config.posthog,
        apiKey: environment.HEADROOM_POSTHOG_API_KEY ?? "",
        request,
        now: now?.() ?? new Date(),
      }),
  };
}
