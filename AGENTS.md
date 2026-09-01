# Repo Agent Notes

## Dependabot YAML Linting
- In `.github/dependabot*.yml`, keep path scalars plain (`/`, `/*`) instead of quoted to satisfy `yaml/plain-scalar`.

## GitHub Actions Pinning
- Pin every `uses:` to a commit SHA with the release tag in the trailing comment; `Homebrew/actions/*` is no exception (it now warns that `master` is deprecated), so `.github/zizmor.yml` carries no `unpinned-uses` policy override.
