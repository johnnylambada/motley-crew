# /mcworkers — List Active Workers

When the user sends `/mcworkers`, list all workers.

## Scoping

1. Read `IDENTITY.md` to determine your role.
2. **If Project Lead:** List workers for this project only (filter by repo URL).
3. **If Chief of Staff:** List all workers across all projects.

## Workflow

### Step 1: Run list script
```bash
~/motley-crew/scripts/list-workers.sh
```

This outputs a table:
```
NAME         TEMPLATE        ROLE       MODEL    CREATED
----         --------        ----       -----    -------
Alice        dev-sonnet      Developer  Sonnet   2026-02-20
Bob          reviewer-opus   Reviewer   Opus     2026-02-20
```

### Step 2: Filter (if Lead)

If you're a project lead, filter the output to only show workers whose `Project repo` in IDENTITY.md matches your project's repo URL.

### Step 3: Report

Post the table to the Discord channel. If no workers exist, say so and suggest `/mcworker <template>` to create one.

## Notes
- Workers are permanent and cost nothing when idle
- Use `/mcworker <template>` to spawn new workers
- Workers are only removed when a project is offboarded
