export const REDACTED = "‹redacted›";

const replacements = [
  [
    /-----BEGIN [^-]*PRIVATE KEY-----[\s\S]*?-----END [^-]*PRIVATE KEY-----/giu,
    REDACTED,
  ],
  [
    /\bAuthorization\s*:\s*(?:Bearer|Basic)\s+[^\s,;]+/giu,
    `Authorization: ${REDACTED}`,
  ],
  [
    /\b(?:access_token|api_key|authorization|password|refresh_token|token)\s*[=:]\s*["']?[^"'\s,;]+["']?/giu,
    REDACTED,
  ],
  [
    /\b(?:phx_|sk-proj-|sk-ant-admin|sk-ant-|sk-|sess-)[A-Za-z0-9_-]{8,}/gu,
    REDACTED,
  ],
  [
    /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\b/gu,
    REDACTED,
  ],
  [
    /(?:^|[\s="'(])(?:\/[^/\s"'=]+)+\/AuthKey_[A-Za-z0-9_-]+\.p8\b/giu,
    (match) => `${match[0] ?? ""}${REDACTED}`,
  ],
  [
    /\b[A-Z]:\\(?:[^\\\s"'=]+\\)+AuthKey_[A-Za-z0-9_-]+\.p8\b/giu,
    REDACTED,
  ],
  [
    /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/giu,
    REDACTED,
  ],
  [
    /\b[A-Za-z0-9_-]{48,}\b/gu,
    REDACTED,
  ],
];

export function redactText(value) {
  let result = String(value ?? "");
  for (const [pattern, replacement] of replacements) {
    result = result.replace(pattern, replacement);
  }
  return result;
}

export function redactValue(value) {
  if (typeof value === "string") {
    return redactText(value);
  }
  if (Array.isArray(value)) {
    return value.map(redactValue);
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, nestedValue]) => [
        key,
        redactValue(nestedValue),
      ]),
    );
  }
  return value;
}
