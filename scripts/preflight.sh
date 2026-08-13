#!/usr/bin/env bash
#
# preflight.sh — run this before Product → Archive.
#
# The rule it enforces: never archive from a tree that isn't on GitHub.
# A TestFlight build you can't trace back to a commit is a build you
# can't reproduce, hand to anyone, or safely build on top of.
#
#   ./scripts/preflight.sh
#
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
ok()  { printf '  \033[32mok\033[0m    %s\n' "$1"; }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=1; }
note(){ printf '        %s\n' "$1"; }

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
printf '\nPreflight — branch %s\n\n' "$branch"

# 1 ── nothing uncommitted
if [ -z "$(git status --porcelain)" ]; then
    ok "working tree is clean"
else
    bad "uncommitted changes — commit them before archiving"
    git status --short | sed 's/^/        /'
fi

# 2 ── nothing unpushed
git fetch origin --quiet 2>/dev/null
if git rev-parse --verify --quiet "origin/$branch" >/dev/null; then
    ahead=$(git rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo 0)
    behind=$(git rev-list --count "HEAD..origin/$branch" 2>/dev/null || echo 0)
    if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
        ok "in sync with origin/$branch"
    else
        [ "$ahead" -gt 0 ] && bad "$ahead commit(s) not pushed — run: git push"
        [ "$behind" -gt 0 ] && bad "$behind commit(s) not pulled — run: git pull"
    fi
else
    bad "no origin/$branch — this branch has never been pushed"
    note "run: git push -u origin $branch"
fi

# 3 ── the file that never travels
if [ -f Spoke/Config.swift ]; then
    ok "Config.swift present"
    for key in proxyBaseURL proxySecret anthropicAPIKey deepgramAPIKey; do
        grep -q "$key" Spoke/Config.swift || bad "Config.swift is missing $key"
    done
else
    bad "Spoke/Config.swift missing — copy Config.swift.example and fill it in"
fi

# 4 ── what this build will be
build=$(grep -m1 'CFBundleVersion:' project.yml | tr -dc '0-9')
version=$(grep -m1 'CFBundleShortVersionString:' project.yml | grep -o '"[^"]*"' | tr -d '"')
printf '\n  Version %s (%s) from commit %s\n' "${version:-?}" "${build:-?}" "$(git rev-parse --short HEAD)"
note "build numbers can't be reused — if $build is already uploaded, bump it"

if [ "$fail" -eq 0 ]; then
    printf '\n\033[32mGood to archive.\033[0m\n\n'
else
    printf '\n\033[31mFix the above first.\033[0m\n\n'
    exit 1
fi
