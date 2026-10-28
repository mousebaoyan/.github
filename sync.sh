#!/usr/bin/env bash
# Copies the shared section of this repo's AGENTS.md into the same section of
# each target repo's AGENTS.md. Each argument is repo:mode, where mode is "pr"
# (open or refresh a PR that merges itself once the repo's checks pass) or
# "push" (commit straight to main), matching how that repo takes changes.
set -euo pipefail

start='<!-- 鼠群通用约定开始 -->'
end='<!-- 鼠群通用约定结束 -->'
branch=sync-shared-agents
source_dir=$(dirname "$0")

shared=$(mktemp)
awk -v s="$start" -v e="$end" '$0 == s { on = 1 } on { print } $0 == e { on = 0 }' \
  "$source_dir/AGENTS.md" > "$shared"
message="同步鼠群通用约定

来源：https://github.com/mousebaoyan/.github/commit/$(git -C "$source_dir" rev-parse HEAD)"

for target in "$@"; do
  repo=${target%:*}
  mode=${target#*:}
  dir=$(mktemp -d)
  gh repo clone "mousebaoyan/$repo" "$dir" -- --depth 1 --quiet
  if ! grep -qxF "$start" "$dir/AGENTS.md"; then
    echo "$repo: AGENTS.md has no shared section markers" >&2
    exit 1
  fi
  awk -v s="$start" -v e="$end" -v shared="$shared" '
    $0 == s { while ((getline line < shared) > 0) print line; skip = 1 }
    !skip { print }
    $0 == e { skip = 0 }
  ' "$dir/AGENTS.md" > "$dir/AGENTS.md.new"
  mv "$dir/AGENTS.md.new" "$dir/AGENTS.md"
  if git -C "$dir" diff --quiet; then
    echo "$repo: up to date"
    continue
  fi

  if [[ $mode == pr ]]; then
    git -C "$dir" switch -qc "$branch"
    git -C "$dir" commit -qam "$message"
    git -C "$dir" push -qf origin "$branch"
    if [[ $(gh pr list -R "mousebaoyan/$repo" --head "$branch" --json number --jq length) == 0 ]]; then
      gh pr create -R "mousebaoyan/$repo" --head "$branch" --title "同步鼠群通用约定" \
        --body "把 AGENTS.md 里的「鼠群通用约定」一节换成 [mousebaoyan/.github](https://github.com/mousebaoyan/.github/commits/main/AGENTS.md) 的最新版本，只改了这一节。仓库要求的检查通过后自动合并。"
    fi
    # GitHub refuses auto-merge on a PR that is already mergeable, which right
    # after the push gh can't always tell yet. A direct merge still has to pass
    # the repo's rules.
    gh pr merge "$branch" -R "mousebaoyan/$repo" --auto --squash ||
      gh pr merge "$branch" -R "mousebaoyan/$repo" --squash
  else
    git -C "$dir" commit -qam "$message"
    git -C "$dir" push -q origin HEAD
  fi
  echo "$repo: synced ($mode)"
done
