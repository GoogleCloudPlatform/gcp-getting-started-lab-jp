# .phase-status.json

Lightweight phase tracking. This is the SINGLE source of truth for the `.phase-status.json` schema. All steering files reference this definition.

```json
{
  "migration_id": "0412-1030",
  "last_updated": "2026-04-12T10:30:00Z",
  "phases": {
    "discover": "completed",
    "clarify": "completed",
    "design": "in_progress",
    "estimate": "pending",
    "generate": "pending"
  }
}
```

**Field Definitions:**

| Field           | Type     | Set When                                                           |
| --------------- | -------- | ------------------------------------------------------------------ |
| `migration_id`  | string   | Created (matches folder name, never changes)                       |
| `last_updated`  | ISO 8601 | After each phase update                                            |
| `phases.<name>` | string   | Phase transitions: `"pending"` -> `"in_progress"` -> `"completed"` |

**Rules:**

- Phase status progresses: `"pending"` -> `"in_progress"` -> `"completed"`. Never goes backward, with ONE exception: a phase that ends `"failed"` (legal terminal for incomplete MANDATORY output, e.g. Generate under budget pressure) transitions `"failed"` -> `"in_progress"` when the user re-runs it.
- Valid status values: `pending`, `in_progress`, `completed`, `failed`.
- Valid phase names: discover, clarify, design, estimate, generate.
- `migration_id` matches the `$MIGRATION_DIR` folder name (e.g., `0412-1030`).
