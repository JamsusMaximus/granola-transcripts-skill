#!/bin/bash
# PostToolUse hook for mcp__granola__get_meeting_transcript
# Reads a mapping file to know where to save each transcript
#
# Install: copy this file somewhere permanent and reference it in
# ~/.claude/settings.json under hooks.PostToolUse

INPUT=$(cat)
MAPPING_FILE="/tmp/granola-transcript-mapping.json"

echo "$INPUT" | python3 -c "
import json, sys

d = json.load(sys.stdin)
meeting_id = d.get('tool_input', {}).get('meeting_id', '')

# tool_response is a list: [{'type': 'text', 'text': '{...json...}'}]
tr = d.get('tool_response', '')
if isinstance(tr, list) and len(tr) > 0 and isinstance(tr[0], dict):
    inner = tr[0].get('text', '')
    parsed = json.loads(inner)
    transcript = parsed.get('transcript', '')
elif isinstance(tr, dict):
    transcript = tr.get('transcript', '')
else:
    transcript = ''

if not meeting_id or not transcript:
    sys.exit(0)

try:
    with open('$MAPPING_FILE') as f:
        mapping = json.load(f)
except:
    sys.exit(0)

target = mapping.get(meeting_id, '')
if not target:
    sys.exit(0)

with open(target, 'a') as f:
    f.write(transcript + '\n')

print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PostToolUse', 'additionalContext': f'Transcript saved to {target} by hook. No need to write it yourself.'}}))
" 2>/tmp/granola-hook-error.log
