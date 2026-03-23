# How Vault Guard Works — Technical Deep-Dive

CLS Vault Guard is a set of four Claude Code hooks written in Python. Each hook intercepts a specific event in the Claude Code execution lifecycle and scans the relevant content for credential patterns defined in `config/patterns.json`.

---

## Architecture Overview

```
Claude Code session
       │
       ├── [UserPromptSubmit]   → vg_prompt_scan.py
       │
       ├── [PostToolUse:Bash]   → vg_bash_guard.py
       │
       ├── [PostToolUse:Write]  → vg_write_intercept.py
       ├── [PostToolUse:Edit]   → vg_write_intercept.py
       │
       └── [Stop]               → vg_session_audit.py
```

Each hook:
1. Reads its input from stdin (Claude Code passes the tool context as JSON)
2. Loads `~/.vaultguard.json` for config
3. Loads `config/patterns.json` for credential regex patterns
4. Scans the relevant content
5. Emits output to stdout (Claude Code reads this back as a tool result annotation)
6. Optionally appends to `~/.vaultguard.log`

---

## Hook 1: `UserPromptSubmit` — Prompt Scanner

**File:** `~/.claude/hooks/vg_prompt_scan.py`

**When it fires:** Before Claude processes any user message.

**What it receives (stdin):**
```json
{
  "session_id": "...",
  "transcript_path": "...",
  "prompt": "Here is my Stripe key: sk_live_51abc..."
}
```

**What it does:**
- Extracts the `prompt` field
- Runs each enabled regex pattern against the raw text
- If a match is found in `block` mode: exits with code `2`, causing Claude Code to surface a blocking warning to the user
- If a match is found in `warn` mode: exits with code `0` but writes a warning annotation
- Logs the event to `~/.vaultguard.log` if logging is enabled

**Why the prompt hook matters:**
Users often paste credentials directly into the chat ("use this API key: sk_live_..."). Without this hook, Claude would receive the real key, potentially echo it back, use it in generated code, or include it in its context window.

---

## Hook 2: `PostToolUse:Bash` — Shell Command Guard

**File:** `~/.claude/hooks/vg_bash_guard.py`

**When it fires:** After every `Bash` tool execution.

**What it receives (stdin):**
```json
{
  "session_id": "...",
  "tool_name": "Bash",
  "tool_input": {
    "command": "export STRIPE_KEY=sk_live_51abc..."
  },
  "tool_response": {
    "stdout": "",
    "stderr": ""
  }
}
```

**What it does:**
- Scans `tool_input.command` — catches keys hard-coded into shell commands
- Scans `tool_response.stdout` and `tool_response.stderr` — catches keys echoed or printed by scripts
- In `block` mode: writes a blocking annotation to stdout telling Claude to halt follow-up actions and redact the output
- In `warn` mode: annotates the result with a warning but allows continuation

**Common patterns caught:**
- `export API_KEY=sk_live_...`
- `curl -H "Authorization: Bearer sk-ant-..."`
- Scripts that `echo` or `cat` credential files
- `printenv | grep KEY` leaking keys to the terminal

---

## Hook 3: `PostToolUse:Write|Edit` — File Write Interceptor

**File:** `~/.claude/hooks/vg_write_intercept.py`

**When it fires:** After every `Write` or `Edit` tool call.

**What it receives (stdin):**
```json
{
  "session_id": "...",
  "tool_name": "Write",
  "tool_input": {
    "file_path": "/Users/you/project/config.ts",
    "content": "const STRIPE_KEY = 'sk_live_51abc...'"
  },
  "tool_response": {}
}
```

**What it does:**
- Reads the content from `tool_input.content` (for `Write`) or reconstructs from the file path (for `Edit`)
- Scans every line for credential patterns
- Reports the file path and line number of any match
- In `block` mode: annotates the result to tell Claude the write must be redacted before proceeding
- Tracks every written file path in the session state for the final audit

**Why file interception matters:**
The most common real-world leak is an LLM writing credentials into a config file, `.env`, or TypeScript source. This hook is the last in-process safety net before the key exists on disk in the wrong place.

---

## Hook 4: `Stop` — Session Audit

**File:** `~/.claude/hooks/vg_session_audit.py`

**When it fires:** When Claude Code finishes a session (the agent stops).

**What it receives (stdin):**
```json
{
  "session_id": "...",
  "transcript_path": "/path/to/session/transcript.jsonl"
}
```

**What it does:**
- Reads the full session transcript from `transcript_path`
- Extracts all file paths that were written or edited during the session
- Re-scans each file for credential patterns (catches anything that slipped through)
- Reads the session log from `~/.vaultguard.log` to compile a summary of all events
- Prints a credential-safety summary to the terminal:

```
────────────────────────────────────────
  VaultGuard Session Audit
  Session: abc123   Duration: 4m 12s
────────────────────────────────────────
  Files written : 7
  Scans run     : 23
  Credentials   : 0 detected
  Status        : CLEAN
────────────────────────────────────────
```

If credentials were detected during the session:
```
  Status        : 2 CREDENTIAL EVENTS — review ~/.vaultguard.log
```

---

## Pattern Matching

All credential patterns are defined in `config/patterns.json`:

```json
[
  {
    "id": "stripe_live",
    "name": "Stripe Live Secret Key",
    "regex": "sk_live_[0-9a-zA-Z]{24,}",
    "severity": "critical"
  },
  ...
]
```

The hooks load this file at runtime. You can add your own patterns without modifying any Python code.

### Severity levels

| Level | Behavior in `block` mode | Behavior in `warn` mode |
|---|---|---|
| `critical` | Hard block, annotation, log | Warning annotation, log |
| `high` | Hard block, annotation, log | Warning annotation, log |
| `medium` | Warning annotation, log | Log only |
| `low` | Log only | Log only |

---

## Session State

The hooks share a lightweight session state file at `/tmp/vaultguard_<session_id>.json`. This file tracks:

- Files written this session
- Credential events detected
- Scan count

The `Stop` hook reads this file to produce the final audit summary, then removes it.

---

## Config Loading

Each hook resolves the config in this order:

1. `~/.vaultguard.json` (user global config)
2. `.vaultguard.json` in the current working directory (project-level override, if present)
3. Built-in defaults (if neither exists)

Project-level config merges with the global config — project settings win on conflicts.

---

## Exit Codes

Claude Code interprets hook exit codes as follows:

| Code | Meaning |
|---|---|
| `0` | Hook ran successfully, no blocking action |
| `1` | Hook error (logged, not blocking) |
| `2` | Blocking action — Claude Code surfaces a warning and may halt |

Vault Guard uses `2` only for `critical` and `high` severity matches in `block` mode.
