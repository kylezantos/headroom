function requiredResponse(response, label) {
  if (!response || response.status < 200 || response.status >= 300) {
    throw new Error(`${label} is unavailable`);
  }
  return response;
}

function header(response, name) {
  if (typeof response.headers?.get === "function") {
    return response.headers.get(name);
  }
  return response.headers?.[name] ?? response.headers?.[name.toLowerCase()] ?? null;
}

function appcastValue(xml, expression, label) {
  const match = xml.match(expression);
  if (!match) {
    throw new TypeError(`appcast is missing ${label}`);
  }
  return match[1].trim();
}

function parseAppcast(xml) {
  const firstItem = xml.match(/<item\b[^>]*>([\s\S]*?)<\/item>/iu)?.[1];
  if (!firstItem) {
    throw new TypeError("appcast has no release item");
  }
  return {
    version: appcastValue(
      firstItem,
      /<sparkle:shortVersionString>([^<]+)<\/sparkle:shortVersionString>/iu,
      "short version",
    ),
    build: appcastValue(
      firstItem,
      /<sparkle:version>([^<]+)<\/sparkle:version>/iu,
      "build",
    ),
    downloadUrl: appcastValue(
      firstItem,
      /<enclosure\b[^>]*\burl="([^"]+)"/iu,
      "download URL",
    ),
  };
}

function validPublicURL(value, expectedOrigin, expectedPath = null) {
  try {
    const url = new URL(value);
    return (
      url.protocol === "https:"
      && url.origin === expectedOrigin
      && !url.username
      && !url.password
      && (expectedPath === null || url.pathname === expectedPath)
    );
  } catch {
    return false;
  }
}

function evidenceState(evidence, now, maxAgeSeconds) {
  if (!evidence) {
    return { evidence: null, diagnostic: "evidence-absent" };
  }
  if (
    evidence.schemaVersion !== 1
    || typeof evidence.recordedAt !== "string"
    || typeof evidence.sourceReference !== "string"
    || !/^docs\/release\/[a-z0-9._/-]+\.md$/u.test(evidence.sourceReference)
    || evidence.sourceReference.includes("..")
    || !evidence.stages
    || typeof evidence.stages !== "object"
  ) {
    return { evidence: null, diagnostic: "evidence-invalid" };
  }
  const recordedAt = new Date(evidence.recordedAt);
  if (
    Number.isNaN(recordedAt.valueOf())
    || now.valueOf() - recordedAt.valueOf() > maxAgeSeconds * 1000
    || recordedAt.valueOf() > now.valueOf() + 60_000
  ) {
    return { evidence: null, diagnostic: "evidence-expired" };
  }
  return { evidence, diagnostic: "evidence-current" };
}

export async function defaultWebsiteRequest(url, { method = "GET" } = {}) {
  const response = await fetch(url, {
    method,
    redirect: "error",
    signal: AbortSignal.timeout(15_000),
  });
  return {
    status: response.status,
    body: method === "HEAD" ? "" : await response.text(),
    headers: {
      "content-length": response.headers.get("content-length"),
      "last-modified": response.headers.get("last-modified"),
    },
  };
}

