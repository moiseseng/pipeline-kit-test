# One path to production

This folder makes GitHub the only way code reaches a live site. The same folder works in every
repository; only `pipeline.yml` and `CODEOWNERS` change from one to the next.

## How a change reaches production

Everyone opens a pull request to `main`. What happens next depends on who opened it.

| Who opens the pull request | What it needs to merge |
|---|---|
| The owners | The checks pass. No approval. |
| A login listed under `direct_merge` | The checks pass. No approval. |
| Anyone else | The checks pass and an owner approves. |

A merge to `main` publishes to production. A push to the `staging` branch publishes to staging,
with no approval.

Whoever opens a pull request can ask for auto-merge and move on:

```bash
gh pr merge --auto --squash
```

A pull request from a login under `direct_merge` then merges on its own as soon as the checks
pass. Anyone else's merges as soon as the checks pass and an owner has approved. Without that
command a pull request stays open until someone merges it.

GitHub's own rules decide what may merge. A workflow that runs on a pull request comes from that
pull request's branch, so its author could edit it; the rules on `main` can't be changed from a
pull request.

- `CODEOWNERS` names the owners of every file.
- The rule "main: owner approval" requires an owner's approval, and lets the owners skip it.
- The rule "main: pull request and checks" applies to everyone, owners included.
- The `production` environment accepts the `main` branch only, so a job on any other branch
  can't read production secrets.

GitHub's auto-merge never uses the owners' exception, so the Auto-merge workflow does the merge
for the logins under `direct_merge`. It is safe to give it that power for three reasons:

- GitHub runs it from `main`, never from the pull request's branch, and it runs no pull request
  code.
- It checks who opened the pull request, who pushed its last commit and who asked for
  auto-merge. All three have to be listed. Changing the list takes a pull request of its own.
- It merges as a GitHub App that the approval rule lets through. The app's key sits in the
  `automerge` environment, which accepts `main` only. The checks rule still applies to it.

## What is in the folder

| File | What it does |
|---|---|
| `CODEOWNERS` | Names who approves. Edit once per repository. |
| `pipeline.yml` | Lists the sites in the repository and where each one publishes, and the logins that merge without an approval. |
| `workflows/checks.yml` | Runs on every pull request: config, committed secrets, the repository's own tests. |
| `workflows/automerge.yml` | Merges pull requests from the logins under `direct_merge` once their checks pass. |
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

To let some logins merge without an approval, add the app that does the merging:

1. Create a GitHub App in the account that owns the repository: no webhook, and the repository
   permissions Contents and Pull requests set to read and write. Install it on the repository.
2. Run `.github/setup.sh --app-id <App ID>`, together with `--team <team>` in an organization.
   The approval rule then lets the app through.
3. On the `automerge` environment, set the variable `MERGE_APP_CLIENT_ID` to the app's client ID
   and the secret `MERGE_APP_PRIVATE_KEY` to its private key.
4. List the logins under `direct_merge` in `pipeline.yml`. An app's login is its name followed by
   `[bot]`.

Keep that app for merging only, and its key nowhere but the `automerge` environment. Whoever
holds the key can merge without an approval. Agents that open pull requests get an app of their
own: listed under `direct_merge` if they are on the owners' side, and never given to the setup
script.

The setup script needs the GitHub CLI. Without it, do the same by hand in the repository's
settings: import the two files from `rulesets/` under Rules, create the `production`, `staging`
and `automerge` environments limited to the `main`, `staging` and `main` branches, and allow
auto-merge.

On the free plan the rules and environments only work in public repositories. Private
repositories need Pro or Team.

## Testing it

Use two identities: the repository owner, and a second account added as a collaborator. A GitHub
App works as the second identity too, and takes no seat in an organization.

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
| 10 | A login under `direct_merge` opens a pull request and asks for auto-merge | It merges on its own once the checks pass. Production publishes. |
| 11 | A login that isn't listed does the same | Nothing merges until an owner approves. Then GitHub merges it. |
| 12 | A listed login asks for auto-merge after the checks already passed | It merges. |
| 13 | A listed login's pull request fails its checks | Nothing merges. |
| 14 | A login that isn't listed pushes a commit to a listed login's pull request | It no longer merges on its own. |

What a first run on a public test repository showed:

- The owners' exception covers the approval only. With failing checks, an owner's merge is
  refused too.
- Auto-merge doesn't use the exception. An owner merges with the bypass option on the pull
  request, or with `gh pr merge --admin`.

What a second run showed, in a private repository of an organization on the Team plan, with a
team as the owners and a GitHub App as the second identity:

- The rules and the environments work in a private repository, and a team works as the owners.
- Every case passed except 14, which needs a third identity.
- An approved pull request with auto-merge is merged by GitHub itself, and production publishes.
- A pull request with a merge conflict gets no checks, so the Auto-merge workflow never starts
  for it and nobody is told. Whoever opened it has to notice and update the branch.

Still to try:

- Case 14.
- Whether a path can be left without an owner so that content merges with no approval. That
  needs the approval count at 0 in "main: owner approval".

## Not included yet

- Real deploy scripts. `simulated` reports what it would publish and touches no server. Scripts
  for each real server go in `scripts/targets/`.
- Separate identities. The two paths only work if the owners and everyone else use different
  GitHub accounts or apps. The folder doesn't create them.
- A notice when a pull request has a conflict with `main`.
- Cleaning up merged branches. Turn on "Automatically delete head branches" in the repository's
  settings.
- A shared home for the scripts. Today each repository carries its own copy of this folder.
