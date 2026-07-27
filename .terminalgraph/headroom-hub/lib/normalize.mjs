import { redactText } from "./redact.mjs";

const CURRENT_STATUSES = new Set(["healthy", "attention"]);
const FAILURE_STATUSES = new Set([
  "unavailable",
  "unknown",
  "not-configured",
]);
const STAGE_STATUSES = new Set([
  "complete",
  "pending",
  "processing",
  "accepted",
  "pending-acceptance",
  "submitted",
  "insufficient-data",
  "unavailable",
  "unknown",
  "not-configured",
  "rejected",
]);
const SIGNAL_SEVERITIES = new Set(["info", "attention", "critical"]);
const SOURCE_HOSTS = new Set([
  "appstoreconnect.apple.com",
  "developer.apple.com",
  "eu.posthog.com",
  "github.com",
  "headroom.zantos.co",
  "us.posthog.com",
]);

function asISODate(value, fallback = null) {
  if (value === undefined || value === null || value === "") {
    return fallback;
  }
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.valueOf()) ? fallback : date.toISOString();
}

function safeIdentifier(value, label) {
  if (
    typeof value !== "string"
    || !/^[a-z0-9][a-z0-9._:-]*$/u.test(value)
  ) {
    throw new TypeError(`${label} must be a stable lowercase identifier`);
  }
  return value;
}

function safeText(value, fallback = "") {
  return redactText(typeof value === "string" ? value : fallback);
}

function safeSourceURL(value) {
  if (typeof value !== "string" || value.length === 0) {
    return null;
  }
  try {
    const url = new URL(value);
    if (
      url.protocol !== "https:"
      || !SOURCE_HOSTS.has(url.hostname)
      || url.username
      || url.password
      || url.port
    ) {
      return null;
    }
    return url.toString();
  } catch {
    return null;
  }
}

function normalizeMetric(metric) {
  const value =
    typeof metric.value === "number"
    || typeof metric.value === "string"
    || metric.value === null
      ? metric.value
      : null;
  return {
    id: safeIdentifier(metric.id, "metric.id"),
    label: safeText(metric.label, metric.id),
    value: typeof value === "string" ? safeText(value) : value,
    unit: typeof metric.unit === "string" ? safeText(metric.unit) : null,
    status:
      typeof metric.status === "string" && STAGE_STATUSES.has(metric.status)
        ? metric.status
        : null,
    detail: typeof metric.detail === "string" ? safeText(metric.detail) : null,
  };
}

function normalizeStage(stage) {
  return {
    id: safeIdentifier(stage.id, "stage.id"),
    label: safeText(stage.label, stage.id),
    status: STAGE_STATUSES.has(stage.status) ? stage.status : "unknown",
    evidenceAt: asISODate(stage.evidenceAt),
    detail: typeof stage.detail === "string" ? safeText(stage.detail) : null,
  };
}

function normalizeSignal(signal, fallbackURL) {
  return {
    id: safeIdentifier(signal.id, "signal.id"),
    severity: SIGNAL_SEVERITIES.has(signal.severity)
      ? signal.severity
      : "attention",
    title: safeText(signal.title, signal.id),
    summary: safeText(signal.summary),
    sourceUrl: safeSourceURL(signal.sourceUrl) ?? fallbackURL,
    repository:
      typeof signal.repository === "string"
        ? safeText(signal.repository)
        : null,
  };
}

function emptySource(source, status, summary, reasonCode, nowISO, sourceUrl) {
  return {
    id: safeIdentifier(source.id, "source.id"),
    label: safeText(source.label, source.id),
    status,
    retainedStatus: null,
    summary: safeText(summary),
    detail: null,
    diagnostic: safeIdentifier(reasonCode ?? "source-unavailable", "reasonCode"),
    sourceUrl: safeSourceURL(sourceUrl),
    freshness: {
      kind: "unknown",
      collectedAt: nowISO,
      evidenceAt: null,
      lastSuccessAt: null,
      staleAgeSeconds: null,
    },
    metrics: [],
    stages: [],
    signals: [],
  };
}