export async function collectWebsite({
  baseUrl,
  request = defaultWebsiteRequest,
  readEvidence = async () => null,
  now = new Date(),
  evidenceMaxAgeSeconds = 30 * 24 * 60 * 60,
}) {
  const origin = new URL(baseUrl).origin;
  if (origin !== "https://headroom.zantos.co") {
    throw new TypeError("website origin is not allowed");
  }
  const urls = {
    page: `${origin}/`,
    privacy: `${origin}/privacy`,
    latest: `${origin}/latest.json`,
    appcast: `${origin}/appcast.xml`,
    stableDownload: `${origin}/Headroom.dmg`,
  };
  const [page, privacy, latestResponse, appcastResponse, download, localEvidence] =
    await Promise.all([
      request(urls.page),
      request(urls.privacy),
      request(urls.latest),
      request(urls.appcast),
      request(urls.stableDownload, { method: "HEAD" }),
      readEvidence(),
    ]);
  requiredResponse(page, "Headroom site");
  requiredResponse(privacy, "Headroom privacy page");
  requiredResponse(latestResponse, "latest.json");
  requiredResponse(appcastResponse, "Sparkle appcast");
  requiredResponse(download, "stable DMG");

  let latest;
  try {
    latest = JSON.parse(latestResponse.body);
  } catch {
    throw new TypeError("latest.json is invalid");
  }
  const appcast = parseAppcast(appcastResponse.body);
  const manifestURLsValid =
    validPublicURL(latest.downloadUrl, origin, "/Headroom.dmg")
    && validPublicURL(latest.versionedDownloadUrl, origin)
    && validPublicURL(latest.appcastUrl, origin, "/appcast.xml")
    && validPublicURL(appcast.downloadUrl, origin);
  const contentLength = Number(header(download, "content-length"));
  const lengthMatches =
    Number.isFinite(contentLength)
    && Number(latest.size) === contentLength;
  const releaseMatches =
    String(latest.version) === appcast.version
    && String(latest.build) === appcast.build
    && latest.versionedDownloadUrl === appcast.downloadUrl
    && lengthMatches
    && manifestURLsValid;

  const { evidence, diagnostic } = evidenceState(
    localEvidence,
    now,
    evidenceMaxAgeSeconds,
  );
  const sparkleEvidence = evidence?.stages?.sparkleAccepted;
  const sparkleStatus =
    sparkleEvidence?.status === "accepted"
      ? "accepted"
      : sparkleEvidence?.status === "pending"
        ? "pending"
        : "unknown";
  const signals = releaseMatches
    ? []
    : [
        {
          id: "website:macos-release-mismatch",
          severity: "critical",
          title: "macOS distribution mismatch",
          summary: "latest.json and appcast.xml do not agree",
          sourceUrl: urls.latest,
        },
      ];

  return {
    source: { id: "website", label: "Website + Sparkle" },
    status: releaseMatches ? "healthy" : "attention",
    summary: releaseMatches
      ? `Headroom ${latest.version} (${latest.build}) is publicly consistent`
      : "Public macOS release surfaces are inconsistent",
    evidenceAt: latest.publishedAt,
    sourceUrl: urls.page,
    metrics: [
      {
        id: "site",
        label: "Public site",
        value: "reachable",
        status: "complete",
      },
      {
        id: "privacy",
        label: "Privacy page",
        value: "reachable",
        status: "complete",
      },
      {
        id: "macos-version",
        label: "Public macOS version",
        value: String(latest.version ?? ""),
        detail: `build ${latest.build ?? "unknown"}`,
        status: releaseMatches ? "complete" : "pending",
      },
      {
        id: "stable-download",
        label: "Stable DMG metadata",
        value: Number.isFinite(contentLength) ? contentLength : null,
        unit: "bytes",
        status: lengthMatches ? "complete" : "pending",
      },
      {
        id: "operator-evidence",
        label: "Operator evidence",
        value: evidence ? evidence.recordedAt : null,
        status: evidence ? "complete" : "unavailable",
        detail: diagnostic,
      },
    ],
    stages: [
      {
        id: "macos-published",
        label: "macOS published",
        status: releaseMatches ? "complete" : "pending",
        evidenceAt: latest.publishedAt,
      },
      {
        id: "sparkle-accepted",
        label: "Sparkle accepted",
        status: sparkleStatus,
        evidenceAt: sparkleEvidence?.evidenceAt ?? null,
      },
    ],
    signals,
  };
}

export function createWebsiteAdapter({
  config,
  request = defaultWebsiteRequest,
  readEvidence,
  now,
}) {
  return {
    id: "website",
    label: "Website + Sparkle",
    sourceUrl: config.website.baseUrl,
    collect: () =>
      collectWebsite({
        baseUrl: config.website.baseUrl,
        request,
        readEvidence,
        now: now?.() ?? new Date(),
      }),
  };
}
