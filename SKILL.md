---
name: granola-transcripts
description: |
  Fetch and save Granola meeting transcripts to local files. Handles rate limiting,
  large transcript context bloat, and auto-saving via a PostToolUse hook.
  Use when the user wants to save meeting transcripts from Granola MCP.
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - mcp__granola__list_meetings
  - mcp__granola__get_meetings
  - mcp__granola__get_meeting_transcript
---

# Granola Transcript Fetcher

Fetch meeting transcripts from the Granola MCP server and save them to local files.

## The Problem

Granola transcripts are large (30-40KB). When `get_meeting_transcript` returns, the full transcript enters the conversation context window, which:

1. Makes response generation extremely slow (appears to hang)
2. Bloats context, risking hitting limits before the task is done
3. Leaves the agent stuck between "received transcript" and "write to file"

Additionally, `get_meeting_transcript` has aggressive rate limiting:
- 2-3 rapid calls trigger a lockout
- Lockout lasts 6-10 minutes
- Retries during lockout extend the timer
- Only affects transcripts; `list_meetings` and `get_meetings` are not rate limited

## The Solution: PostToolUse Hook

A hook script intercepts every `get_meeting_transcript` response and auto-saves the transcript to a pre-configured file path. The transcript still enters context (unavoidable with MCP), but no manual Write step is needed.

The hook reads a mapping file at `/tmp/granola-transcript-mapping.json` to know where each transcript should go.

## Prerequisites

Before calling any `mcp__granola__*` tools, you MUST load them via ToolSearch:
```
ToolSearch: "select:mcp__granola__list_meetings,mcp__granola__get_meetings,mcp__granola__get_meeting_transcript"
```

## Step-by-Step Process

Work in phases. Complete each phase fully before starting the next. This is critical because transcript fetches bloat context - all setup must be done first so nothing is left to do after context is heavy.

### Phase 1: Verify the hook is installed

Check that `~/.claude/settings.json` has the PostToolUse hook configured. The `command` path should point to wherever the user installed `granola-transcript-to-file.sh`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "mcp__granola__get_meeting_transcript",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/granola-transcript-to-file.sh"
          }
        ]
      }
    ]
  }
}
```

If missing, add it (merge with existing hooks, don't overwrite).

### Phase 2: Find the meetings

Use `list_meetings` (not rate limited) to get meeting metadata: IDs, titles, dates, attendees, times. Filter to the meetings the user wants.

Use `get_meetings` (not rate limited) to get AI-generated summaries/enhanced notes if the user also wants those.

### Phase 3: Create ALL target files and the mapping

Do all of this before fetching any transcripts:

1. Create all directories
2. Create all output files with headers:

```markdown
# {Meeting Title}

- **Date:** {date}, {time}
- **Attendees:** {comma-separated names}

## Transcript

```

3. Create `/tmp/granola-transcript-mapping.json` mapping each meeting ID to its absolute file path:

```json
{
  "meeting-uuid-1": "/absolute/path/to/file1.md",
  "meeting-uuid-2": "/absolute/path/to/file2.md"
}
```

4. Save summary files (if wanted) as separate files - don't embed in transcript files.

### Phase 4: Fetch transcripts ONE AT A TIME

Call `get_meeting_transcript` for each meeting sequentially. After each call:

- The hook will confirm: "Transcript saved to {path} by hook. No need to write it yourself."
- **Keep your response minimal** - just acknowledge the hook's message and move on. The 30KB+ transcript is now in your context. If you try to summarise, reference, or verbosely process it, response generation will be extremely slow. Just say "Saved. Next one in N minutes." or similar.
- Do NOT attempt to write the transcript yourself - the hook already did it.
- **Wait 4-6 minutes between EVERY fetch**, not just after rate limits. Back-to-back fetches (even just two) trigger extended lockouts.
- If rate limited, wait 10 minutes before retrying. Do not retry sooner - it extends the lockout.

Use `sleep` in a background bash command to wait between fetches:
```bash
sleep 300  # 5 minutes
```

### Phase 5: Verify

Check file sizes (not line counts - transcripts append as a single line):
```bash
wc -c /path/to/each/file.md
```

Each transcript file should be 25-40KB. If a file is under 1KB, the transcript wasn't saved.

## Critical Rules

- **NEVER fetch transcripts in parallel** - causes cascading rate limits
- **NEVER retry immediately on rate limit** - extends lockout duration
- **NEVER try to write the transcript manually** - the hook handles it
- **NEVER fetch two transcripts back-to-back** - always wait 4-6 minutes between fetches
- **ALWAYS complete phases 1-3 before starting phase 4** - setup must be done before context gets heavy
- **ALWAYS keep responses minimal after a fetch** - don't summarise or reference the transcript
- **ALWAYS create the mapping file before fetching** - hook needs it to know where to save
- **ALWAYS verify with `wc -c`** (byte count), not `wc -l` (line count)

## Idempotency Warning

The hook appends to the target file (mode `'a'`). If you fetch the same transcript twice, it will be duplicated in the file. Before fetching, check if the file already has content beyond the header:
```bash
wc -c /path/to/file.md
```
If it's already 25KB+, the transcript is already there - skip it.

## Transcript Format

Granola uses `Me:` and `Them:` speaker labels. In group calls, all non-user speakers are `Them:` with no way to distinguish individuals. The raw text has no line breaks between speaker turns.

## Troubleshooting

- **Hook errors**: Check `/tmp/granola-hook-error.log`
- **File not written**: Verify mapping file exists at `/tmp/granola-transcript-mapping.json` and has correct meeting ID
- **Rate limited on first call**: Previous session may have triggered lockout; wait 10 minutes
- **Certificate errors**: Retry once immediately; these are intermittent
- **Agent appears to hang after fetch**: The transcript bloated context. Keep response short and move on.
