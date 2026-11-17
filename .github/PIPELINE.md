# One path to production

This folder makes GitHub the only way code reaches a live site. The same folder works in every
repository; only `pipeline.yml` and `CODEOWNERS` change from one to the next.

## How a change reaches production

Everyone opens a pull request to `main`. What happens next depends on who opened it.

| Who opens the pull request | What it needs to merge |
|---|---|
| The owners | The checks pass. No approval. |
| Anyone else | The checks pass and an owner approves. |

A merge to `main` publishes to production. A push to the `staging` branch publishes to staging,
with no approval.

GitHub's own rules decide who can merge, not the workflows. A workflow runs from the pull
request's branch, so its author could edit it; the rules on `main` can't be changed from a pull
request.

- `CODEOWNERS` names the owners of every file.
- The rule "main: owner approval" requires an owner's approval, and lets the owners skip it.
- The rule "main: pull request and checks" applies to everyone, owners included.
- The `production` environment accepts the `main` branch only, so a job on any other branch
  can't read production secrets.

## What is in the folder

| File | What it does |
|---|---|
| `CODEOWNERS` | Names who approves. Edit once per repository. |
| `pipeline.yml` | Lists the sites in the repository and where each one publishes. |
| `workflows/checks.yml` | Runs on every pull request: config, committed secrets, the repository's own tests. |
| `workflows/deploy.yml` | Publishes the sites whose folder changed, after a push to `main` or `staging`. |
| `workflows/rollback.yml` | Publishes an earlier commit of one site again. Started by hand. |
| `scripts/` | What the workflows run. `scripts/targets/` holds one deploy script per kind of server. |
| `rulesets/` | The two rules for `main`, as files. |
| `setup.sh` | Applies the rules, creates the environments and turns on auto-merge. |

## Installing it in a repository

1. Copy the `.github` folder into the repository.
2. In `CODEOWNERS`, replace the placeholder with the approving user or team.
3. In `pipeline.yml`, list the repository's sites.
4. Commit and push to `main`, then run `.github/setup.sh` from the clone. In an organization,
   run `.github/setup.sh --team <team>` so that team skips the approval rule instead of the admins.
5. Create the staging branch if the repository uses one: `git push origin main:staging`.

The setup script needs the GitHub CLI. Without it, do the same by hand in the repository's
settings: import the two files from `rulesets/` under Rules, create the `production` and
`staging` environments limited to the `main` and `staging` branches, and allow auto-merge.

On the free plan the rules and environments only work in public repositories. Private
repositories need Pro or Team.

## Testing it

Use two accounts: the repository owner, and a second account added as a collaborator.

| # | Do this | Expected |
|---|---|---|
| 1 | Owner opens a pull request that edits `site/index.html` | Checks run. The owner merges with the bypass option and no approval. Production publishes. |
| 2 | Collaborator opens the same kind of pull request | Merge is blocked until the owner approves. |
| 3 | Collaborator pushes a new commit after the approval | The approval is dismissed and merge is blocked again. |
| 4 | A pull request adds a file named `.env` | The checks fail and nobody can merge, the owner included. |
| 5 | Collaborator pushes straight to `main` | The push is rejected. |
| 6 | Collaborator changes a workflow on a branch to use `environment: production` | The job is rejected because the branch isn't `main`. |
| 7 | Collaborator pushes to `staging` | Staging publishes with no approval. |
| 8 | Run Rollback with an older commit from `main` | That version publishes again. |
| 9 | Run Rollback with a commit that isn't on `main` | The run refuses it. |

What a first run on a public test repository showed:

- The owners' exception covers the approval only. With failing checks, an owner's merge is
  refused too.
- Auto-merge doesn't use the exception. An owner merges with the bypass option on the pull
  request, or with `gh pr merge --admin`.

Still to try: whether a path can be left without an owner so that content merges with no
approval. That needs the approval count at 0 in "main: owner approval".

## Not included yet

- Real deploy scripts. `simulated` reports what it would publish and touches no server. Scripts
  for each real server go in `scripts/targets/`.
- Separate identities. The two paths only work if the owners and everyone else use different
  GitHub accounts or apps.
- A shared home for the scripts. Today each repository carries its own copy of this folder.
