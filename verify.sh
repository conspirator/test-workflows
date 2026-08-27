#!/usr/bin/env bash
# Check this scratch repository before you push it, and again any time you
# change one of the copied files.
#
# It never touches GitHub. Everything here is local.
set -uo pipefail

cd "$(dirname "$0")"
fail=0
note() { printf '%-4s %s\n' "$1" "$2"; }
ok()   { note "OK" "$2"; }
bad()  { note "BAD" "$2"; fail=1; }

echo "== the repository guard =="
# Every job in the two copied workflows must name THIS repository, or the job
# skips in silence and the test proves nothing.
remote=$(git remote get-url origin 2>/dev/null \
  | sed -E 's#(git@[^:]*:|https://[^/]*/)##; s#\.git$##')
guards=$(rg -o "github.repository == '[^']*'" .github/workflows/ci-state.yml \
  .github/workflows/reset-ci-state.yml | sed -E "s/.*== '//; s/'//" | sort -u)
count=$(echo "$guards" | grep -c .)
if [ "$count" -ne 1 ]; then
  bad "" "the guards disagree with each other: $(echo "$guards" | tr '\n' ' ')"
else
  if [ -z "$remote" ]; then
    note "??" "no origin remote yet. The guard says '$guards'."
    note "" "Add the remote, then run this again."
  elif [ "$guards" = "$remote" ]; then
    ok "" "all three guards say '$guards', which matches origin"
  else
    bad "" "the guards say '$guards' but origin is '$remote'"
    note "" "Fix with: sed -i '' \"s|$guards|$remote|g\" .github/workflows/ci-state.yml .github/workflows/reset-ci-state.yml"
  fi
fi

echo
echo "== the classifier's own tests =="
if out=$(node --test .github/scripts/ci-state.test.js 2>&1); then
  ok "" "$(echo "$out" | rg '^. (tests|pass|fail) ' | tr '\n' ' ')"
else
  bad "" "the classifier tests failed"
  echo "$out" | tail -20
fi

echo
echo "== the contract the classifier reads =="
wf=.github/workflows/build-and-test.yml
rg -q '^name: Build and Test$' "$wf" && ok "" "workflow is named 'Build and Test'" \
  || bad "" "the workflow name must be exactly 'Build and Test'"
for job in lint mac_build_and_test; do
  rg -q "^  $job:$" "$wf" && ok "" "job '$job' exists" || bad "" "job '$job' is missing"
done
rg -q '^    needs: lint$' "$wf" && ok "" "mac_build_and_test needs lint, so a lint failure skips it" \
  || bad "" "mac_build_and_test must declare 'needs: lint'"
rg -qF 'name: "Infra: fake check"' "$wf" && ok "" "the build-machine step carries the Infra: prefix" \
  || bad "" "the build-machine step must be named \"Infra: fake check\""
rg -qF 'name: Build (Xcode, macOS)' "$wf" && ok "" "a step the author owns exists" \
  || bad "" "a non-Infra step is missing"

echo
echo "== no job holding a write token touches the pull request head =="
if rg -q 'head_branch|pull_request\.head|refs/pull' .github/workflows/ci-state.yml \
     .github/workflows/reset-ci-state.yml; then
  bad "" "a copied workflow names the contributor head"
else
  ok "" "neither copied workflow names the contributor head"
fi

echo
echo "== the workflows parse =="
if command -v uv >/dev/null 2>&1; then
  if uv run --quiet --with pyyaml python - <<'PY'
import glob, sys, yaml
for path in sorted(glob.glob('.github/workflows/*.yml')):
    with open(path) as handle:
        yaml.safe_load(handle)
    print("   parsed", path)
PY
  then ok "" "all workflow files parse"
  else bad "" "a workflow file does not parse"
  fi
else
  note "??" "uv not found, skipped the parse check"
fi

echo
[ "$fail" -eq 0 ] && echo "Ready to push." || echo "Fix the BAD lines above first."
exit "$fail"
