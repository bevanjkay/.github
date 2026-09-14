# Repo Agent Notes

## Dependabot YAML Linting
- In `.github/dependabot*.yml`, keep path scalars plain (`/`, `/*`) instead of quoted to satisfy `yaml/plain-scalar`.

## Dependabot Ignores
- Hold stateful datastore images (`postgres`, `redis`) at their current major in `dependabot-mirror.yml`. A datastore major is a migration, not a version bump, and no repository here has CI that can prove the data survived one.

## GitHub Actions Pinning
- Pin every `uses:` to a commit SHA with the release tag in the trailing comment; `Homebrew/actions/*` is no exception (it now warns that `master` is deprecated), so there is no zizmor `unpinned-uses` policy override; zizmor ignores go inline on the workflow that needs them, never in a config file.
