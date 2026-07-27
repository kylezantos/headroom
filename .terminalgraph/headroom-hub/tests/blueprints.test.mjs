import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const manifestDirectory = new URL("../blueprints/", import.meta.url);

async function readManifest(name) {
  return JSON.parse(
    await readFile(new URL(`${name}.manifest.json`, manifestDirectory), "utf8"),
  );
}

function nodeByRef(manifest, ref) {
  return manifest.nodes.find((node) => node.ref === ref);
}

function assertPortable(manifest) {
  const serialized = JSON.stringify(manifest);
  assert.doesNotMatch(serialized, /\/Users\/|\/home\/|[A-Z]:\\/u);
  assert.doesNotMatch(
    serialized,
    /(?:authorization|bearer|private[_ -]?key|api[_ -]?key|phx_|sk-proj-)/iu,
  );
  assert.equal(manifest.portability.trackedBlueprint, false);

  const commands = manifest.nodes
    .map(({ command, restoreCommand }) => command ?? restoreCommand)
    .filter(Boolean)
    .join("\n");
  assert.doesNotMatch(
    commands,
    /\b(?:curl\s+-X\s+(?:POST|DELETE|PATCH)|git\s+push|gh\s+pr\s+merge|rm\s+-rf|pnpm\s+install|npm\s+install)\b/iu,
  );
}

test("control room has one reviewed delegation path and a closed gate", async () => {
  const manifest = await readManifest("headroom-control-room");
  assertPortable(manifest);

  assert.equal(manifest.group.layout, "freeform");
  assert.deepEqual(
    manifest.projects.map(({ label }) => label),
    ["headroom", "kz-portfolio"],
  );
  assert.equal(nodeByRef(manifest, "review-gate").initiallyOpen, false);
  assert.equal(nodeByRef(manifest, "refresh-trigger").intervalMilliseconds, 300000);

  const edges = manifest.connections.map(({ from, to }) => `${from}->${to}`);
  assert.deepEqual(
    edges.filter((edge) => /review-webhook|review-note|review-gate|agent\.text/u.test(edge)),
    [
      "review-webhook.output->review-note.write",
      "review-note.save-content->review-gate.input",
      "review-gate.output->agent.text",
      "agent.exit->review-gate.close",
    ],
  );
  assert.ok(edges.includes("agent.exit->review-gate.close"));
  assert.equal(manifest.security.reviewRequiredBeforeAgentInput, true);
  assert.equal(manifest.security.sourceMutationsAllowed, false);
});

test("app mission requires a fresh Headroom worktree and evidence closeout", async () => {
  const manifest = await readManifest("headroom-app-mission");
  assertPortable(manifest);

  assert.equal(manifest.project, "headroom");
  assert.equal(manifest.worktree.required, true);
  assert.equal(manifest.worktree.fallbackToRepositoryRoot, false);
  assert.equal(manifest.group.layout, "split_tree");
  assert.deepEqual(
    manifest.nodes.map(({ type }) => type),
    ["terminal", "terminal", "editor", "browser", "note"],
  );
  assert.equal(nodeByRef(manifest, "instructions").filePath, "${WORKTREE}/AGENTS.md");
  assert.equal(manifest.closeout.evidenceReviewRequired, true);
  assert.equal(manifest.closeout.implicitBranchOrWorktreeDeletion, false);
});

test("site mission is distinct and diagnoses setup without installing", async () => {
  const manifest = await readManifest("headroom-site-mission");
  assertPortable(manifest);

  assert.equal(manifest.project, "kz-portfolio");
  assert.equal(manifest.worktree.required, true);
  assert.equal(manifest.worktree.fallbackToRepositoryRoot, false);
  assert.equal(manifest.group.layout, "split_tree");
  assert.deepEqual(
    manifest.nodes.map(({ type }) => type),
    ["terminal", "terminal", "editor", "browser", "browser", "note"],
  );
  assert.match(nodeByRef(manifest, "diagnostics").command, /dependencies=missing/u);
  assert.doesNotMatch(
    nodeByRef(manifest, "diagnostics").command,
    /\b(?:pnpm|npm)\s+(?:install|dev|build|ship)\b/u,
  );
  assert.equal(manifest.closeout.implicitBranchOrWorktreeDeletion, false);
});
