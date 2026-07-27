import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const FAILURE_CONCLUSIONS = new Set([
  "action_required",
  "cancelled",
  "failure",
  "startup_failure",
  "timed_out",
]);
const FAILURE_CHECK_BUCKETS = new Set(["cancel", "fail"]);
const FAILURE_CHECK_STATES = new Set([
  "CANCELLED",
  "ERROR",
  "FAILURE",
  "TIMED_OUT",
]);
const PULL_REQUEST_LIMIT = 100;

function parseJSON(value, label) {
  try {
    return JSON.parse(value);
  } catch {
    throw new TypeError(`${label} returned invalid structured output`);
  }
}

function repositoryID(repository) {
  return repository.split("/").at(-1).replace(/[^a-z0-9-]/giu, "-");
}

function runID(run) {
  const candidate = run.databaseId ?? run.url?.split("/").at(-1) ?? "unknown";
  return String(candidate).replace(/[^a-z0-9-]/giu, "-");
}

function newestTimestamp(values, fallback) {
  const timestamps = values
    .map((value) => new Date(value).valueOf())
    .filter(Number.isFinite);
  return timestamps.length > 0
    ? new Date(Math.max(...timestamps)).toISOString()
    : fallback.toISOString();
}

function checkFailed(check) {
  return (
    FAILURE_CHECK_BUCKETS.has(String(check.bucket ?? "").toLowerCase())
    || FAILURE_CHECK_STATES.has(String(check.state ?? "").toUpperCase())
  );
}

export async function defaultRunGh(args) {
  try {
    const { stdout } = await execFileAsync("gh", args, {
      encoding: "utf8",
      env: {
        ...process.env,
        GH_PAGER: "cat",
        NO_COLOR: "1",
      },
      maxBuffer: 1024 * 1024,
      timeout: 15_000,
    });
    return stdout;
  } catch (error) {
    const stdout = typeof error?.stdout === "string" ? error.stdout.trim() : "";
    if (stdout.startsWith("[") || stdout.startsWith("{")) {
      return stdout;
    }
    throw new Error("GitHub CLI read failed");
  }
}

async function readRepository(repository, runGh, now) {
  const [pullRequestOutput, runOutput, releaseOutput] = await Promise.all([
    runGh([
      "pr",
      "list",
      "--repo",
      repository,
      "--state",
      "open",
      "--limit",
      String(PULL_REQUEST_LIMIT),
      "--json",
      "number,title,url,isDraft,reviewDecision,statusCheckRollup,updatedAt",
    ]),
    runGh([
      "run",
      "list",
      "--repo",
      repository,
      "--limit",
      "20",
      "--json",
      "conclusion,createdAt,databaseId,displayTitle,status,updatedAt,url,workflowName",
    ]),
    runGh([
      "release",
      "list",
      "--repo",
      repository,
      "--limit",
      "5",
      "--json",
      "isDraft,isPrerelease,name,publishedAt,tagName",
    ]),
  ]);
  const pullRequests = parseJSON(pullRequestOutput, "gh pr list");
  const runs = parseJSON(runOutput, "gh run list");
  const releases = parseJSON(releaseOutput, "gh release list");

  const checksByPullRequest = new Map();
  await Promise.all(
    pullRequests.map(async (pullRequest) => {
      try {
        const output = await runGh([
          "pr",
          "checks",
          String(pullRequest.number),
          "--repo",
          repository,
          "--required",
          "--json",
          "bucket,link,name,state,workflow",
        ]);
        checksByPullRequest.set(
          pullRequest.number,
          parseJSON(output, "gh pr checks"),
        );
      } catch {
        checksByPullRequest.set(
          pullRequest.number,
          Array.isArray(pullRequest.statusCheckRollup)
            ? pullRequest.statusCheckRollup
            : [],
        );
      }
    }),
  );

  const cutoff = now.valueOf() - 7 * 24 * 60 * 60 * 1000;
  const failedRuns = runs.filter(
    (run) =>
      FAILURE_CONCLUSIONS.has(String(run.conclusion ?? "").toLowerCase())
      && new Date(run.createdAt).valueOf() >= cutoff,
  );
  return {
    repository,
    pullRequests,
    checksByPullRequest,
    runs,
    failedRuns,
    releases,
    pullRequestResultsMayBeTruncated:
      pullRequests.length >= PULL_REQUEST_LIMIT,
  };
}