export function normalizeResult(
  result,
  {
    now = new Date(),
    previous = null,
    cacheMaxAgeSeconds = 86_400,
  } = {},
) {
  if (!result?.source) {
    throw new TypeError("adapter result must identify its source");
  }
  const nowISO = asISODate(now);
  if (!nowISO) {
    throw new TypeError("now must be a valid date");
  }

  if (CURRENT_STATUSES.has(result.status)) {
    const sourceUrl = safeSourceURL(result.sourceUrl);
    return {
      id: safeIdentifier(result.source.id, "source.id"),
      label: safeText(result.source.label, result.source.id),
      status: result.status,
      retainedStatus: null,
      summary: safeText(result.summary),
      detail: typeof result.detail === "string" ? safeText(result.detail) : null,
      diagnostic: null,
      sourceUrl,
      freshness: {
        kind: "current",
        collectedAt: nowISO,
        evidenceAt: asISODate(result.evidenceAt, nowISO),
        lastSuccessAt: nowISO,
        staleAgeSeconds: 0,
      },
      metrics: Array.isArray(result.metrics)
        ? result.metrics.map(normalizeMetric)
        : [],
      stages: Array.isArray(result.stages)
        ? result.stages.map(normalizeStage)
        : [],
      signals: Array.isArray(result.signals)
        ? result.signals.map((signal) => normalizeSignal(signal, sourceUrl))
        : [],
    };
  }

  const failureStatus = FAILURE_STATUSES.has(result.status)
    ? result.status
    : "unknown";
  const lastSuccessAt = asISODate(previous?.freshness?.lastSuccessAt);
  if (previous && lastSuccessAt) {
    const staleAgeSeconds = Math.max(
      0,
      Math.floor((new Date(nowISO) - new Date(lastSuccessAt)) / 1000),
    );
    if (staleAgeSeconds <= cacheMaxAgeSeconds) {
      return {
        id: previous.id,
        label: previous.label,
        status: "stale",
        retainedStatus:
          previous.status === "stale"
            ? previous.retainedStatus
            : previous.status,
        summary: safeText(result.summary, "Refresh failed"),
        detail:
          typeof result.detail === "string" ? safeText(result.detail) : null,
        diagnostic: safeIdentifier(
          result.reasonCode ?? "refresh-failed",
          "reasonCode",
        ),
        sourceUrl: safeSourceURL(result.sourceUrl) ?? previous.sourceUrl,
        freshness: {
          kind: "retained",
          collectedAt: nowISO,
          evidenceAt: previous.freshness.evidenceAt,
          lastSuccessAt,
          staleAgeSeconds,
        },
        metrics: previous.metrics,
        stages: previous.stages,
        signals: [],
      };
    }

    return {
      ...emptySource(
        result.source,
        "unknown",
        result.summary,
        "cache-expired",
        nowISO,
        result.sourceUrl ?? previous.sourceUrl,
      ),
      diagnostic: "cache-expired",
    };
  }

  return emptySource(
    result.source,
    failureStatus,
    result.summary,
    result.reasonCode,
    nowISO,
    result.sourceUrl,
  );
}

export function normalizeSnapshot(
  results,
  {
    now = new Date(),
    previousSnapshot = null,
    cacheMaxAgeSeconds = 86_400,
  } = {},
) {
  const previousByID = new Map(
    (previousSnapshot?.sources ?? []).map((source) => [source.id, source]),
  );
  const sources = results.map((result) =>
    normalizeResult(result, {
      now,
      previous: previousByID.get(result.source.id) ?? null,
      cacheMaxAgeSeconds,
    }),
  );
  const complete = sources.every(
    (source) =>
      source.freshness.kind === "current"
      && CURRENT_STATUSES.has(source.status),
  );
  const attentionCount = sources.reduce(
    (count, source) =>
      count
      + (source.status === "attention" ? 1 : 0)
      + source.signals.filter(
        ({ severity }) => severity === "attention" || severity === "critical",
      ).length,
    0,
  );

  return {
    schemaVersion: 1,
    collectedAt: asISODate(now),
    overall: {
      status: attentionCount > 0
        ? "attention"
        : complete
          ? "healthy"
          : "partial",
      completeness: complete ? "complete" : "partial",
      attentionCount,
    },
    sources,
  };
}

