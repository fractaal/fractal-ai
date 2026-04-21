#!/usr/bin/env bash
# search.sh — lean-preset semantic search over engineering scratchpads.
#
# Wraps `qmd query --no-rerank` with a preset that swaps qmd's default 1.7B
# query-expansion model for a 0.6B Qwen3 and caps context windows, so the
# M1 Pro doesn't grind. See SKILL.md for the tier ladder.
#
# Usage:
#   search.sh "<query>"                    # default: -n 5 markdown results
#   search.sh "<query>" -n 10              # pass any extra `qmd query` flags
#   search.sh "<query>" --full             # full document bodies instead of snippets
#   search.sh "<query>" --json             # JSON output for programmatic use
#
# First run after new scratchpads will re-embed only the new chunks
# (~0.4s/chunk on M1). Steady-state runs are ~1–25s depending on whether
# BM25 alone was confident enough to skip LLM expansion.

set -euo pipefail

if ! command -v qmd >/dev/null 2>&1; then
  echo "search.sh: 'qmd' not on PATH. See SKILL.md bootstrap section." >&2
  exit 127
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 \"<query>\" [extra qmd flags]" >&2
  exit 2
fi

# Lean-model preset. Env-var indirection lets callers override any single
# knob without forking the script. The big win is QMD_GENERATE_MODEL —
# dropping 1.7B → 0.6B is what unblocks running this on an M1 Pro.
export QMD_GENERATE_MODEL="${QMD_GENERATE_MODEL:-hf:ggml-org/Qwen3-0.6B-GGUF/Qwen3-0.6B-Q4_K_M.gguf}"
export QMD_EXPAND_CONTEXT_SIZE="${QMD_EXPAND_CONTEXT_SIZE:-1024}"
export QMD_RERANK_CONTEXT_SIZE="${QMD_RERANK_CONTEXT_SIZE:-2048}"
export QMD_EMBED_CONTEXT_SIZE="${QMD_EMBED_CONTEXT_SIZE:-2048}"

query="$1"; shift

# Keep index + vectors fresh. Both are no-ops when nothing new; progress goes
# to stderr so stdout only carries the final query results (clean for agents).
qmd update >&2
qmd embed  >&2

# --no-rerank: skip per-candidate LLM reranking (biggest CPU win)
# -C 20:       cap candidate pool (default 40)
# --md:        markdown output, clean for agent parsing
# -c scratchpads: skill is scoped to this collection
exec qmd query "$query" --no-rerank -C 20 --md -c scratchpads "$@"
