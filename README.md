# Granola Transcripts Skill for Claude Code

A Claude Code skill + hook that fetches and saves [Granola](https://granola.ai) meeting transcripts to local files. Solves two problems that make Granola's MCP server painful to use with Claude Code:

1. **Context bloat** - Transcripts are 30-40KB each. They enter the conversation context and make everything slow. The hook auto-saves transcripts to files so the agent doesn't need to process them.

2. **Aggressive rate limiting** - Fetching 2-3 transcripts back-to-back triggers a 6-10 minute lockout. The skill teaches the agent to wait between fetches and never retry during a lockout.

![Granola MCP](https://www.granola.ai/updatesImages/mcp-launch.png)

## How it works

1. The **skill** (`SKILL.md`) teaches Claude Code the correct workflow: list meetings first, set up file mappings, then fetch transcripts one at a time with delays between each.

2. The **hook** (`granola-transcript-to-file.sh`) intercepts every `get_meeting_transcript` response and auto-saves the transcript to a pre-configured file path via a JSON mapping file.

## Installation

### 1. Install the hook

Copy the hook script somewhere permanent:

```bash
cp granola-transcript-to-file.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/granola-transcript-to-file.sh
```

### 2. Add to Claude Code settings

Add the PostToolUse hook to `~/.claude/settings.json` (merge with existing hooks):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "mcp__granola__get_meeting_transcript",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/YOUR_USERNAME/.claude/hooks/granola-transcript-to-file.sh"
          }
        ]
      }
    ]
  }
}
```

### 3. Install the skill

Copy `SKILL.md` to your Claude Code skills directory:

```bash
mkdir -p ~/.claude/skills/granola-transcripts
cp SKILL.md ~/.claude/skills/granola-transcripts/
```

### 4. Prerequisites

You need the [Granola MCP server](https://granola.ai) configured in Claude Code. The skill uses these MCP tools:
- `mcp__granola__list_meetings`
- `mcp__granola__get_meetings`
- `mcp__granola__get_meeting_transcript`

## Usage

Once installed, ask Claude Code to fetch your Granola transcripts:

```
Save my Granola transcripts from this week to ~/meetings/
```

The skill handles the rest - listing meetings, creating files, setting up the mapping, and fetching transcripts with appropriate delays.

## How the mapping works

Before fetching transcripts, the skill creates `/tmp/granola-transcript-mapping.json`:

```json
{
  "meeting-uuid-1": "/absolute/path/to/meeting-1.md",
  "meeting-uuid-2": "/absolute/path/to/meeting-2.md"
}
```

The hook reads this file after each transcript fetch to know where to save the content.

## Troubleshooting

| Problem | Solution |
|---|---|
| Hook errors | Check `/tmp/granola-hook-error.log` |
| Transcript not saved | Verify `/tmp/granola-transcript-mapping.json` exists and has the correct meeting ID |
| Rate limited on first call | A previous session may have triggered lockout. Wait 10 minutes. |
| Agent appears to hang | The transcript bloated context. Keep responses short after each fetch. |
| Duplicate content in file | The hook appends. If you re-fetch the same transcript, it duplicates. Check file size with `wc -c` before fetching. |

## Transcript format

Granola uses `Me:` and `Them:` speaker labels. In group calls, all non-user speakers are labelled `Them:` with no way to distinguish individuals. The raw text has no line breaks between speaker turns.
