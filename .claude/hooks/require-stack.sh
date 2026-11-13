#!/usr/bin/env bash
# PreToolUse hook (Bash): refuse `gh pr create` while the author has other open pull
# requests, unless the new one is stacked (--base a branch other than main) or the
# command says why it stands alone ("# standalone: <reason>"). Related means the same files or component, a shared
# label, or one request that opens several pull requests. See AGENTS.md, "Stack
# pull requests". Fails open: any error here lets the command through.
set -u

command=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ $command =~ (^|[^[:alnum:]_-])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$) ]] || exit 0

if [[ $command =~ --base(=|[[:space:]]+)[\"\']?([^[:space:]\"\']+) && ${BASH_REMATCH[2]} != main ]]; then
  exit 0
fi
[[ $command == *"standalone:"* ]] && exit 0

open=$(gh pr list --author @me --state open --json number,title,headRefName \
  --jq '.[] | "#\(.number) \(.headRefName): \(.title)"' 2>/dev/null) || exit 0
[[ -n $open ]] || exit 0

reason="You have open pull requests:
$open

Related pull requests must be stacked (AGENTS.md): same component or files, same label (enhancement, bug, chore, documentation, ...), or opened by one request.
To stack: branch from the previous pull request's branch, open it with --base <that branch>, then run gh stack link <pr> <pr> ... If this one is unrelated to all of them, repeat the command with a trailing '# standalone: <why>'."
jq -n --arg reason "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
