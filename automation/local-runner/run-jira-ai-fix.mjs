#!/usr/bin/env node
/**
 * Local Desktop agent runner for jira-ai-fix.
 *
 * Runs on THIS machine (not Cloud): loads user skills from ~/.cursor/skills,
 * uses local repos under REPO_ROOT, and follows DRAFT_JIRA_COMMENT.
 *
 * Usage:
 *   node run-jira-ai-fix.mjs --jira ST-13297 [--cwd C:\i21Source] [--investigate-model grok-4.5] [--wrap-up-model auto]
 *
 * Auth: CURSOR_API_KEY env (or --api-key).
 */
import { Agent, Cursor, CursorAgentError, JsonlLocalAgentStore } from "@cursor/sdk";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const DEFAULT_MAX_ATTEMPTS = 2;
const RETRY_DELAY_MS = 5000;
// Intake revisits only (real Jira/HDTN/attachment/comment fetches). Skill/runbook
// reads must not count — they used to false-trigger at 5 via path "jira-ai-fix".
const THRASH_MAX_VISITS = 8;
const INTAKE_STEPS = new Set(["jira", "attachments", "hdtn", "comments"]);

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

function processLogPath() {
  if (process.env.JIRA_AI_PROCESS_LOG) {
    return process.env.JIRA_AI_PROCESS_LOG;
  }
  const now = new Date();
  const mm = String(now.getMonth() + 1).padStart(2, "0");
  const dd = String(now.getDate()).padStart(2, "0");
  const yyyy = String(now.getFullYear());
  const stamp = `${mm}${dd}${yyyy}`;
  const jira = (arg("--jira") || process.env.JIRA_KEY || "").trim().toUpperCase();
  const safe = jira.replace(/[^\w\-]/g, "_");
  if (safe) {
    return path.join(automationLogDir(), `${stamp}_${safe}.txt`);
  }
  return path.join(automationLogDir(), `${stamp}.txt`);
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

function buildInvestigatePrompt(jiraKey) {
  return [
    `jira-ai-fix ${jiraKey}`,
    "",
    "Mode: INVESTIGATE_AND_FIX (phase 1 of 2)",
    "",
    "Run the real jira-ai-fix skill on this machine for investigation and implementation only.",
    "Do: Jira / HDTN / attachments, root-cause thinking, planning, and implement the code fix when appropriate.",
    "",
    "Speed / triage (mandatory early gate):",
    "1. One-pass intake only: fetch Jira, HDTN, attachments, and comments/history EACH AT MOST ONCE.",
    "   Do not re-open the same ticket/attachment/comment loop \"to be sure\" unless a tool failed or fields clearly changed.",
    "2. Immediately decide: code-only vs data-dependent.",
    "3. If code-only (UI/API/logic reproducible from code + ticket evidence): do NOT download or restore a customer database.",
    "   Disclose DB skipped in the investigation-handoff Open questions / risks line.",
    "4. Restore a customer DB only when the symptom clearly needs customer data to prove root cause.",
    "5. After intake, stay in code / root-cause / fix / validation until the handoff fence. Do not bounce back to re-fetch intake.",
    "",
    "Branching (mandatory):",
    "- Feature-branch base from Fix Version: prefer matching Dev on origin; if no Dev exists, use matching Prod.",
    "- Create/reuse ONLY FEATURE_BRANCH=<TARGET_BRANCH>_<JIRA> from that base.",
    "- Commit locally on that FEATURE_BRANCH when a fix is implemented.",
    "- Do NOT create wip/*, temp/*, scratch/*, or *-phase1 branches (or any other throwaway branch names).",
    "",
    "HARD STOP for this phase (leave for phase 2):",
    "- Do NOT author the final section 6 RCA / jira-rca-draft fence.",
    "- Do NOT write %USERPROFILE%\\.jira-ai-drafts\\<KEY>-rca.md yet.",
    "- Do NOT post to Jira.",
    "- Do NOT git push.",
    "",
    "At the end emit exactly one fenced handoff block:",
    "",
    "```investigation-handoff",
    "Root cause: ...",
    "Fix summary: ...",
    "Files changed: ...",
    "Feature branch: ...",
    "Module(s): ...",
    "Validation done: ...",
    "Open questions / risks: ...",
    "```",
  ].join("\n");
}

function buildContinuePrompt(jiraKey) {
  return [
    `Continue jira-ai-fix ${jiraKey} — resume after a transient stall/interrupt.`,
    "",
    "Mode: INVESTIGATE_AND_FIX (phase 1 of 2) — RESUME",
    "",
    "Use conversation context already gathered. Do NOT re-fetch Jira / HDTN / attachments / comments unless that data is missing or a prior tool failed.",
    "Pick up from the last incomplete checkpoint (code / root-cause / fix / validation).",
    "Keep the code-only vs data-dependent triage: do not start a DB restore unless still clearly required and not yet done.",
    "",
    "HARD STOP for this phase (leave for phase 2):",
    "- Do NOT author the final section 6 RCA / jira-rca-draft fence.",
    "- Do NOT write %USERPROFILE%\\.jira-ai-drafts\\<KEY>-rca.md yet.",
    "- Do NOT post to Jira.",
    "- Do NOT git push.",
    "",
    "When investigation/fix is complete, emit exactly one fenced handoff block:",
    "",
    "```investigation-handoff",
    "Root cause: ...",
    "Fix summary: ...",
    "Files changed: ...",
    "Feature branch: ...",
    "Module(s): ...",
    "Validation done: ...",
    "Open questions / risks: ...",
    "```",
  ].join("\n");
}

function buildWrapUpPrompt(jiraKey) {
  return [
    `Continue jira-ai-fix ${jiraKey} — Mode: WRAP_UP (phase 2 of 2)`,
    "",
    "Use the investigation/fix already done in this conversation (and the investigation-handoff if present).",
    "Do NOT re-investigate from scratch unless something critical is missing.",
    "Do NOT re-fetch Jira / HDTN / attachments unless required fields are missing from context.",
    "Do NOT launch, wait on, or depend on Confluence / Azure DevOps MCP servers — wrap-up is local draft + branch only.",
    "",
    "Do now:",
    "1. Stay on / reuse FEATURE_BRANCH=<TARGET_BRANCH>_<JIRA> from phase 1. Do NOT create wip/*, temp/*, scratch/*, or *-phase1 branches.",
    "2. If phase 1 left commits on the wrong branch, move them onto FEATURE_BRANCH=<TARGET_BRANCH>_<JIRA> and delete any local wip/temp branch you find for this Jira.",
    "3. Ensure the fix is committed locally on FEATURE_BRANCH only.",
    "4. HARD STOP: do not run git push or upload any branch/commit to a remote.",
    "5. Author the section 6 RCA but do NOT post to Jira.",
    "Delivery block MUST include Module: <repo folder> (one clone) or Modules: <repo1, repo2> (multiple) — the REPO_ROOT folder name(s) where FEATURE_BRANCH was created (e.g. i21_Liquibase), not the Jira project display name.",
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

function extractHandoff(text) {
  if (!text) return null;
  const m = String(text).match(/```investigation-handoff\s*\r?\n([\s\S]*?)\r?\n```/);
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

function activeJiraKey() {
  return (arg("--jira") || process.env.JIRA_KEY || "").trim().toUpperCase();
}

function log(msg) {
  // Human-readable process log line (no agent/run IDs). Also print for the poller
  // to tee - the poller skips re-writing lines that already look like process-log entries.
  const stamp = new Date();
  const local = new Date(stamp.getTime() - stamp.getTimezoneOffset() * 60000)
    .toISOString()
    .replace("T", " ")
    .replace(/\.\d+Z$/, "");
  const jira = activeJiraKey();
  const text = String(msg || "");
  const tagged =
    jira && !text.includes(`[${jira}]`) ? `[${jira}] ${text}` : text;
  const line = `${local} [INFO] ${tagged}`;
  console.log(line);
  try {
    const logDir = automationLogDir();
    fs.mkdirSync(logDir, { recursive: true });
    fs.appendFileSync(processLogPath(), line + "\n");
  } catch {
    /* ignore */
  }
}

function logRunnerOutcome(summary) {
  if (!summary) return;
  const key = summary.jiraKey || activeJiraKey() || "?";
  if (summary.ok) {
    log(`process: finished ${key} successfully`);
    if (summary.draftPath) log(`process: draft ready at ${summary.draftPath}`);
    if (summary.metaPath) log(`process: meta ${summary.metaPath}`);
    if (summary.investigateModel || summary.wrapUpModel) {
      log(
        `process: models used investigate=${summary.investigateModel || "?"} wrap-up=${summary.wrapUpModel || "?"}`
      );
    }
    if (summary.attempts != null) log(`process: attempts ${summary.attempts}`);
    const handoff = summary.resumeState?.handoff;
    if (handoff) {
      const lines = String(handoff).split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
      const root = lines.find((l) => /^root cause:/i.test(l)) || lines[0];
      if (root) log(`process: handoff ${oneLine(root, 180)}`);
      const fix = lines.find((l) => /^fix summary:/i.test(l));
      if (fix) log(`process: handoff ${oneLine(fix, 180)}`);
      const branch = lines.find((l) => /^feature branch:/i.test(l));
      if (branch) log(`process: handoff ${oneLine(branch, 180)}`);
    }
  } else {
    log(`process: finished ${key} with failure`);
    if (summary.phase) log(`process: failed-part ${summary.phase}`);
    if (summary.why) log(`process: why ${oneLine(summary.why, 200)}`);
    if (summary.rootCause) log(`process: root-cause ${oneLine(summary.rootCause, 200)}`);
    if (summary.failurePath) log(`process: details ${summary.failurePath}`);
  }
}

function activityPath() {
  return path.join(os.homedir(), ".jira-ai-automation", "current-agent.json");
}

function writeCurrentActivity(state) {
  try {
    const dir = path.dirname(activityPath());
    fs.mkdirSync(dir, { recursive: true });
    const jira = state.jiraKey || activeJiraKey() || "";
    let doing = state.doing != null ? String(state.doing) : "";
    if (jira) {
      const working = `Working on ${jira}`;
      if (!doing) doing = working;
      else if (!doing.includes(jira)) doing = `${working}: ${doing}`;
    }
    fs.writeFileSync(
      activityPath(),
      JSON.stringify(
        {
          ...state,
          jiraKey: jira || state.jiraKey || null,
          doing,
          updatedAt: new Date().toISOString(),
        },
        null,
        2
      ),
      "utf8"
    );
  } catch {
    /* ignore */
  }
}

function clearCurrentActivity() {
  try {
    if (fs.existsSync(activityPath())) fs.unlinkSync(activityPath());
  } catch {
    /* ignore */
  }
}

function oneLine(text, max = 220) {
  const s = String(text || "")
    .replace(/\s+/g, " ")
    .trim();
  if (!s) return "";
  return s.length > max ? `${s.slice(0, max - 1)}...` : s;
}

function compactValue(value, max = 180) {
  if (value == null) return "";
  try {
    const s = typeof value === "string" ? value : JSON.stringify(value);
    return oneLine(s, max);
  } catch {
    return oneLine(String(value), max);
  }
}

function toolResultPayload(event) {
  return (
    event?.result ??
    event?.output ??
    event?.content ??
    event?.response ??
    event?.message ??
    event?.error ??
    ""
  );
}

function parseMaybeJson(value) {
  if (value == null) return null;
  if (typeof value === "object") return value;
  if (typeof value !== "string") return null;
  const t = value.trim();
  if (!(t.startsWith("{") || t.startsWith("["))) return null;
  try {
    return JSON.parse(t);
  } catch {
    return null;
  }
}

/** Flatten SDK/shell tool payloads into plain text (never leave raw JSON wrappers). */
function unwrapToolText(result) {
  if (result == null) return "";
  if (typeof result === "string") {
    const parsed = parseMaybeJson(result);
    if (parsed) return unwrapToolText(parsed);
    return result;
  }
  if (Array.isArray(result)) {
    return result.map((x) => unwrapToolText(x)).filter(Boolean).join("\n");
  }
  if (typeof result === "object") {
    if (result.value != null && typeof result.value === "object") {
      const v = result.value;
      const parts = [v.stdout, v.stderr, v.output, v.message, v.text]
        .filter((x) => x != null && String(x).trim() !== "")
        .map(String);
      if (parts.length) return parts.join("\n");
      if (typeof v.exitCode === "number") {
        return `exitCode=${v.exitCode}`;
      }
    }
    const direct = [result.stdout, result.stderr, result.output, result.text, result.message]
      .filter((x) => x != null && String(x).trim() !== "")
      .map(String);
    if (direct.length) return direct.join("\n");
    if (result.content != null) return unwrapToolText(result.content);
    if (result.error != null) return unwrapToolText(result.error);
    // Avoid dumping huge opaque objects into the process log.
    return "";
  }
  return String(result);
}

function shortPath(p) {
  let s = String(p || "")
    .replace(/\\/g, "/")
    .replace(/^\s*=+\s*/g, "")
    .replace(/\s*=+\s*$/g, "")
    .trim();
  if (!s) return "";
  const parts = s.split("/").filter(Boolean);
  if (parts.length <= 3) return parts.join("/");
  return parts.slice(-3).join("/");
}

function extractArgHints(args) {
  let obj = args;
  if (typeof args === "string") {
    obj = parseMaybeJson(args) || {};
  }
  if (!obj || typeof obj !== "object") {
    return { path: "", command: "", url: "", query: "" };
  }
  const path =
    obj.target_file ||
    obj.path ||
    obj.file_path ||
    obj.filePath ||
    obj.filename ||
    obj.file ||
    obj.glob_pattern ||
    obj.pattern ||
    "";
  const command = obj.command || obj.cmd || "";
  const url = obj.url || obj.uri || "";
  const query = obj.query || obj.q || obj.search_term || "";
  let pathFromCmd = "";
  if (command) {
    const m = String(command).match(/["']([^"']+\.[A-Za-z0-9]+)["']/);
    if (m) pathFromCmd = m[1];
  }
  return {
    path: String(path || pathFromCmd || ""),
    command: String(command || ""),
    url: String(url || ""),
    query: String(query || ""),
  };
}

function summarizeHttpOrApi(text) {
  const t = String(text || "");
  if (!t) return "";
  const ticket =
    t.match(/\bHDTN-(\d+)\b/i) ||
    t.match(/\/Ticket\/(\d+)\b/i) ||
    t.match(/\bHD\/Ticket\/(\d+)\b/i);
  if (/404|Not\s*Found/i.test(t)) {
    if (ticket) return `HDTN API 404 Not Found (ticket ${ticket[1]})`;
    const url = t.match(/https?:\/\/\S+/);
    return url ? `HTTP 404 Not Found (${oneLine(url[0], 90)})` : "HTTP 404 Not Found";
  }
  if (/401|Unauthorized/i.test(t)) return "HTTP 401 Unauthorized";
  if (/403|Forbidden/i.test(t)) return "HTTP 403 Forbidden";
  if (/500|Internal Server Error/i.test(t)) return "HTTP 500 Internal Server Error";
  if (/The remote server returned an error:\s*\((\d+)\)\s*([^\n\.]+)/i.test(t)) {
    const m = t.match(/The remote server returned an error:\s*\((\d+)\)\s*([^\n\.]+)/i);
    if (ticket) return `HDTN/API ${m[1]} ${oneLine(m[2], 40)} (ticket ${ticket[1]})`;
    return `HTTP ${m[1]} ${oneLine(m[2], 60)}`;
  }
  return "";
}

function summarizeShellStdout(text, hints) {
  const t = String(text || "").trim();
  if (!t) {
    if (hints.command) return `shell ok: ${oneLine(hints.command, 100)}`;
    return "shell ok (no output)";
  }
  const http = summarizeHttpOrApi(t);
  if (http) return http;

  const branch = t.match(
    /(?:^|\n)\s*={0,4}\s*([A-Za-z]:[^\n]*?)\s*={0,4}\s*\n\s*(?:true|false)\s*\n\s*([^\n]+)/i
  );
  if (branch) {
    return `repo ${shortPath(branch[1])} on branch ${oneLine(branch[2], 60)}`;
  }
  const onBranch = t.match(/\bon branch\s+([^\s\n]+)/i) || t.match(/^##\s+([^\s\n]+)/m);
  if (onBranch) return `git branch ${oneLine(onBranch[1], 70)}`;

  const keyLine = t.match(/^Key:\s*([A-Z][A-Z0-9]+-\d+)/im);
  const summaryLine = t.match(/^Summary:\s*(.+)$/im);
  if (keyLine) {
    return summaryLine
      ? `${keyLine[1]} — ${oneLine(summaryLine[1], 100)}`
      : `fetched ${keyLine[1]}`;
  }

  const firstUseful = t
    .split(/\r?\n/)
    .map((l) => l.trim())
    .find((l) => l && !/^===/.test(l) && !/^(true|false)$/i.test(l));
  return oneLine(firstUseful || t, 140);
}

function pushStepFinding(ctx, step, finding) {
  if (!step || !finding) return;
  if (!ctx.stepFindings) ctx.stepFindings = new Map();
  const line = oneLine(finding, 180);
  if (!line) return;
  // Drop useless generic markers.
  if (/^success$/i.test(line) || /^\{"status":"success"/i.test(line)) return;
  const list = ctx.stepFindings.get(step) || [];
  if (list.some((x) => x === line || x.includes(line) || line.includes(x))) return;
  list.push(line);
  while (list.length > 8) list.shift();
  ctx.stepFindings.set(step, list);
}

function findingScore(s) {
  const t = String(s || "");
  if (!t || /^success$/i.test(t)) return 0;
  if (/^\{/.test(t)) return 1;
  if (/404|HTTP \d|error|fail|Not Found/i.test(t)) return 6;
  if (/HDTN-|ST-\d+|branch |read |edited |wrote |attachment|file/i.test(t)) return 5;
  return 3;
}

function takeStepResultSummary(ctx, step) {
  if (!ctx.stepFindings || !step) return "";
  const list = ctx.stepFindings.get(step) || [];
  ctx.stepFindings.delete(step);
  if (!list.length) return "";
  const ranked = [...list].sort((a, b) => findingScore(b) - findingScore(a));
  // Prefer 1–2 high-signal findings, not a semicolon pile of near-duplicates.
  const picked = [];
  for (const item of ranked) {
    if (picked.some((p) => p.includes(item) || item.includes(p))) continue;
    picked.push(item);
    if (picked.length >= 2) break;
  }
  return oneLine(picked.join(" · "), 200);
}

function summarizeToolOutcome(step, name, args, result) {
  const hints = extractArgHints(args);
  const toolName = String(name || "").toLowerCase();
  const rawText = unwrapToolText(result);
  const argsText = compactValue(args, 120);
  const blob = `${toolName} ${hints.path} ${hints.command} ${hints.url} ${rawText} ${argsText}`;

  // Shell / HTTP style outcomes first (common source of ugly JSON dumps).
  if (
    /shell|bash|powershell|exec|run_terminal|mcp_.*fetch|webfetch|http/i.test(toolName) ||
    hints.command ||
    hints.url ||
    /"exitCode"\s*:|"stdout"\s*:/.test(String(typeof result === "string" ? result : JSON.stringify(result || {})))
  ) {
    const http = summarizeHttpOrApi(rawText) || summarizeHttpOrApi(hints.url);
    if (http) return http;
    if (rawText || hints.command) return summarizeShellStdout(rawText, hints);
  }

  if (step === "jira") {
    const key = blob.match(/\b([A-Z][A-Z0-9]+-\d+)\b/);
    const status =
      blob.match(/"status"\s*:\s*\{[^}]*"name"\s*:\s*"([^"]+)"/i) ||
      blob.match(/"status"\s*:\s*"([^"]+)"/i) ||
      rawText.match(/^Status:\s*(.+)$/im);
    const summary =
      blob.match(/"summary"\s*:\s*"([^"]{6,140})"/i) ||
      rawText.match(/^Summary:\s*(.+)$/im);
    const parts = [];
    if (key) parts.push(key[1]);
    if (status) parts.push(oneLine(status[1], 40));
    if (summary) parts.push(oneLine(summary[1], 100));
    if (parts.length) return parts.join(" — ");
    if (rawText) return oneLine(rawText, 140);
  }

  if (step === "hdtn") {
    const http = summarizeHttpOrApi(rawText) || summarizeHttpOrApi(blob);
    if (http) return http;
    const h = blob.match(/\b(HDTN-\d+|HD-\d+)\b/i);
    const title =
      blob.match(/"short_description"\s*:\s*"([^"]{6,120})"/i) ||
      blob.match(/"title"\s*:\s*"([^"]{6,120})"/i) ||
      blob.match(/"summary"\s*:\s*"([^"]{6,120})"/i);
    const parts = [];
    if (h) parts.push(h[1].toUpperCase());
    if (title) parts.push(oneLine(title[1], 100));
    if (parts.length) return parts.join(" — ");
    if (rawText) return oneLine(rawText, 140);
  }

  if (step === "attachments") {
    const files = [
      ...blob.matchAll(
        /([\w.\-]+\.(?:png|jpe?g|gif|pdf|zip|xlsx?|csv|txt|sql|bak|docx?|msg))/gi
      ),
    ].map((m) => m[1]);
    const uniq = [...new Set(files)].filter((f) => !/^n\.tmp/i.test(f)).slice(0, 5);
    if (uniq.length) return `attachment(s): ${uniq.join(", ")}`;
    if (/no attachments|0 attachments|attachment.?count.:.?0/i.test(blob)) {
      return "no attachments found";
    }
  }

  if (step === "comments") {
    const count =
      blob.match(/"total"\s*:\s*(\d+)/i) ||
      blob.match(/\b(\d+)\s+comments?\b/i);
    if (count) return `${count[1]} comment(s)/history item(s)`;
  }

  if (step === "database") {
    const http = summarizeHttpOrApi(rawText);
    if (http) return http;
    if (rawText) return oneLine(rawText, 140);
  }

  if (step === "code" || step === "fix" || step === "validate") {
    const pathHint = hints.path ? shortPath(hints.path) : "";
    if (pathHint) {
      const verb = /write|search_replace|strreplace|apply_patch|delete/i.test(toolName)
        ? "edited"
        : /grep|glob|search/i.test(toolName)
          ? "searched"
          : step === "validate"
            ? "validated"
            : "read";
      const extra =
        hints.query || hints.command
          ? ` (${oneLine(hints.query || hints.command, 60)})`
          : "";
      return `${verb} ${pathHint}${extra}`;
    }
    if (rawText) {
      const http = summarizeHttpOrApi(rawText);
      if (http) return http;
      return summarizeShellStdout(rawText, hints);
    }
  }

  // Generic: never emit raw JSON wrappers.
  if (rawText) {
    const http = summarizeHttpOrApi(rawText);
    if (http) return http;
    if (/^\s*\{/.test(rawText)) return summarizeShellStdout(unwrapToolText(rawText), hints);
    return oneLine(rawText, 140);
  }
  if (hints.path) return `used ${shortPath(hints.path)}`;
  if (hints.command) return `ran: ${oneLine(hints.command, 100)}`;
  if (toolName) return `tool ${toolName}`;
  return "";
}

// High-level investigation checklist steps (no thinking text, no agent/run IDs).
const CHECKLIST_STEPS = {
  starting: "starting investigation",
  jira: "Jira ticket",
  hdtn: "HDTN ticket",
  attachments: "attachments",
  comments: "comments / history",
  code: "code / root cause",
  database: "customer database / SQL",
  fix: "coding",
  validate: "validation",
  draft: "draft comment",
  finish: "run wrap-up",
};

function checklistLabel(stepKey) {
  return CHECKLIST_STEPS[stepKey] || stepKey;
}

function beginPhrase(stepKey) {
  if (stepKey === "starting" || stepKey === "finish") return checklistLabel(stepKey);
  if (stepKey === "fix" || stepKey === "code") return "coding";
  if (stepKey === "draft") return "creating the draft comment";
  if (stepKey === "validate") return "validating the fix";
  return `checking ${checklistLabel(stepKey)}`;
}

function endPhrase(stepKey, outcome) {
  if (outcome === "failed") {
    if (stepKey === "fix" || stepKey === "code") return "Failed coding";
    if (stepKey === "draft") return "Failed creating the draft comment";
    if (stepKey === "validate") return "Failed validating the fix";
    if (stepKey === "starting" || stepKey === "finish") {
      return `Failed ${checklistLabel(stepKey)}`;
    }
    return `Failed checking ${checklistLabel(stepKey)}`;
  }
  if (stepKey === "fix" || stepKey === "code") return "Done coding";
  if (stepKey === "draft") return "Done creating the draft comment";
  if (stepKey === "validate") return "Done validating the fix";
  if (stepKey === "starting" || stepKey === "finish") {
    return `${checklistLabel(stepKey)} done`;
  }
  return `Done checking ${checklistLabel(stepKey)}`;
}

function beginChecklistStep(ctx, stepKey, extra = {}) {
  if (!stepKey) return;
  if (!ctx.endedLogged) ctx.endedLogged = new Set();
  if (!ctx.stepFindings) ctx.stepFindings = new Map();
  if (!ctx.stepVisitCounts) ctx.stepVisitCounts = new Map();

  // Same step still open — refresh activity only, no duplicate "checking…" line.
  if (ctx.activeStep === stepKey) {
    writeCurrentActivity({
      jiraKey: ctx.jiraKey,
      model: ctx.modelId,
      status: "running",
      stage: stepKey,
      doing: beginPhrase(stepKey),
      attempt: ctx.attempt,
      maxAttempts: ctx.maxAttempts,
      agentId: ctx.agentId || null,
      runId: ctx.runId || null,
      phaseComplete: ctx.phase1Complete ? "wrap-up" : "investigate",
      ...extra,
    });
    return;
  }

  // Close previous open step as done if we moved on without an explicit finish.
  if (ctx.activeStep && ctx.activeStep !== stepKey) {
    endChecklistStep(ctx, ctx.activeStep, "done");
  }

  // New visit to this step — allow a fresh Done later.
  ctx.endedLogged.delete(stepKey);
  ctx.endedLogged.delete(`${stepKey}:failed`);

  if (INTAKE_STEPS.has(stepKey)) {
    const visits = (ctx.stepVisitCounts.get(stepKey) || 0) + 1;
    ctx.stepVisitCounts.set(stepKey, visits);
    if (visits > THRASH_MAX_VISITS) {
      ctx.thrashAbort = { step: stepKey, visits };
      log(`process: thrash detected step=${stepKey} visits=${visits} (max=${THRASH_MAX_VISITS})`);
    }
  }

  ctx.activeStep = stepKey;
  ctx.stage = stepKey;
  const phrase = beginPhrase(stepKey);
  log(`process: ${phrase}`);
  writeCurrentActivity({
    jiraKey: ctx.jiraKey,
    model: ctx.modelId,
    status: "running",
    stage: stepKey,
    doing: phrase,
    attempt: ctx.attempt,
    maxAttempts: ctx.maxAttempts,
    agentId: ctx.agentId || null,
    runId: ctx.runId || null,
    phaseComplete: ctx.phase1Complete ? "wrap-up" : "investigate",
    ...extra,
  });
}

function endChecklistStep(ctx, stepKey, outcome = "done", detail = "") {
  const key = stepKey || ctx.activeStep;
  if (!key) return;
  if (!ctx.endedLogged) ctx.endedLogged = new Set();
  if (!ctx.stepFindings) ctx.stepFindings = new Map();

  // Duplicate SDK completion events / already-closed step — log Done/Failed once only.
  if (outcome === "done" && ctx.endedLogged.has(key)) {
    if (ctx.activeStep === key) ctx.activeStep = "";
    return;
  }
  if (outcome === "failed" && ctx.endedLogged.has(`${key}:failed`)) {
    if (ctx.activeStep === key) ctx.activeStep = "";
    return;
  }
  // Tool completed after we already switched away (begin closed it) — skip.
  if (outcome === "done" && ctx.activeStep && ctx.activeStep !== key) {
    ctx.endedLogged.add(key);
    return;
  }

  const phrase = endPhrase(key, outcome);
  const findingSummary = takeStepResultSummary(ctx, key);
  const detailLine = detail ? oneLine(detail, 120) : "";
  const resultLine = findingSummary || detailLine;

  log(`process: ${phrase}`);
  if (resultLine) {
    log(`process: result: ${resultLine}`);
  }

  ctx.endedLogged.add(key);
  if (outcome === "failed") ctx.endedLogged.add(`${key}:failed`);
  if (ctx.activeStep === key) ctx.activeStep = "";
  writeCurrentActivity({
    jiraKey: ctx.jiraKey,
    model: ctx.modelId,
    status: outcome === "failed" ? "error" : "running",
    stage: key,
    doing: resultLine ? `${phrase} | ${resultLine}` : phrase,
    lastResult: resultLine || null,
    attempt: ctx.attempt,
    maxAttempts: ctx.maxAttempts,
  });
}

function inferChecklistStep(name, args) {
  const n = String(name || "").toLowerCase();
  const blob = `${n} ${compactValue(args, 300)}`.toLowerCase();

  // Local skill / runbook / automation config — not Jira ticket intake.
  // Paths like .../jira-ai-fix/SKILL.md used to match /jira/ and thrash-abort.
  if (
    /jira-ai-fix|jira-ai-fix\.md|draft_mode\.md|jira-ai-config|\.jira-ai-automation|jira-ai-drafts|runbook\/j[iI]?ra/i.test(
      blob
    )
  ) {
    if (/rca|draft|jira-rca-draft|acceptance verification/.test(blob) && /jira-ai-drafts|jira-rca-draft/.test(blob)) {
      return "draft";
    }
    return "code";
  }

  if (
    /hdtn|helpdesk|servicenow|hd-\d+|hdtn-\d+|gethelpdesk|help.?desk/.test(blob)
  ) {
    return "hdtn";
  }
  if (
    /attachment|download.?attach|getattach|filename|\.png|\.jpg|\.jpeg|\.gif|\.pdf|\.zip|\.xlsx|\.csv|\.txt|\.sql|\.bak/.test(
      blob
    )
  ) {
    return "attachments";
  }
  if (/comment|changelog|history|worklog/.test(blob) && /jira|atlassian|issue/.test(blob)) {
    return "comments";
  }
  // Real Jira/Atlassian API or MCP — not every string containing "jira".
  if (
    /getjira|searchjql|executejql|getissue|get_issue|execute_jql|atlassian|rest\/api\/[23]\/issue|browse\/[a-z]+-\d+/i.test(
      blob
    ) ||
    (/\b(mcp|plugin).*jira\b|\bjira.*(mcp|plugin|tool)\b/i.test(blob) &&
      /issue|ticket|jql|search|get_/i.test(blob))
  ) {
    return "jira";
  }
  if (
    /sql|database|restore|\.bak|liquibase|sqlscripts|query|ssms|sqlcmd|customer.?db/.test(
      blob
    )
  ) {
    return "database";
  }
  if (
    /rca|draft|jira-ai-drafts|jira-rca-draft|acceptance verification|root cause analysis/.test(
      blob
    )
  ) {
    return "draft";
  }
  if (
    /write|search_replace|strreplace|edit_notebook|apply_patch|delete_file|editnotebook/.test(
      n
    )
  ) {
    return "fix";
  }
  if (/test|lint|build|validate|pytest|npm test|dotnet test/.test(blob)) {
    return "validate";
  }
  if (
    /read|grep|glob|semant|shell|bash|powershell|git|fetch|webfetch|websearch|task|explore/.test(
      n
    ) ||
    /read|grep|glob|shell|git /.test(blob)
  ) {
    return "code";
  }
  return null;
}

function toolCallId(event) {
  return (
    event?.call_id ||
    event?.toolCallId ||
    event?.id ||
    `${event?.name || event?.toolName || "tool"}:${Date.now()}`
  );
}

function logStreamEvent(event, ctx) {
  // Track IDs internally only — never print agent=/run= in the process log.
  if (event?.agent_id) ctx.agentId = event.agent_id;
  if (event?.run_id) ctx.runId = event.run_id;
  if (!ctx.openSteps) ctx.openSteps = new Map();
  if (!ctx.endedLogged) ctx.endedLogged = new Set();
  if (!ctx.stepFindings) ctx.stepFindings = new Map();

  switch (event?.type) {
    case "system":
      beginChecklistStep(ctx, "starting");
      break;
    case "status": {
      const st = String(event.status || "").toUpperCase();
      if (st === "FINISHED") {
        if (ctx.activeStep) endChecklistStep(ctx, ctx.activeStep, "done");
        beginChecklistStep(ctx, "finish");
        endChecklistStep(ctx, "finish", "done");
      } else if (st === "ERROR" || st === "CANCELLED") {
        endChecklistStep(ctx, ctx.activeStep || "starting", "failed", event.message || st);
      }
      break;
    }
    case "task": {
      const text = oneLine(event.text || "", 120).toLowerCase();
      if (!text) break;
      if (/hdtn|helpdesk/.test(text)) beginChecklistStep(ctx, "hdtn");
      else if (/attach/.test(text)) beginChecklistStep(ctx, "attachments");
      else if (/comment|history/.test(text)) beginChecklistStep(ctx, "comments");
      else if (/atlassian|jql|fetch.*ticket|check.*jira issue|get.*jira/.test(text)) {
        beginChecklistStep(ctx, "jira");
      }
      else if (/database|sql|restore/.test(text)) beginChecklistStep(ctx, "database");
      else if (/fix|implement|patch|change/.test(text)) beginChecklistStep(ctx, "fix");
      else if (/draft|rca/.test(text)) beginChecklistStep(ctx, "draft");
      else if (/valid|test|verify/.test(text)) beginChecklistStep(ctx, "validate");
      else if (/investig|analy|root cause|repro|code|skill|runbook/.test(text)) {
        beginChecklistStep(ctx, "code");
      }
      break;
    }
    case "tool_call":
    case "tool_use": {
      const name = event.name || event.toolName || "";
      const args = event.args || event.arguments || event.input;
      const step = inferChecklistStep(name, args);
      const status = String(event.status || "running").toLowerCase();
      const id = toolCallId(event);

      if (status === "running" || status === "started" || status === "in_progress") {
        if (step) {
          ctx.openSteps.set(id, { step, name, args });
          beginChecklistStep(ctx, step);
          // Capture useful request hints early (e.g. attachment filenames).
          const early = summarizeToolOutcome(step, name, args, "");
          if (early && step === "attachments") pushStepFinding(ctx, step, early);
        }
      } else if (status === "completed" || status === "success" || status === "done") {
        const open = ctx.openSteps.get(id);
        const doneStep = open?.step || step || null;
        const toolName = open?.name || name;
        const toolArgs = open?.args ?? args;
        if (ctx.openSteps.has(id)) ctx.openSteps.delete(id);
        if (!doneStep) break;

        const summary = summarizeToolOutcome(
          doneStep,
          toolName,
          toolArgs,
          toolResultPayload(event)
        );
        if (summary) pushStepFinding(ctx, doneStep, summary);

        // Wait until all overlapping tools for this stage finish before Done.
        const stillOpen = [...ctx.openSteps.values()].some((s) => s.step === doneStep);
        if (stillOpen) break;
        if (ctx.activeStep === doneStep) {
          endChecklistStep(ctx, doneStep, "done");
        } else {
          // Already closed by a stage switch — mark ended to absorb duplicates.
          ctx.endedLogged.add(doneStep);
        }
      } else if (status === "error" || status === "failed") {
        const open = ctx.openSteps.get(id);
        const failStep = open?.step || step || ctx.activeStep;
        if (ctx.openSteps.has(id)) ctx.openSteps.delete(id);
        if (!failStep) break;
        const errDetail = compactValue(
          event.result || event.error || event.message,
          120
        );
        if (errDetail) pushStepFinding(ctx, failStep, errDetail);
        const stillOpen = [...ctx.openSteps.values()].some((s) => s.step === failStep);
        if (stillOpen) break;
        endChecklistStep(ctx, failStep, "failed", errDetail);
      }
      break;
    }
    case "assistant": {
      // Infer checklist step from queued tools only — never log assistant/thinking prose.
      for (const block of event.message?.content || []) {
        if (block?.type === "tool_use" || block?.type === "tool_call") {
          const step = inferChecklistStep(block.name || "", block.input || block.args);
          if (step) beginChecklistStep(ctx, step);
        }
      }
      break;
    }
    case "thinking":
    case "usage":
      break;
    default:
      break;
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
  const logPath = processLogPath();
  log(`FAILURE jira=${jiraKey} process=${report.process || "local-runner / Cursor SDK jira-ai-fix"}`);
  log(`FAILURE failed-part=${report.phase}`);
  log(`FAILURE why=${report.why}`);
  log(`FAILURE root-cause=${report.rootCause}`);
  log(
    `FAILURE status=${report.status || ""} exit=${report.exitCode ?? ""} attempts=${report.attempts || 1}/${report.maxAttempts || 1} cwd=${report.cwd || ""}`
  );
  if (report.details) {
    for (const detailLine of String(report.details).split(/\r?\n/)) {
      if (detailLine) log(`FAILURE detail: ${detailLine}`);
    }
  }
  annotateRcaWithFailure(jiraKey, report, logPath);
  return logPath;
}

function annotateRcaWithFailure(jiraKey, report, processLog) {
  const dir = draftsDir();
  fs.mkdirSync(dir, { recursive: true });
  const mdPath = path.join(dir, `${jiraKey}-rca.md`);
  const metaPath = path.join(dir, `${jiraKey}-meta.json`);
  const stamp = report.failedAt || new Date().toISOString();
  const note = [
    "",
    "---",
    "",
    "## Automation failure",
    "",
    `- Time: ${stamp}`,
    `- Process: ${report.process || "local-runner / Cursor SDK jira-ai-fix"}`,
    `- Failed part: ${report.phase}`,
    `- Why it failed: ${report.why}`,
    `- Root cause: ${report.rootCause}`,
    `- Status: ${report.status || ""}`,
    `- Exit code: ${report.exitCode ?? ""}`,
    `- Process log: ${processLog}`,
    "",
    "Automation will not reinvestigate this Jira while this RCA draft exists.",
    "Delete this draft only when a fresh investigation is intentional.",
    "",
  ].join("\n");

  if (fs.existsSync(mdPath)) {
    const existing = fs.readFileSync(mdPath, "utf8");
    if (!/^## Automation failure\s*$/m.test(existing)) {
      fs.writeFileSync(mdPath, existing.replace(/\s+$/, "") + "\n" + note, "utf8");
    } else {
      const updated = existing.replace(/(?:^|\n)---\s*\n## Automation failure[\s\S]*$/m, "\n" + note.trimStart());
      fs.writeFileSync(mdPath, updated.replace(/\s+$/, "") + "\n", "utf8");
    }
    log(`Appended failure note to existing RCA draft ${mdPath}`);
  } else {
    const body = [
      `# Investigation incomplete: ${jiraKey}`,
      "",
      "No completed RCA was produced. The automation failure details are below.",
      note,
    ].join("\n");
    fs.writeFileSync(mdPath, body, "utf8");
    log(`Created failure RCA draft marker ${mdPath}`);
  }

  fs.writeFileSync(
    metaPath,
    JSON.stringify(
      {
        jiraKey,
        mode: "local",
        investigation: "failed",
        finishedAt: stamp,
        failurePhase: report.phase,
        failureWhy: report.why,
        failureRootCause: report.rootCause,
        processLogPath: processLog,
        jiraCommentPosted: false,
      },
      null,
      2
    ),
    "utf8"
  );
  return mdPath;
}

async function streamRun(run, streamCtx) {
  streamCtx.runId = run?.id || streamCtx.runId || "";
  if (typeof run?.stream === "function") {
    for await (const event of run.stream()) {
      logStreamEvent(event, streamCtx);
      if (streamCtx.thrashAbort) {
        try {
          if (typeof run.cancel === "function") await run.cancel();
          else if (typeof run.abort === "function") await run.abort();
        } catch {
          /* ignore cancel errors */
        }
        const classified = {
          phase: "local-agent-execution",
          why: `Repeated fetch loop on ${streamCtx.thrashAbort.step} (${streamCtx.thrashAbort.visits} visits).`,
          rootCause:
            "Agent re-fetched the same intake sources instead of progressing to code/root-cause.",
          retryable: false,
          errorName: "ThrashAbort",
        };
        const err = new Error(classified.why);
        err.classified = classified;
        err.runId = streamCtx.runId || "";
        err.agentId = streamCtx.agentId || "";
        err.status = "cancelled";
        throw err;
      }
    }
  }
  const result = await run.wait();
  const status = result?.status || "unknown";
  const text =
    result?.result ||
    result?.text ||
    (typeof result === "string" ? result : "") ||
    "";
  return {
    result,
    status,
    text,
    runId: result?.id || streamCtx.runId || "",
  };
}

function throwIfRunFailed(status, result, streamCtx, phase) {
  if (status !== "error" && status !== "cancelled") return;
  endChecklistStep(streamCtx, streamCtx.activeStep || "jira", "failed", status);
  const classified = classifyFailure(
    new Error(result?.error?.message || `run ${status}`),
    {
      status,
      phase,
    }
  );
  const err = new Error(classified.why);
  err.classified = classified;
  err.runId = streamCtx.runId || "";
  err.agentId = streamCtx.agentId || "";
  err.status = status;
  throw err;
}

async function disposeAgent(agent) {
  if (!agent) return;
  try {
    if (typeof agent[Symbol.asyncDispose] === "function") {
      await agent[Symbol.asyncDispose]();
    } else if (typeof agent.close === "function") {
      await agent.close();
    }
  } catch (disposeErr) {
    log(`agent dispose warning: ${disposeErr?.message || disposeErr}`);
  }
}

async function createOrResumeAgent({
  apiKey,
  cwd,
  modelId,
  storeRoot,
  resumeAgentId,
}) {
  // Keep user/project/plugins so jira-ai-fix skills + rules still load.
  // Pass mcpServers: {} on create/resume/send so ~/.cursor/mcp.json is NOT
  // started (npx Confluence/ADO hangs unattended). Desktop/manual Cursor is
  // untouched — it still uses ~/.cursor/mcp.json on its own.
  const localOpts = {
    cwd,
    settingSources: ["user", "project", "plugins"],
    store: new JsonlLocalAgentStore(storeRoot),
  };
  const noAmbientMcp = {};

  if (resumeAgentId) {
    try {
      log(`process: resuming agent ${resumeAgentId}`);
      log("process: automation MCP disabled (inline empty mcpServers; Desktop mcp.json unchanged)");
      const resumed = await Agent.resume(resumeAgentId, {
        apiKey,
        local: localOpts,
        mcpServers: noAmbientMcp,
      });
      return { agent: resumed, resumed: true };
    } catch (err) {
      log(`process: resume failed (${err?.message || err}); creating new agent`);
    }
  }

  log("process: automation MCP disabled (inline empty mcpServers; Desktop mcp.json unchanged)");
  const agent = await Agent.create({
    apiKey,
    model: { id: modelId },
    local: localOpts,
    mcpServers: noAmbientMcp,
  });
  return { agent, resumed: false };
}

async function runOnce({
  jiraKey,
  apiKey,
  cwd,
  investigateModelId,
  wrapUpModelId,
  investigatePrompt,
  continuePrompt,
  wrapUpPrompt,
  storeRoot,
  attempt,
  maxAttempts,
  resumeState,
}) {
  const streamCtx = {
    jiraKey,
    modelId: investigateModelId,
    attempt,
    maxAttempts,
    agentId: resumeState?.agentId || "",
    runId: "",
    stage: "",
    activeStep: "",
    openSteps: new Map(),
    endedLogged: new Set(),
    stepFindings: new Map(),
    stepVisitCounts: new Map(),
    thrashAbort: null,
    phase1Complete: Boolean(resumeState?.phase1Complete),
  };

  beginChecklistStep(streamCtx, "starting", { cwd });

  let agent = null;
  let phase1Complete = Boolean(resumeState?.phase1Complete);
  let handoff = resumeState?.handoff || null;
  let phase1 = resumeState?.phase1 || null;
  let resumed = false;

  try {
    const created = await createOrResumeAgent({
      apiKey,
      cwd,
      modelId: investigateModelId,
      storeRoot,
      resumeAgentId: resumeState?.agentId || "",
    });
    agent = created.agent;
    resumed = created.resumed;
    streamCtx.agentId = agent?.agentId || agent?.id || resumeState?.agentId || "";
    // Resume failed and we created a fresh agent — conversation context is gone.
    if (!resumed && resumeState?.agentId) {
      phase1Complete = false;
      handoff = null;
      phase1 = null;
      streamCtx.phase1Complete = false;
      log("process: fresh agent after failed resume; re-running phase 1");
    }
    endChecklistStep(streamCtx, "starting", "done");

    // ---- Phase 1: investigate / plan / code ----
    if (!phase1Complete) {
      const phase1Prompt =
        resumed && resumeState?.agentId ? continuePrompt : investigatePrompt;
      log(
        `process: phase 1 investigate model=${investigateModelId}${resumed ? " (resume)" : ""}`
      );
      streamCtx.modelId = investigateModelId;
      // Do not pre-count "jira" intake — wait for real Atlassian/API tools.
      beginChecklistStep(streamCtx, "code", { cwd, phase: 1 });
      const phase1Run = await agent.send(phase1Prompt, {
        model: { id: investigateModelId },
        // Per-send override fully replaces ambient MCP for this run (SDK docs).
        mcpServers: {},
      });
      phase1 = await streamRun(phase1Run, streamCtx);
      throwIfRunFailed(phase1.status, phase1.result, streamCtx, "investigate-phase");
      if (streamCtx.activeStep) endChecklistStep(streamCtx, streamCtx.activeStep, "done");
      handoff = extractHandoff(phase1.text) || handoff;
      if (handoff) {
        log("process: investigation handoff received");
      } else {
        log(
          "process: investigation handoff fence missing - continuing to wrap-up with conversation context"
        );
      }
      phase1Complete = true;
      streamCtx.phase1Complete = true;
      writeCurrentActivity({
        jiraKey,
        model: investigateModelId,
        status: "running",
        stage: "investigate-done",
        doing: "phase 1 complete; starting wrap-up",
        attempt,
        maxAttempts,
        agentId: streamCtx.agentId || null,
        runId: phase1.runId || streamCtx.runId || null,
        phaseComplete: "wrap-up",
        handoffPresent: Boolean(handoff),
      });
    } else {
      log("process: skipping phase 1 (already complete); wrap-up only");
    }

    // ---- Phase 2: feature branch / draft RCA / wrap-up ----
    log(`process: phase 2 wrap-up model=${wrapUpModelId}`);
    streamCtx.modelId = wrapUpModelId;
    streamCtx.openSteps = new Map();
    streamCtx.endedLogged = new Set();
    streamCtx.stepFindings = new Map();
    streamCtx.stepVisitCounts = new Map();
    streamCtx.thrashAbort = null;
    streamCtx.activeStep = "";
    beginChecklistStep(streamCtx, "draft", { cwd, phase: 2 });
    const phase2Run = await agent.send(wrapUpPrompt, {
      model: { id: wrapUpModelId },
      mcpServers: {},
    });
    const phase2 = await streamRun(phase2Run, streamCtx);
    throwIfRunFailed(phase2.status, phase2.result, streamCtx, "wrap-up-phase");
    if (streamCtx.activeStep) endChecklistStep(streamCtx, streamCtx.activeStep, "done");

    const combinedText = [phase2.text, phase1?.text].filter(Boolean).join("\n\n");
    beginChecklistStep(streamCtx, "draft", { cwd });
    let draft = extractDraft(phase2.text) || extractDraft(combinedText);
    if (!draft) {
      log("process: RCA draft fence missing - saving full assistant text as fallback");
      draft = phase2.text || phase1?.text || `(no result text; status=${phase2.status})`;
      endChecklistStep(streamCtx, "draft", "failed", "missing jira-rca-draft fence");
    } else {
      endChecklistStep(streamCtx, "draft", "done");
    }

    const runId = phase2.runId || phase1?.runId || streamCtx.runId || "";
    const agentId = streamCtx.agentId || "";
    const meta = {
      jiraKey,
      mode: "local",
      dryRun: false,
      finishedAt: new Date().toISOString(),
      agentId: agentId || null,
      runId,
      status: phase2.status,
      cwd,
      investigateModel: investigateModelId,
      wrapUpModel: wrapUpModelId,
      model: investigateModelId,
      attempts: attempt,
      prCreated: false,
      phases: {
        investigate: {
          status: phase1?.status || (phase1Complete ? "resumed-skip" : "unknown"),
          runId: phase1?.runId || null,
          handoffPresent: Boolean(handoff),
        },
        wrapUp: { status: phase2.status, runId: phase2.runId || null },
      },
    };
    const saved = saveDraft(jiraKey, draft, meta);
    beginChecklistStep(streamCtx, "finish", { cwd });
    endChecklistStep(streamCtx, "finish", "done");
    log(`process: draft saved`);
    log(`process: working on ${jiraKey} — wrap-up complete, preparing outcome`);

    await disposeAgent(agent);
    agent = null;

    return {
      ok: true,
      jiraKey,
      status: phase2.status,
      agentId: agentId || null,
      runId,
      draftPath: saved.md,
      metaPath: saved.metaPath,
      attempts: attempt,
      investigateModel: investigateModelId,
      wrapUpModel: wrapUpModelId,
      resumeState: {
        agentId: agentId || null,
        phase1Complete: true,
        handoff,
      },
    };
  } catch (err) {
    err.agentId = err.agentId || streamCtx.agentId || resumeState?.agentId || "";
    err.runId = err.runId || streamCtx.runId || "";
    err.resumeState = {
      agentId: err.agentId || null,
      phase1Complete,
      handoff,
      phase1,
    };
    // Keep agent alive for resume retries; dispose only when caller decides.
    err._agent = agent;
    throw err;
  }
}

async function main() {
  const jiraKey = (arg("--jira") || arg("-j") || "").toUpperCase();
  if (!jiraKey || !/^[A-Z][A-Z0-9]+-\d+$/.test(jiraKey)) {
    console.error(
      "Usage: node run-jira-ai-fix.mjs --jira ST-12345 [--cwd C:\\i21Source] [--investigate-model grok-4.5] [--wrap-up-model auto]"
    );
    process.exit(2);
  }

  const apiKey = (arg("--api-key") || process.env.CURSOR_API_KEY || "").trim();
  if (!apiKey) {
    const failurePath = writeFailureReport(jiraKey, {
      process: "local-runner preflight",
      phase: "preflight-auth",
      why: "CURSOR_API_KEY is required (Cursor Dashboard â†’ API Keys).",
      rootCause: "Missing API key in process/user environment.",
      retryable: false,
      attempts: 0,
      maxAttempts: 0,
      exitCode: 1,
      errorName: "AuthError",
      details: "Set CURSOR_API_KEY before launching the local runner.",
    });
    console.error("CURSOR_API_KEY is required (Cursor Dashboard â†’ API Keys).");
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

  const autoCfg = readJson(path.join(os.homedir(), ".jira-ai-automation", "config.json")) || {};
  const investigateModelId = (
    arg("--investigate-model") ||
    arg("--model") ||
    autoCfg.investigateModel ||
    autoCfg.localModel ||
    "grok-4.5"
  )
    .toString()
    .trim();
  const wrapUpModelId = (arg("--wrap-up-model") || autoCfg.wrapUpModel || "auto").toString().trim();
  const maxAttempts = Math.max(1, Number(arg("--max-attempts", String(DEFAULT_MAX_ATTEMPTS))) || DEFAULT_MAX_ATTEMPTS);
  const investigatePrompt = buildInvestigatePrompt(jiraKey);
  const continuePrompt = buildContinuePrompt(jiraKey);
  const wrapUpPrompt = buildWrapUpPrompt(jiraKey);

  log(`process: models investigate=${investigateModelId} wrap-up=${wrapUpModelId}`);
  log(`process: working on ${jiraKey}`);

  const storeRoot = path.join(os.homedir(), ".jira-ai-automation", "local-agent-store");
  fs.mkdirSync(storeRoot, { recursive: true });
  // Node < 22.13 has no node:sqlite - use portable JSONL store.
  Cursor.configure({ local: { store: new JsonlLocalAgentStore(storeRoot) } });

  let lastErr = null;
  let lastClassified = null;
  let lastRunId = "";
  let resumeState = {
    agentId: null,
    phase1Complete: false,
    handoff: null,
    phase1: null,
  };
  let heldAgent = null;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const summary = await runOnce({
        jiraKey,
        apiKey,
        cwd,
        investigateModelId,
        wrapUpModelId,
        investigatePrompt,
        continuePrompt,
        wrapUpPrompt,
        storeRoot,
        attempt,
        maxAttempts,
        resumeState,
      });
      heldAgent = null;
      clearCurrentActivity();
      logRunnerOutcome(summary);
      // Machine-readable summary for the poller (not mirrored into the process log).
      console.log(JSON.stringify(summary));
      // SDK can leave open handles; force exit so the poller can email + release lock.
      process.exit(0);
    } catch (err) {
      lastErr = err;
      lastRunId = err?.runId || lastRunId;
      lastClassified =
        err?.classified ||
        classifyFailure(err, {
          status: err?.status,
          phase: "local-agent-execution",
        });

      if (err?.resumeState) {
        resumeState = {
          agentId: err.resumeState.agentId || resumeState.agentId,
          phase1Complete: Boolean(err.resumeState.phase1Complete),
          handoff: err.resumeState.handoff || resumeState.handoff,
          phase1: err.resumeState.phase1 || resumeState.phase1,
        };
      }
      if (err?._agent) {
        heldAgent = err._agent;
      }

      log(
        `Attempt ${attempt}/${maxAttempts} failed phase=${lastClassified.phase} retryable=${lastClassified.retryable}: ${lastClassified.why}`
      );
      writeCurrentActivity({
        jiraKey,
        agentId: err?.agentId || resumeState.agentId || null,
        runId: err?.runId || lastRunId || null,
        model: investigateModelId,
        investigateModel: investigateModelId,
        wrapUpModel: wrapUpModelId,
        status: "error",
        doing: lastClassified.why,
        attempt,
        maxAttempts,
        phaseComplete: resumeState.phase1Complete ? "wrap-up" : "investigate",
        handoffPresent: Boolean(resumeState.handoff),
      });

      const canRetry = lastClassified.retryable && attempt < maxAttempts;
      if (canRetry) {
        // Resume uses Agent.resume(agentId); drop the prior handle to avoid leaks.
        await disposeAgent(heldAgent);
        heldAgent = null;
        const mode = resumeState.phase1Complete
          ? "wrap-up-only"
          : resumeState.agentId
            ? "resume-continue"
            : "fresh";
        log(
          `Retrying after stall/transient failure in ${RETRY_DELAY_MS}ms (mode=${mode}, agentId=${resumeState.agentId || "none"})...`
        );
        await sleep(RETRY_DELAY_MS);
        continue;
      }
      break;
    }
  }

  await disposeAgent(heldAgent);
  heldAgent = null;

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
    model: investigateModelId,
    investigateModel: investigateModelId,
    wrapUpModel: wrapUpModelId,
    runId: lastRunId,
    details: errText(lastErr),
  });

  writeCurrentActivity({
    jiraKey,
    agentId: resumeState.agentId || null,
    runId: lastRunId || null,
    model: investigateModelId,
    investigateModel: investigateModelId,
    wrapUpModel: wrapUpModelId,
    status: "failed",
    doing: lastClassified?.why || "Local runner failed",
    attempt: maxAttempts,
    maxAttempts,
  });

  const failSummary = {
    ok: false,
    jiraKey,
    status: "failed",
    runId: lastRunId || null,
    failurePath,
    phase: lastClassified?.phase || "local-runner",
    why: lastClassified?.why || null,
    rootCause: lastClassified?.rootCause || null,
  };
  logRunnerOutcome(failSummary);
  console.log(JSON.stringify(failSummary));
  process.exit(1);
}

main().catch((err) => {
  const jiraKey = (arg("--jira") || arg("-j") || "UNKNOWN").toUpperCase();
  const classified = classifyFailure(err, { phase: "local-runner-fatal" });
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