export async function collectGitHub({
  repositories,
  runGh = defaultRunGh,
  now = new Date(),
}) {
  const repositoryResults = await Promise.all(
    repositories.map((repository) => readRepository(repository, runGh, now)),
  );
  const metrics = [];
  const signals = [];
  const evidenceTimestamps = [];

  for (const result of repositoryResults) {
    const id = repositoryID(result.repository);
    const failedChecks = [];
    if (result.pullRequestResultsMayBeTruncated) {
      signals.push({
        id: `github:${id}:open-pr-result-limit`,
        severity: "attention",
        title: `${result.repository}: open PR result limit reached`,
        summary: `At least ${PULL_REQUEST_LIMIT} open pull requests; the total may be higher`,
        sourceUrl: `https://github.com/${result.repository}/pulls`,
        repository: result.repository,
      });
    }
    for (const pullRequest of result.pullRequests) {
      evidenceTimestamps.push(pullRequest.updatedAt);
      const checks = result.checksByPullRequest.get(pullRequest.number) ?? [];
      for (const check of checks.filter(checkFailed)) {
        failedChecks.push(check);
        signals.push({
          id: `github:${id}:pr-${pullRequest.number}:${String(check.name ?? "check")
            .toLowerCase()
            .replace(/[^a-z0-9-]/gu, "-")}`,
          severity: "critical",
          title: `PR #${pullRequest.number}: ${pullRequest.title}`,
          summary: `Required check ${check.name ?? "unknown"} failed`,
          sourceUrl: pullRequest.url,
          repository: result.repository,
        });
      }
    }

    for (const run of result.failedRuns) {
      evidenceTimestamps.push(run.updatedAt ?? run.createdAt);
      signals.push({
        id: `github:${id}:workflow-${runID(run)}`,
        severity: "attention",
        title: `${result.repository}: ${run.workflowName ?? "Workflow"}`,
        summary: `${run.displayTitle ?? "Workflow run"} concluded ${run.conclusion}`,
        sourceUrl: run.url,
        repository: result.repository,
      });
    }
    for (const run of result.runs) {
      evidenceTimestamps.push(run.updatedAt ?? run.createdAt);
    }
    for (const release of result.releases) {
      evidenceTimestamps.push(release.publishedAt);
    }

    metrics.push(
      {
        id: `${id}.open-prs`,
        label: `${result.repository} open PRs`,
        value: result.pullRequests.length,
        unit: "pull requests",
      },
      {
        id: `${id}.blocked-prs`,
        label: `${result.repository} blocked PRs`,
        value: new Set(
          result.pullRequests
            .filter((pullRequest) =>
              (result.checksByPullRequest.get(pullRequest.number) ?? []).some(
                checkFailed,
              ),
            )
            .map(({ number }) => number),
        ).size,
        unit: "pull requests",
      },
      {
        id: `${id}.workflow-health`,
        label: `${result.repository} recent workflow failures`,
        value: result.runs.length === 0 ? null : result.failedRuns.length,
        unit: "runs",
        status: result.runs.length === 0
          ? "not-configured"
          : result.failedRuns.length > 0
            ? "pending"
            : "complete",
      },
      {
        id: `${id}.latest-release`,
        label: `${result.repository} latest release`,
        value: result.releases[0]?.tagName ?? null,
        status: result.releases.length === 0 ? "not-configured" : "complete",
      },
    );
  }

  return {
    source: { id: "github", label: "GitHub" },
    status: signals.length > 0 ? "attention" : "healthy",
    summary: signals.length > 0
      ? `${signals.length} GitHub items need attention`
      : "No blocked pull requests or recent workflow failures",
    evidenceAt: newestTimestamp(evidenceTimestamps, now),
    sourceUrl: `https://github.com/${repositories[0]}`,
    metrics,
    stages: [],
    signals,
  };
}

export function createGitHubAdapter({ config, runGh = defaultRunGh, now }) {
  return {
    id: "github",
    label: "GitHub",
    sourceUrl: `https://github.com/${config.github.repositories[0]}`,
    collect: () =>
      collectGitHub({
        repositories: config.github.repositories,
        runGh,
        now: now?.() ?? new Date(),
      }),
  };
}
