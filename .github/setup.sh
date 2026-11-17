#!/usr/bin/env bash
# Applies the repository settings that the .github folder can't carry: the rules for main,
# the production and staging environments, and auto-merge. Safe to run again.
#
# Run it from a clone of the repository, signed in to the GitHub CLI (gh) as an admin:
#   .github/setup.sh                 the repository admins skip the approval rule
#   .github/setup.sh --team owners   organization only: that team skips it instead
set -euo pipefail

team=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --team) team="${2:?--team needs a team slug}"; shift 2 ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

for tool in gh python3; do
  command -v "$tool" >/dev/null || { echo "This script needs '$tool' installed." >&2; exit 1; }
done

here="$(cd "$(dirname "$0")" && pwd)"
if grep -q 'REPLACE-WITH-OWNER' "$here/CODEOWNERS"; then
  echo "Set the approving user or team in .github/CODEOWNERS first, and commit it." >&2
  exit 1
fi

repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
owner="${repo%%/*}"
echo "Setting up $repo"

echo "- auto-merge"
gh api -X PATCH "repos/$repo" -F allow_auto_merge=true --silent

# An environment that only its own branch can use: jobs on other branches can't read its secrets.
environment() {
  local name="$1" branch="$2"
  echo "- environment '$name', open to the '$branch' branch only"
  gh api -X PUT "repos/$repo/environments/$name" --silent --input - \
    <<< '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
  if ! gh api "repos/$repo/environments/$name/deployment-branch-policies" \
      --jq '.branch_policies[].name' | grep -qx "$branch"; then
    gh api -X POST "repos/$repo/environments/$name/deployment-branch-policies" \
      -f name="$branch" -f type=branch --silent
  fi
}
environment production main
environment staging staging

# Who skips the approval rule: the repository admins, or one team when --team is given.
bypass='[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}]'
if [[ -n "$team" ]]; then
  team_id="$(gh api "orgs/$owner/teams/$team" --jq .id)"
  bypass="[{\"actor_id\":$team_id,\"actor_type\":\"Team\",\"bypass_mode\":\"pull_request\"}]"
fi

for file in "$here"/rulesets/*.json; do
  name="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["name"])' "$file")"
  body="$(python3 - "$file" "$bypass" <<'PY'
import json, sys
ruleset = json.load(open(sys.argv[1]))
if ruleset.get("bypass_actors"):
    ruleset["bypass_actors"] = json.loads(sys.argv[2])
print(json.dumps(ruleset))
PY
)"
  id="$(gh api "repos/$repo/rulesets?includes_parents=false" --paginate \
    --jq ".[] | select(.name == \"$name\") | .id" | head -n 1)"
  if [[ -n "$id" ]]; then
    echo "- rule '$name' (updated)"
    gh api -X PUT "repos/$repo/rulesets/$id" --silent --input - <<< "$body"
  else
    echo "- rule '$name' (created)"
    gh api -X POST "repos/$repo/rulesets" --silent --input - <<< "$body"
  fi
done

echo "Done. Check the result under Settings > Rules and Settings > Environments."
