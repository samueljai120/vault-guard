# Configuration Reference

Vault Guard is configured via `~/.vaultguard.json`. A default file is created automatically when you run `install.sh`. You never need to edit it for full out-of-the-box protection — all defaults are safe.

---

## Full Schema

```json
{
  "version": "1",
  "default_project": "my-project",
  "projects": [
    {
      "id": "my-project",
      "name": "My Project",
      "keychain_service": "my-project",
      "dir": "~/Documents/my-project",
      "key_prefixes": ["MY_PROJECT_", "STRIPE_", "OPENAI_"]
    }
  ]
}
```

---

## Top-Level Fields

### `version`
**Type:** string
**Default:** `"1"`
**Description:** Schema version. Do not change — used for future migrations.

---

### `default_project`
**Type:** string
**Default:** `"vault-guard"`
**Description:** The project ID to use when a credential can't be matched to any project by file path or key prefix. Must match one of the `id` values in the `projects` array.

---

### `projects`
**Type:** array of project objects
**Description:** Each project defines a separate Keychain namespace. Credentials are routed to the first matching project.

**Project object schema:**

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | yes | Unique identifier (used in CLI commands like `vault-guard list my-project`) |
| `name` | string | yes | Human-readable label (displayed in terminal output) |
| `keychain_service` | string | yes | macOS Keychain service name. Each project gets its own isolated namespace. |
| `dir` | string | no | Absolute or `~`-prefixed path. When Claude writes a file inside this directory, the credential is routed to this project. |
| `key_prefixes` | array of strings | no | If the credential's key name starts with any of these prefixes, it's routed to this project. |

---

## How Project Routing Works

When a credential is detected, Vault Guard decides which project to store it under:

1. **File path match** — if the credential was found in a file inside a project's `dir`, that project wins
2. **Key prefix match** — if the key name starts with one of a project's `key_prefixes`, that project wins
3. **Default** — falls back to `default_project`

---

## Example — Multiple Projects

```json
{
  "version": "1",
  "default_project": "main-app",
  "projects": [
    {
      "id": "main-app",
      "name": "Main Application",
      "keychain_service": "main-app",
      "dir": "~/Documents/main-app",
      "key_prefixes": ["STRIPE_", "OPENAI_", "ANTHROPIC_"]
    },
    {
      "id": "staging",
      "name": "Staging Environment",
      "keychain_service": "staging",
      "dir": "~/Documents/staging",
      "key_prefixes": ["STAGING_"]
    }
  ]
}
```

With this config:
- `STRIPE_SECRET_KEY` pasted in chat → routes to `main-app` (prefix match)
- A credential found in `~/Documents/staging/server/.env` → routes to `staging` (path match)
- `RANDOM_API_KEY` pasted in chat → routes to `main-app` (default)

---

## Editing Your Config

```bash
vault-guard projects       # list configured projects
nano ~/.vaultguard.json    # edit manually
```

Changes take effect on the next Claude Code message (hooks reload config on every invocation).
