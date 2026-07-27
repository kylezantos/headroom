import { createServer } from "node:http";
import { pathToFileURL } from "node:url";

import { readSnapshot } from "./collect.mjs";
import { createMissionBrief, renderDashboard } from "./render.mjs";

const LOOPBACK_HOST = "127.0.0.1";
const SECURITY_HEADERS = {
  "Cache-Control": "no-store",
  "Content-Security-Policy":
    "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'self'",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
};

function send(response, status, body, contentType = "text/plain; charset=utf-8") {
  response.writeHead(status, {
    ...SECURITY_HEADERS,
    "Content-Type": contentType,
  });
  response.end(body);
}

function validWebhookURL(value) {
  if (!value) {
    return null;
  }
  const url = new URL(value);
  if (
    url.protocol !== "http:"
    || !["127.0.0.1", "::1", "localhost"].includes(url.hostname)
    || url.username
    || url.password
  ) {
    throw new TypeError("delegation webhook must be loopback HTTP");
  }
  return url;
}

async function readBody(request, maxBytes = 8192) {
  let body = "";
  request.setEncoding("utf8");
  for await (const chunk of request) {
    body += chunk;
    if (Buffer.byteLength(body) > maxBytes) {
      throw new Error("request body is too large");
    }
  }
  return body;
}

async function forwardBrief(webhookURL, brief, fetchImpl) {
  if (!webhookURL) {
    return false;
  }
  const response = await fetchImpl(webhookURL, {
    method: "POST",
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
    },
    body: brief,
    redirect: "error",
    signal: AbortSignal.timeout(5_000),
  });
  if (!response.ok) {
    throw new Error("review-note webhook rejected the brief");
  }
  return true;
}

export async function startServer({
  snapshotProvider,
  snapshotPath = new URL("../data/snapshot.json", import.meta.url),
  webhookURL = null,
  host = LOOPBACK_HOST,
  port = 0,
  fetchImpl = fetch,
} = {}) {
  if (host !== LOOPBACK_HOST) {
    throw new TypeError("Headroom hub server must bind to 127.0.0.1");
  }
  const safeWebhookURL = validWebhookURL(webhookURL);
  const provideSnapshot =
    snapshotProvider ?? (() => readSnapshot(snapshotPath));
  let dashboardOrigin = null;
  const server = createServer(async (request, response) => {
    try {
      const requestURL = new URL(request.url, dashboardOrigin);
      if (request.method === "GET" && requestURL.pathname === "/") {
        const snapshot = await provideSnapshot();
        send(
          response,
          200,
          await renderDashboard(snapshot),
          "text/html; charset=utf-8",
        );
        return;
      }
      if (request.method === "GET" && requestURL.pathname === "/healthz") {
        send(response, 200, "ok\n");
        return;
      }
      if (request.method === "POST" && requestURL.pathname === "/delegate") {
        if (request.headers.origin !== dashboardOrigin) {
          send(response, 403, "Delegation origin rejected.\n");
          return;
        }
        if (
          !String(request.headers["content-type"] ?? "")
            .toLowerCase()
            .startsWith("application/x-www-form-urlencoded")
        ) {
          send(response, 415, "Unsupported delegation request.\n");
          return;
        }
        const parameters = new URLSearchParams(await readBody(request));
        const keys = [...parameters.keys()];
        if (
          keys.length !== 1
          || keys[0] !== "signalId"
          || parameters.getAll("signalId").length !== 1
        ) {
          send(response, 400, "Delegation accepts one signal identifier.\n");
          return;
        }
        const snapshot = await provideSnapshot();
        const brief = createMissionBrief(
          snapshot,
          parameters.get("signalId"),
        );
        if (!brief) {
          send(response, 404, "Signal not found.\n");
          return;
        }
        if (!await forwardBrief(safeWebhookURL, brief, fetchImpl)) {
          send(response, 503, "Review note is not connected.\n");
          return;
        }
        send(response, 202, "Mission brief staged for review.\n");
        return;
      }
      send(response, 404, "Not found.\n");
    } catch {
      send(response, 500, "Control room request failed safely.\n");
    }
  });

  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, host, resolve);
  });
  const address = server.address();
  dashboardOrigin = `http://${host}:${address.port}`;
  return {
    server,
    url: `${dashboardOrigin}/`,
    close: () =>
      new Promise((resolve, reject) =>
        server.close((error) => error ? reject(error) : resolve()),
      ),
  };
}

async function main() {
  const port = Number(process.env.HEADROOM_HUB_PORT ?? "0");
  if (!Number.isInteger(port) || port < 0 || port > 65_535) {
    throw new TypeError("HEADROOM_HUB_PORT must be a valid local port");
  }
  const running = await startServer({
    port,
    webhookURL: process.env.HEADROOM_HUB_WEBHOOK_URL ?? null,
  });
  process.stdout.write(`${running.url}\n`);
}

if (
  process.argv[1]
  && pathToFileURL(process.argv[1]).href === import.meta.url
) {
  main().catch(() => {
    process.stderr.write("Headroom hub server could not start safely.\n");
    process.exitCode = 1;
  });
}
