const ALLOWED_REPOSITORIES = new Set([
  "kylezantos/headroom",
  "kylezantos/kz-portfolio",
]);

const ALLOWED_POSTHOG_HOSTS = new Set([
  "us.posthog.com",
  "eu.posthog.com",
]);

const APP_STORE_ENVIRONMENT_KEYS = [
  "HEADROOM_ASC_KEY_PATH",
  "HEADROOM_ASC_KEY_ID",
  "HEADROOM_ASC_ISSUER_ID",
];

function assertObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError(`${label} must be an object`);
  }
}

function validatedURL(value, label, allowedHosts) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new TypeError(`${label} must be a valid URL`);
  }
  if (url.protocol !== "https:") {
    throw new TypeError(`${label} must use HTTPS`);
  }
  if (!allowedHosts.has(url.hostname) || url.username || url.password || url.port) {
    throw new TypeError(`${label} host is not allowed`);
  }
  return url;
}

export function validateConfig(config) {
  assertObject(config, "config");
  if (config.schemaVersion !== 1) {
    throw new TypeError("config.schemaVersion must equal 1");
  }

  assertObject(config.github, "config.github");
  if (
    !Array.isArray(config.github.repositories)
    || config.github.repositories.length === 0
    || config.github.repositories.some(
      (repository) => !ALLOWED_REPOSITORIES.has(repository),
    )
  ) {
    throw new TypeError("config.github.repositories contains a repository that is not allowed");
  }

  assertObject(config.website, "config.website");
  const websiteURL = validatedURL(
    config.website.baseUrl,
    "config.website.baseUrl",
    new Set(["headroom.zantos.co"]),
  );
  if (websiteURL.pathname !== "/" || websiteURL.search || websiteURL.hash) {
    throw new TypeError("config.website.baseUrl must be the Headroom site origin");
  }

  assertObject(config.posthog, "config.posthog");
  validatedURL(
    config.posthog.host,
    "config.posthog.host",
    ALLOWED_POSTHOG_HOSTS,
  );
  assertObject(config.posthog.insightIds, "config.posthog.insightIds");

  assertObject(config.appStoreConnect, "config.appStoreConnect");
  if (
    config.appStoreConnect.analyticsReportRequestId !== undefined
    && typeof config.appStoreConnect.analyticsReportRequestId !== "string"
  ) {
    throw new TypeError(
      "config.appStoreConnect.analyticsReportRequestId must be a string",
    );
  }

  if (config.refresh !== undefined) {
    assertObject(config.refresh, "config.refresh");
    for (const key of ["staleAfterSeconds", "cacheMaxAgeSeconds"]) {
      if (
        !Number.isInteger(config.refresh[key])
        || config.refresh[key] <= 0
      ) {
        throw new TypeError(`config.refresh.${key} must be a positive integer`);
      }
    }
  }

  return config;
}

function presence(environment, key) {
  return typeof environment[key] === "string" && environment[key].length > 0;
}

export function preflight(
  config,
  {
    environment = process.env,
    githubAuthenticated = false,
  } = {},
) {
  validateConfig(config);

  const missingAppleKeys = APP_STORE_ENVIRONMENT_KEYS.filter(
    (key) => !presence(environment, key),
  );
  const presentAppleKeyCount =
    APP_STORE_ENVIRONMENT_KEYS.length - missingAppleKeys.length;
  let appStoreConnect;
  if (presentAppleKeyCount === 0) {
    appStoreConnect = { status: "not-configured" };
  } else if (missingAppleKeys.length > 0) {
    appStoreConnect = {
      status: "incomplete",
      missing: missingAppleKeys,
    };
  } else {
    appStoreConnect = { status: "ready" };
  }

  const credentials = {
    github: {
      status: githubAuthenticated ? "ready" : "setup-required",
    },
    posthog: {
      status: presence(environment, "HEADROOM_POSTHOG_API_KEY")
        ? "ready"
        : "not-configured",
    },
    appStoreConnect,
  };

  return {
    ok: Object.values(credentials).every(({ status }) => status === "ready"),
    config: { status: "ready" },
    credentials,
  };
}
