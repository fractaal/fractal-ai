#!/usr/bin/env bash
# search.sh — semantic search over engineering scratchpads.
#
# Single command that handles freshness (update + embed) then runs qmd query.
# Uses qmd's full defaults (1.7B expansion + reranking) unless --lean is passed,
# which swaps to the M1 Pro-friendly 0.6B preset with reranking disabled.
#
# Usage:
#   search.sh "<query>"                    # full semantic search (default)
#   search.sh "<query>" -n 10              # pass any extra `qmd query` flags
#   search.sh "<query>" --full             # full document bodies instead of snippets
#   search.sh "<query>" --json             # JSON output for programmatic use
#   search.sh "<query>" --lean             # M1 Pro mode: 0.6B model, no reranking

set -euo pipefail

if ! command -v qmd >/dev/null 2>&1; then
  echo "search.sh: 'qmd' not on PATH. See SKILL.md bootstrap section." >&2
  exit 127
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 \"<query>\" [--lean] [extra qmd flags]" >&2
  exit 2
fi

query="$1"; shift

lean=false
args=()
for arg in "$@"; do
  if [[ "$arg" == "--lean" ]]; then
    lean=true
  else
    args+=("$arg")
  fi
done

if [[ "$lean" == true ]]; then
  export QMD_GENERATE_MODEL="${QMD_GENERATE_MODEL:-hf:ggml-org/Qwen3-0.6B-GGUF/Qwen3-0.6B-Q4_K_M.gguf}"
  export QMD_EXPAND_CONTEXT_SIZE="${QMD_EXPAND_CONTEXT_SIZE:-1024}"
  export QMD_RERANK_CONTEXT_SIZE="${QMD_RERANK_CONTEXT_SIZE:-2048}"
  export QMD_EMBED_CONTEXT_SIZE="${QMD_EMBED_CONTEXT_SIZE:-2048}"
fi

# Keep index + vectors fresh. Both are no-ops when nothing new; progress goes
# to stderr so stdout only carries the final query results (clean for agents).
qmd update >&2
qmd embed  >&2

if [[ "$lean" == true ]]; then
  exec qmd query "$query" --no-rerank -C 20 --md -c scratchpads "${args[@]}"
else
  exec qmd query "$query" --md -c scratchpads "${args[@]}"
fi
