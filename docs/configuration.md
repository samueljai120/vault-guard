# Configuration Reference

Vault Guard is configured via `~/.vaultguard.json`. A default file is created automatically when you run `install.sh`. You never need to edit it for full out-of-the-box protection — all defaults are safe.

A project-level `.vaultguard.json` in your working directory will override the global config for that project. Project settings win on any conflicting keys.

---

## Full Schema

```json
{
  "version": 1,
  "mode": "block",
  "projects": [
    {
      "name": "default",
      "path": "~",
      "patterns": "all"
    }
  ],
  "notifications": {
    "terminal": true,
    "log_file": "~/.vaultguard.log"
  },
  "allow_test_keys": false,
  "exempt_paths": [],
  "disabled_patterns": [],
  "severity_overrides": {}
}
```

---

## Top-Level Fields

### `version`
**Type:** integer
**Default:** `1`
**Description:** Schema version. Do not change — used for future migrations.

---

### `mode`
**Type:** `"block"` | `"warn"`
**Default:** `"block"`
**Description:** Controls what happens when a credential is detected.

| Value | Behavior |
|---|---|
| `"block"` | Hook exits with code `2`. Claude Code surfaces a blocking warning. The prompt, command, or file write is flagged for review. Recommended for production. |
| `"warn"` | Hook exits with code `0`. Claude Code receives a warning annotation but continues. Recommended for CI or read-heavy sessions where you want visibility without interruption. |

**Example:**
```json
{ "mode": "warn" }
```

---

### `projects`
**Type:** array of project objects
**Default:** single entry covering `~`
**Description:** Per-project configuration. Vault Guard matches the Claude Code working directory against each project's `path` and applies the first match. If no project matches, the `default` entry (path `~`) is used.

**Project object schema:**

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Human-readable label |
| `path` | string | yes | Absolute or `~`-prefixed path. Matched as a prefix against the CWD. |
| `patterns` | `"all"` \| array of IDs | no | Which patterns to enable. `"all"` enables every pattern in `config/patterns.json`. |
| `mode` | `"block"` \| `"warn"` | no | Overrides the top-level `mode` for this project |
| `allow_test_keys` | boolean | no | Overrides top-level `allow_test_keys` for this project |

**Example — per-project config:**
```json
{
  "version": 1,
  "mode": "block",
  "projects": [
    {
      "name": "my-saas",
      "path": "~/Documents/my-saas",
      "patterns": "all",
      "mode": "block"
    },
    {
      "name": "test-sandbox",
      "path": "~/Documents/sandbox",
      "patterns": ["stripe_live", "anthropic"],
      "mode": "warn",
      "allow_test_keys": true
    },
    {
      "name": "default",
      "path": "~",
      "patterns": "all"
    }
  ]
}
```

---

### `notifications`
**Type:** object
**Description:** Controls how credential events are reported.

| Field | Type | Default | Description |
|---|---|---|---|
| `terminal` | boolean | `true` | Print a warning to the terminal when a credential is detected |
| `log_file` | string \| `null` | `"~/.vaultguard.log"` | Path to the append-only log file. Set to `null` to disable file logging. |

**Example — disable file logging:**
```json
{
  "notifications": {
    "terminal": true,
    "log_file": null
  }
}
```

---

### `allow_test_keys`
**Type:** boolean
**Default:** `false`
**Description:** When `true`, credentials matching test-mode prefixes (`sk_test_`, `pk_test_`, etc.) are downgraded from `high` to `low` severity and produce no blocking action or terminal warning. Useful in development environments where test keys are routine.

**Example:**
```json
{ "allow_test_keys": true }
```

---

### `exempt_paths`
**Type:** array of strings
**Default:** `[]`
**Description:** File paths or directories where all credential scanning is skipped. Supports `~` expansion. Use for test fixture directories or paths where fake/example credentials are expected and safe.

**Example:**
```json
{
  "exempt_paths": [
    "~/.ssh/",
    "~/.gnupg/",
    "~/Documents/my-project/tests/fixtures/",
    "~/Documents/my-project/docs/"
  ]
}
```

Path matching rules:
- If the exempt path ends with `/`, it matches any file under that directory
- If it does not end with `/`, it matches that exact file path
- `~` is expanded to the current user's home directory

---

### `disabled_patterns`
**Type:** array of pattern ID strings
**Default:** `[]`
**Description:** Pattern IDs from `config/patterns.json` to disable globally. Disabled patterns produce no scan result, warning, or log entry.

**Example:**
```json
{
  "disabled_patterns": [
    "supabase_anon",
    "slack_webhook",
    "jwt_generic"
  ]
}
```

Find all pattern IDs with: `vg patterns`

---

### `severity_overrides`
**Type:** object mapping pattern ID to severity string
**Default:** `{}`
**Description:** Override the built-in severity for any pattern. Useful for elevating medium-severity patterns to `high` or `critical` in sensitive projects.

Valid severity values: `"critical"`, `"high"`, `"medium"`, `"low"`

**Example:**
```json
{
  "severity_overrides": {
    "supabase_anon": "high",
    "slack_webhook": "critical",
    "vercel": "critical"
  }
}
```

---

## Minimal Configs

### Strictest (production default)
```json
{
  "version": 1,
  "mode": "block",
  "projects": [{ "name": "default", "path": "~", "patterns": "all" }],
  "allow_test_keys": false
}
```

### Permissive development
```json
{
  "version": 1,
  "mode": "warn",
  "allow_test_keys": true,
  "disabled_patterns": ["jwt_generic", "supabase_anon"],
  "projects": [{ "name": "default", "path": "~", "patterns": "all" }]
}
```

### Mixed — strict in production path, relaxed in sandbox
```json
{
  "version": 1,
  "mode": "block",
  "projects": [
    {
      "name": "production",
      "path": "~/Documents/production-app",
      "mode": "block",
      "allow_test_keys": false
    },
    {
      "name": "sandbox",
      "path": "~/Documents/sandbox",
      "mode": "warn",
      "allow_test_keys": true
    },
    {
      "name": "default",
      "path": "~",
      "patterns": "all"
    }
  ]
}
```

---

## Config Precedence

Settings are resolved in this order (highest to lowest priority):

1. Project-level `.vaultguard.json` in the Claude Code working directory
2. Matching `projects[]` entry in `~/.vaultguard.json`
3. Top-level keys in `~/.vaultguard.json`
4. Built-in defaults

---

## Editing Your Config

```bash
vg config
```

This opens `~/.vaultguard.json` in your `$EDITOR`. Changes take effect on the next Claude Code session.
