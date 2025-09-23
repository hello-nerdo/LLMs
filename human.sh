#!/bin/bash

human() {
  if ! command -v pbcopy >/dev/null 2>&1; then
    echo "Error: pbcopy not found. This command is macOS-specific."
    return 1
  fi

  cat <<'EOF' | pbcopy
You are a skilled editor. Rewrite the TEXT below so it reads naturally, as if written by a human, while preserving its original meaning and intellectual level. Follow every rule.

1. Replace every em dash (—) _and_ en dash (–) with a comma, period, or semicolon—no dash characters may remain.
2. Strip all emojis.
3. Use everyday vocabulary and active voice. Prefer short sentences; split run-ons.
4. Swap inflated or corporate words for plain ones (e.g., “utilize → use”, “enhance → improve”).
5. Avoid formal clichés/buzzwords: accurate, adapt, advanced, align, amplify, analyze, architect, automate, benchmark, core, comprehensive, creative, cross-functional, etc.
6. Preserve all technical terms, names, dates, statistics, and existing formatting (markdown, lists, headings).
7. Do **not** add or remove ideas or sentences.
8. Output **only** the rewritten text; no headers, no commentary.
EOF
  echo "Humanize prompt copied to clipboard."
}
