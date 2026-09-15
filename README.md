# Shared configuration

`sync.yml` keeps a small set of files in step across every repository in its
matrix by opening a pull request in each one whenever the copy here changes.
`actionlint.yml` is copied verbatim; `dependabot.yml` is rendered per
repository, so one repository can hold a dependency the rest of the fleet does
not.

| Hub file                            | Target path                       |
| ----------------------------------- | --------------------------------- |
| `.github/workflows/actionlint.yml`  | `.github/workflows/actionlint.yml` |
| `sync/templates/dependabot.yml.erb` | `.github/dependabot.yml`          |

## Per-repository overrides

`sync/render.rb` renders `.github/dependabot.yml` from `sync/defaults.yml`. A
repository that needs to differ gets `sync/repos/<owner>/<repo>.yml`; every
repository without one renders the defaults byte for byte.

```yaml
# sync/repos/bevanjkay/rss-boi.yml
schema: 1
dependabot:
  docker:
    ignore:
      - dependency-name: node
        reason: |-
          Track the Node LTS line for published images.
        versions:
          - ">=25"
```

Overrides are keyed by ecosystem. `ignore` entries append to the shared holds,
so a repository can add a hold but never drop a fleet-wide one. `skip: true`
omits an ecosystem the repository does not use, and `directory`/`directories`
repoints one. A `reason` becomes the comment above the entry in the rendered
file, so the why survives into the target repository. Render locally with
`ruby sync/render.rb <owner> <repo> /dev/stdout`.

zizmor configuration is deliberately not synced. A `dangerous-triggers` ignore
belongs on the `on:` line of the workflow that needs it, with the reason beside
it, so a repository never depends on a name-based ignore list held elsewhere:

```yaml
on: # zizmor: ignore[dangerous-triggers] -- comments only, no checkout of PR code
  pull_request_target:
```

The synced `actionlint.yml` is a thin caller of `reusable-actionlint.yml` in
this repository, pinned to a tagged commit. It exposes one stable job,
`conclusion`, which is the check every target requires.

The sync runs on push to `main`, weekly, and on manual dispatch. It authenticates
with a GitHub App, creates the commit through the GraphQL API so GitHub signs it,
and enables auto-merge on the pull request. When the target repository's rules
are satisfied the pull request merges itself; when they are not, the run warns
and leaves the pull request open for a manual merge.

## One-time setup: the GitHub App

1. Create the App under the `bevanjkay` account (Settings → Developer settings →
   GitHub Apps → New GitHub App).
   - Webhook: unticked.
   - Repository permissions: **Contents: Read and write**, **Pull requests: Read
     and write**, **Workflows: Read and write**. Metadata is added automatically.
     Workflows is required because the sync writes under `.github/workflows/`.
   - Where can this App be installed: **Any account**, so `gatewaymedia` can
     install it too.
2. Note the **Client ID** and generate a **private key** (a `.pem` download).
3. Install the App on `bevanjkay` and on `gatewaymedia`. Choose **Only select
   repositories** and tick the repositories in the matrix for that owner. A
   repository the App is not installed on fails at the "Mint read token" step.
4. In this repository, environment `github_actions`:
   - Secret `SYNC_APP_PRIVATE_KEY`: the full contents of the `.pem` file.
   - Variable `SYNC_APP_CLIENT_ID`: the Client ID (a repository variable works too).
5. Delete the `BKDBOT_TOKEN` secret once a sync run has succeeded.

If the App's permissions are ever changed, every installation has to approve the
new permissions before tokens carry them.

## Per-repository prerequisites

Auto-merge is deliberately not something the workflow can grant itself. Each
target needs all of the following on its default branch, or its sync pull
requests stay open for a manual merge:

- **Allow squash merging** and **Allow auto-merge** enabled in Settings →
  General → Pull Requests. Deleting head branches on merge is optional; the
  workflow resets the branch every run either way.
- A ruleset (or branch protection) that **requires a pull request** and
  **requires the `conclusion` status check** to pass. Without at least one
  requirement GitHub refuses to enable auto-merge, and the run warns.
- No bypass entry for the sync App in that ruleset, so the check is the gate.
- For repositories in an organisation whose Actions policy is "selected
  actions and reusable workflows", allow
  `bevanjkay/.github/.github/workflows/reusable-actionlint.yml@*`
  (Organisation settings → Actions → General).

Private repositories need nothing extra: the reusable workflow skips the code
scanning uploads there, and the `security-events: write` grant in the caller is
unused.

The settings and ruleset can be applied from the command line with an
account that administers the target:

```bash
OWNER=bevanjkay REPO=example

gh api -X PATCH "repos/${OWNER}/${REPO}" \
  -F allow_squash_merge=true -F allow_auto_merge=true -F delete_branch_on_merge=true

gh api -X POST "repos/${OWNER}/${REPO}/rulesets" --input - <<'JSON'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["squash"]
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "do_not_enforce_on_create": false,
        "required_status_checks": [
          { "context": "conclusion", "integration_id": 15368 }
        ]
      }
    }
  ]
}
JSON
```

`15368` is the GitHub Actions app, so only a check produced by Actions
satisfies the rule. Repositories that already have a ruleset on the default
branch only need the `required_status_checks` rule added to it.

## Adding a repository

1. Install the App on it (Settings → Applications for the owner, edit the
   installation's repository list).
2. Apply the settings and ruleset above.
3. Add an `owner`/`repo` entry to the matrix in `sync.yml` and merge.
4. Watch the sync run. The first pull request adds `actionlint.yml`, and the
   `conclusion` check it introduces runs on that same pull request, so it can
   auto-merge on the first pass.

A repository can also be primed by hand: copy the three files in, commit, and
the next sync finds nothing to do.

## Changing the shared checks

Edits to `reusable-actionlint.yml` reach the matrix only through the pin in
`actionlint.yml`:

1. Merge the change to `main`.
2. Tag it: `git tag v<yyyy.mm.dd> <sha> && git push origin v<yyyy.mm.dd>`.
3. Bump the `uses:` pin in `actionlint.yml` to that SHA with the tag in the
   trailing comment. Dependabot opens this pull request on its own because the
   hub's `dependabot.yml` does not exclude `actionlint.yml`; the mirrored
   `dependabot.yml` does, so targets never bump the pin themselves.
4. Merging the bump triggers the sync, which propagates it.

Zizmor's `ref-version-mismatch` audit checks that the comment names a tag that
resolves to the pinned SHA, so a pin whose tag has not been pushed yet shows as
a warning until step 2 is done.

Note that this repository's own `actionlint.yml` also runs the *pinned* reusable
workflow, so a pull request that edits `reusable-actionlint.yml` is not
exercised by CI until the pin is bumped.

## Reading a sync run

- `changed=false` in "Detect changes": the target is already up to date.
- Failure at "Mint read token" or "Mint write token": the App is not installed
  on that repository, or the installation has not accepted the Workflows
  permission.
- Warning `could not enable auto-merge`: the commit and pull request exist, but
  one of the per-repository prerequisites is missing. Fix it and merge the pull
  request by hand; later runs enable auto-merge themselves.
- Error `is not owned by`: an open pull request from `sync-shared-config` was
  raised by someone other than the App. Close it or rename its branch; the
  workflow never takes over a branch it did not create.
