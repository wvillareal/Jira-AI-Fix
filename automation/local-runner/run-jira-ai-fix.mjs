#!/usr/bin/env node
/**
 * Local Desktop agent runner for jira-ai-fix.
 *
 * Runs on THIS machine (not Cloud): loads user skills from ~/.cursor/skills,
 * uses local repos under REPO_ROOT, and follows DRAFT_JIRA_COMMENT.
 *
 * Usage:
 *   node run-jira-ai-fix.mjs --jira ST-13297 [--cwd C:\i21Source] [--model auto]
 *
 * Auth: CURSOR_API_KEY env (or --api-key).
 */
import { Agent, Cursor, CursorAgentError, JsonlLocalAgentStore } from "@cursor/sdk";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const DEFAULT_MAX_ATTEMPTS = 3;
const RETRY_DELAY_MS = 5000;

function arg(name, fallback = undefined) {
  const i = process.argv.indexOf(name);
  if (i >= 0 && process.argv[i + 1]) return process.argv[i + 1];
  return fallback;
}

function readJson(p) {
  try {
    return JSON.parse(fs.readFileSync(p, "utf8"));
  } catch {
    return null;
  }
}

function draftsDir() {
  return path.join(os.homedir(), ".jira-ai-drafts");
}

function automationLogDir() {
  return path.join(os.homedir(), ".jira-ai-automation", "logs");
}

function failureLogsDir() {
  const dir = path.join(automationLogDir(), "failures");
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function resolveRepoRoot() {
  const fromArg = arg("--cwd");
  if (fromArg) return path.resolve(fromArg);

  const userCfg = readJson(path.join(os.homedir(), ".jira-ai-config.json"));
  if (userCfg?.i21?.repoRoot) return path.resolve(String(userCfg.i21.repoRoot));

  const autoCfg = readJson(path.join(os.homedir(), ".jira-ai-automation", "config.json"));
  if (autoCfg?.localCwd) return path.resolve(String(autoCfg.localCwd));

  return path.resolve("C:\\i21Source");
}

function buildPrompt(jiraKey) {
  return [
    `jira-ai-fix ${jiraKey}`,
    "",
    "Mode: DRAFT_JIRA_COMMENT",
    "",
    "Run the real jira-ai-fix skill end-to-end on this machine.",
    "If a fix is implemented, create/reuse the feature branch and commit locally.",
    "HARD STOP: do not run git push or upload any branch/commit to a remote.",
    "Author the section 6 RCA but do NOT post to Jira.",
    "Jira comment voice: short, direct, and professional.",
    "Keep the required section 6 blocks; compress prose inside each block.",
    "Short sentences and tight bullets. No filler, hedging, casual tone, or emoji.",
    "At the end emit exactly one fenced block:",
    "",
    "```jira-rca-draft",
    "...full section 6 RCA / Acceptance Verification markdown...",
    "```",
    "",
    `Also write the same body to %USERPROFILE%\\.jira-ai-drafts\\${jiraKey}-rca.md when possible.`,
  ].join("\n");
}

function extractDraft(text) {
  if (!text) return null;
  const m = String(text).match(/```jira-rca-draft\s*\r?\n([\s\S]*?)\r?\n```/);
  return m ? m[1].replace(/\s+$/, "") : null;
}

function saveDraft(jiraKey, body, meta) {
  const dir = draftsDir();
  fs.mkdirSync(dir, { recursive: true });
  const md = path.join(dir, `${jiraKey}-rca.md`);
  const metaPath = path.join(dir, `${jiraKey}-meta.json`);
  fs.writeFileSync(md, body, "utf8");
  fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2), "utf8");
  return { md, metaPath };
}

