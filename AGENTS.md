# Repo Agent Notes

## Public Repository
- This repository is public, but many targets are private. Override `reason` text, commit messages and PR descriptions name the hazard, never a target's running versions, hosts or topology.

## Dependabot YAML Linting
- In `.github/dependabot*.yml`, keep path scalars plain (`/`, `/*`) instead of quoted to satisfy `yaml/plain-scalar`; `sync/templates/dependabot.yml.erb` emits them plain for the same reason.

## Dependabot Ignores
- Hold stateful datastore images (`postgres`, `redis`, `valkey`, `mysql`) at their current major in `sync/defaults.yml`. Prefix the name with `*`: Dependabot names a namespaced image `library/postgres` or `immich-app/postgres`, which a bare `postgres` does not match. A datastore major is a migration, not a version bump, and no repository here has CI that can prove the data survived one.
- A hold that applies to one repository belongs in `sync/repos/<owner>/<repo>.yml`, not in `sync/defaults.yml`; repository `ignore` entries append to the shared holds and cannot drop them.

## Dependabot Grouping
- A `groups` block defaults to `applies-to: version-updates`, so security updates stay one pull request per advisory no matter how broad the patterns are. `sync/templates/dependabot.yml.erb` emits a second `<group>-security` block per ecosystem to group those too.
- For images that must release in lockstep (Immich server and machine learning), add a named `groups` entry in the repository override rather than relying on the catch-all; with `grouped: false` there is no catch-all to catch them.
- A grouping change only reaches a target repository on the next sync run; existing ungrouped pull requests must be closed and re-triggered from the repository's Dependabot page before they come back combined.

## GitHub Actions Pinning
- Pin every `uses:` to a commit SHA with the release tag in the trailing comment; `Homebrew/actions/*` is no exception (it now warns that `master` is deprecated), so there is no zizmor `unpinned-uses` policy override; zizmor ignores go inline on the workflow that needs them, never in a config file.

## Sync Matrix
- Drop a repository from the matrix in `sync.yml` once it is archived; the target is read-only, so the job fails at the branch reset and the `conclusion` job reddens the whole run.