function log(msg) {
  const line = `${new Date().toISOString()} [local-runner] ${msg}`;
  console.log(line);
  try {
    const logDir = automationLogDir();
    fs.mkdirSync(logDir, { recursive: true });
    const day = new Date().toISOString().slice(0, 10).replace(/-/g, "");
    fs.appendFileSync(path.join(logDir, `local-runner-${day}.log`), line + "\n");
  } catch {
    /* ignore */
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function errText(err) {
  if (!err) return "";
  if (typeof err === "string") return err;
  return [err.name, err.message, err.stack].filter(Boolean).join("\n");
}

function classifyFailure(err, context = {}) {
  const text = errText(err);
  const lower = text.toLowerCase();
  const status = context.status || "";

  if (
    err?.name === "AbortError" ||
    err?.code === 20 ||
    /operation was aborted|onstall|reportstall|stalldetected|aborted/i.test(text)
  ) {
    return {
      phase: "local-agent-execution",
      why: "Cursor SDK aborted the local agent run.",
      rootCause:
        "SDK stall detector (onStall/AbortError): the agent made no progress long enough to be treated as hung.",
      retryable: true,
      errorName: err?.name || "AbortError",
    };
  }

  if (err instanceof CursorAgentError) {
    return {
      phase: "local-agent-startup",
      why: `Cursor agent failed to start: ${err.message}`,
      rootCause: err.isRetryable
        ? "Transient CursorAgentError (SDK marked retryable)."
        : "Non-retryable CursorAgentError during agent startup/config/auth.",
      retryable: Boolean(err.isRetryable),
      errorName: "CursorAgentError",
    };
  }

  if (status === "error" || /run failed mid-flight/i.test(text)) {
    return {
      phase: "local-agent-execution",
      why: "Local agent run finished with status=error before producing a usable draft.",
      rootCause: "Agent runtime reported an error status mid-flight.",
      retryable: true,
      errorName: status || "run-error",
    };
  }

  if (/cursor_api_key|api key/i.test(lower)) {
    return {
      phase: "preflight-auth",
      why: "CURSOR_API_KEY missing or rejected.",
      rootCause: "Authentication/configuration failure before agent start.",
      retryable: false,
      errorName: err?.name || "AuthError",
    };
  }

  if (/cwd does not exist/i.test(lower)) {
    return {
      phase: "preflight-cwd",
      why: "Configured local cwd / repo root does not exist.",
      rootCause: "Invalid localCwd / i21.repoRoot path.",
      retryable: false,
      errorName: err?.name || "PathError",
    };
  }

  return {
    phase: context.phase || "local-runner",
    why: err?.message || String(err) || "Unknown local-runner failure.",
    rootCause: text || "No detailed stack was captured.",
    retryable: false,
    errorName: err?.name || "Error",
  };
}

function writeFailureReport(jiraKey, report) {
  const dir = failureLogsDir();
  const failurePath = path.join(dir, `${jiraKey}-failure.txt`);
  const lines = [
    `Jira: ${jiraKey}`,
    `Time: ${report.failedAt || new Date().toISOString()}`,
    `Process: ${report.process || "local-runner / Cursor SDK jira-ai-fix"}`,
    `Failed part: ${report.phase}`,
    `Why it failed: ${report.why}`,
    `Root cause: ${report.rootCause}`,
    `Retryable: ${report.retryable ? "yes" : "no"}`,
    `Attempts: ${report.attempts || 1}/${report.maxAttempts || 1}`,
    `Exit code: ${report.exitCode ?? ""}`,
    `Error name: ${report.errorName || ""}`,
    `Cwd: ${report.cwd || ""}`,
    `Model: ${report.model || ""}`,
    `Run id: ${report.runId || ""}`,
    "",
    "Details / stack:",
    report.details || "(none)",
    "",
  ];
  fs.writeFileSync(failurePath, lines.join("\n"), "utf8");
  log(`Failure report written ${failurePath}`);
  return failurePath;
}

function removeRcaArtifacts(jiraKey) {
  const dir = draftsDir();
  for (const name of [`${jiraKey}-rca.md`, `${jiraKey}-meta.json`, `${jiraKey}-notify.md`]) {
    const p = path.join(dir, name);
    if (fs.existsSync(p)) {
      fs.unlinkSync(p);
      log(`Removed incomplete artifact ${p}`);
    }
  }
}

async function runOnce({ jiraKey, apiKey, cwd, modelId, prompt, storeRoot, attempt, maxAttempts }) {
  log(`Attempt ${attempt}/${maxAttempts} starting local agent for ${jiraKey} cwd=${cwd} model=${modelId}`);

  const result = await Agent.prompt(prompt, {
    apiKey,
    model: { id: modelId },
    local: {
      cwd,
      settingSources: ["user", "project", "plugins"],
      store: new JsonlLocalAgentStore(storeRoot),
    },
  });

  const status = result?.status || "unknown";
  const runId = result?.id || "";
  const text =
    result?.result ||
    result?.text ||
    (typeof result === "string" ? result : "") ||
    "";

  log(`Attempt ${attempt}/${maxAttempts} finished status=${status} id=${runId}`);

  if (status === "error") {
    const classified = classifyFailure(new Error("run failed mid-flight"), {
      status,
      phase: "local-agent-execution",
    });
    const err = new Error(classified.why);
    err.classified = classified;
    err.runId = runId;
    err.status = status;
    throw err;
  }

  let draft = extractDraft(text);
  if (!draft) {
    log("No jira-rca-draft fence; saving full assistant text as fallback");
    draft = text || `(no result text; status=${status})`;
  }

  const meta = {
    jiraKey,
    mode: "local",
    dryRun: false,
    finishedAt: new Date().toISOString(),
    runId,
    status,
    cwd,
    model: modelId,
    attempts: attempt,
    prCreated: false,
  };
  const saved = saveDraft(jiraKey, draft, meta);
  log(`Draft saved ${saved.md}`);

  return {
    ok: true,
    jiraKey,
    status,
    runId,
    draftPath: saved.md,
    metaPath: saved.metaPath,
    attempts: attempt,
  };
}

async function main() {
  const jiraKey = (arg("--jira") || arg("-j") || "").toUpperCase();
  if (!jiraKey || !/^[A-Z][A-Z0-9]+-\d+$/.test(jiraKey)) {
    console.error("Usage: node run-jira-ai-fix.mjs --jira ST-12345 [--cwd C:\\i21Source] [--model auto]");
    process.exit(2);
  }

  const apiKey = (arg("--api-key") || process.env.CURSOR_API_KEY || "").trim();
  if (!apiKey) {
    const failurePath = writeFailureReport(jiraKey, {
      process: "local-runner preflight",
      phase: "preflight-auth",
      why: "CURSOR_API_KEY is required (Cursor Dashboard → API Keys).",
      rootCause: "Missing API key in process/user environment.",
      retryable: false,
      attempts: 0,
      maxAttempts: 0,
      exitCode: 1,
      errorName: "AuthError",
      details: "Set CURSOR_API_KEY before launching the local runner.",
    });
    console.error("CURSOR_API_KEY is required (Cursor Dashboard → API Keys).");
    console.log(JSON.stringify({ ok: false, jiraKey, failurePath, status: "auth-missing" }));
    process.exit(1);
  }

  const cwd = resolveRepoRoot();
  if (!fs.existsSync(cwd)) {
    const failurePath = writeFailureReport(jiraKey, {
      process: "local-runner preflight",
      phase: "preflight-cwd",
      why: `cwd does not exist: ${cwd}`,
      rootCause: "Invalid localCwd / i21.repoRoot path.",
      retryable: false,
      attempts: 0,
      maxAttempts: 0,
      exitCode: 1,
      errorName: "PathError",
      cwd,
      details: `Configured cwd path was missing on disk: ${cwd}`,
    });
    console.error(`cwd does not exist: ${cwd}`);
    console.log(JSON.stringify({ ok: false, jiraKey, failurePath, status: "cwd-missing" }));
    process.exit(1);
  }

  const modelId = arg("--model", "auto");
  const maxAttempts = Math.max(1, Number(arg("--max-attempts", String(DEFAULT_MAX_ATTEMPTS))) || DEFAULT_MAX_ATTEMPTS);
  const prompt = buildPrompt(jiraKey);

  const storeRoot = path.join(os.homedir(), ".jira-ai-automation", "local-agent-store");
  fs.mkdirSync(storeRoot, { recursive: true });
  // Node < 22.13 has no node:sqlite — use portable JSONL store.
  Cursor.configure({ local: { store: new JsonlLocalAgentStore(storeRoot) } });

  let lastErr = null;
  let lastClassified = null;
  let lastRunId = "";

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const summary = await runOnce({
        jiraKey,
        apiKey,
        cwd,
        modelId,
        prompt,
        storeRoot,
        attempt,
        maxAttempts,
      });
      // Clear prior failure marker after a successful run.
      const oldFailure = path.join(failureLogsDir(), `${jiraKey}-failure.txt`);
      if (fs.existsSync(oldFailure)) {
        fs.unlinkSync(oldFailure);
        log(`Removed prior failure report ${oldFailure}`);
      }
      console.log(JSON.stringify(summary));
      return;
    } catch (err) {
      lastErr = err;
      lastRunId = err?.runId || lastRunId;
      lastClassified =
        err?.classified ||
        classifyFailure(err, {
          status: err?.status,
          phase: "local-agent-execution",
        });

      log(
        `Attempt ${attempt}/${maxAttempts} failed phase=${lastClassified.phase} retryable=${lastClassified.retryable}: ${lastClassified.why}`
      );

      const canRetry = lastClassified.retryable && attempt < maxAttempts;
      if (canRetry) {
        log(`Retrying after stall/transient failure in ${RETRY_DELAY_MS}ms...`);
        await sleep(RETRY_DELAY_MS);
        continue;
      }
      break;
    }
  }

  removeRcaArtifacts(jiraKey);
  const failurePath = writeFailureReport(jiraKey, {
    process: "local-runner / Cursor SDK jira-ai-fix",
    phase: lastClassified?.phase || "local-runner",
    why: lastClassified?.why || errText(lastErr),
    rootCause: lastClassified?.rootCause || errText(lastErr),
    retryable: Boolean(lastClassified?.retryable),
    attempts: maxAttempts,
    maxAttempts,
    exitCode: 1,
    errorName: lastClassified?.errorName || lastErr?.name || "Error",
    cwd,
    model: modelId,
    runId: lastRunId,
    details: errText(lastErr),
  });

  console.log(
    JSON.stringify({
      ok: false,
      jiraKey,
      status: "failed",
      runId: lastRunId || null,
      failurePath,
      phase: lastClassified?.phase || "local-runner",
      why: lastClassified?.why || null,
      rootCause: lastClassified?.rootCause || null,
    })
  );
  process.exit(1);
}

main().catch((err) => {
  const jiraKey = (arg("--jira") || arg("-j") || "UNKNOWN").toUpperCase();
  const classified = classifyFailure(err, { phase: "local-runner-fatal" });
  try {
    removeRcaArtifacts(jiraKey);
  } catch {
    /* ignore */
  }
  let failurePath = null;
  try {
    failurePath = writeFailureReport(jiraKey, {
      process: "local-runner fatal",
      phase: classified.phase,
      why: classified.why,
      rootCause: classified.rootCause,
      retryable: classified.retryable,
      attempts: 1,
      maxAttempts: 1,
      exitCode: 1,
      errorName: classified.errorName,
      details: errText(err),
    });
  } catch (writeErr) {
    log(`could not write failure report: ${writeErr?.message || writeErr}`);
  }
  log(`fatal: ${err?.stack || err}`);
  try {
    console.log(
      JSON.stringify({
        ok: false,
        jiraKey,
        status: "fatal",
        failurePath,
        phase: classified.phase,
        why: classified.why,
        rootCause: classified.rootCause,
      })
    );
  } catch {
    /* ignore */
  }
  process.exit(1);
});
