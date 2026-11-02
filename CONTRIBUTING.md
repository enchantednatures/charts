# Contributing to ksvc

Thanks for taking the time to improve these charts. Bug reports, documentation
fixes, new examples, and chart changes are all welcome.

By participating in this project you agree to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

- Search the existing issues and pull requests before opening a new one.
- For a bug, include the chart version, Kubernetes and Helm versions, a values
  snippet, and the rendered output or logs. The
  [bug report template](.github/ISSUE_TEMPLATE/bug_report.md) lists what helps.
- For a larger feature or a breaking change, open an issue first so the design
  and versioning impact can be agreed before you write code.
- Do not report security vulnerabilities in a public issue. Follow
  [SECURITY.md](SECURITY.md).

## Repository layout

The root [README](README.md) describes the charts, requirements, and release
process. In short:

- `charts/library/ksvc/` is the library chart. Its
  [README](charts/library/ksvc/README.md) is the values reference.
- `charts/app/ksvc/` is the `ksvc-app` wrapper chart.
- `examples/` contains runnable configurations used by CI.
- `test/` contains shared fixtures, including the Kyverno policy tests.
- `hack/` contains the repository automation scripts.

## Local setup

You need Helm 3.17 or newer. `make lint`, `make test`, and the example commands
also expect `kubectl` and `kind`; `make docs` uses Docker to run helm-docs.
Python 3 is needed for the schema, Kubernetes-version, requirements-docs, and
Markdown-link checks.

The usual local loop is:

```bash
make help                 # list every target

make lint                 # helm lint library + app + all examples
make test                 # helm-unittest suite
make test-schema          # values.schema.json positive + negative cases
make test-kube-version    # examples/app reject Kubernetes < 1.28
make check-docs           # README requirements drift check
make check-markdown-links # local Markdown link check

make template EXAMPLE=minimal
make update-locks         # refresh Chart.lock files after a library version bump
make docs                 # regenerate charts/library/ksvc/README.md
```

If the tools are installed, you can also run the repository hygiene checks
locally:

```bash
yamllint -c .yamllint .github/workflows/*.yaml charts examples flux
actionlint -config-file .github/actionlint.yaml
npx --yes markdownlint-cli2@0.17.2
```

These checks are available for local use. They are not wired into CI in this
change.

## Making changes

- Keep changes focused. A pull request should do one thing and include tests
  for behavior changes.
- Do not commit packaged `.tgz` charts. CI rejects them because they shadow the
  current chart source.
- Do not edit files under `.github/workflows/` unless the change is specifically
  about CI.
- When you change `values.yaml` or a template, update the generated values
  reference with `make docs`. Edit the source values comments rather than the
  generated table.
- When you bump a library chart version, refresh the committed `Chart.lock`
  files with `make update-locks`.

### Chart version bumps

Every change to a chart's packaging-relevant source must bump that chart's
`version:` in `Chart.yaml`. The PR-time gate
(`hack/check-version-bump.sh`) fails a pull request when this is missed, and the
release workflow only publishes charts whose `version:` changed on `main`.

- **Library chart (`charts/library/ksvc/`)**: a change to any file under the
  chart requires a strictly greater `version:`. Changes limited to `README.md`,
  `Chart.lock`, or `test-chart/` are exempt.
- **Application chart (`charts/app/ksvc/`)**: a change to any file under the
  chart other than `README.md`, `Chart.lock`, or `Chart.yaml` requires a
  strictly greater `version:`. Application chart versions are normally bumped
  by the dependent-chart automation, so feature pull requests should not edit
  that chart's `Chart.yaml` directly unless the change is about the wrapper.
- **Examples and docs only**: no chart version bump is needed.

Pick the version according to the [versioning policy](#versioning-and-deprecation).

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```text
<type>(<scope>): <short summary>

<body, if needed>

<footer, for breaking changes or issue references>
```

Common types:

- `feat`: a new capability
- `fix`: a bug fix
- `docs`: documentation only
- `test`: tests or fixtures
- `chore`: maintenance that does not change chart behavior
- `ci`: workflow or automation changes
- `refactor`: internal restructuring without a behavior change

Useful scopes include `ksvc`, `ksvc-app`, `examples`, `docs`, and `ci`. Keep the
summary in the imperative mood, for example `fix(ksvc): quote Kafka source
names`. Reference the issue in the body or footer.

A breaking change must include a `BREAKING CHANGE:` footer that explains the
old behavior, the new behavior, and the migration step.

## Pull requests

- Link the issue the pull request resolves.
- Explain what changed and why, not just which files changed.
- Include test evidence: the commands you ran and their results.
- Confirm the chart version bump rule above.
- Include a migration note for any breaking change.
- Fill in the release-note section so the change can be published accurately.
- Keep the branch up to date and let CI finish before asking for review.

Maintainers may ask for a smaller pull request, additional tests, or a different
versioning choice. A pull request is merged only after review and passing CI.

## Versioning and deprecation

The charts follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) for
the **public values API**. The public values API is the set of values keys
documented in the chart README and accepted by `values.schema.json`, together
with the documented behavior of the rendered resources. Internal template names,
helper names, and resource ordering are not part of the public API.

Version increments mean:

- **Major**: a breaking change to the public values API. Examples include
  removing or renaming a values key, changing a value's type, changing a
  default in a way that changes rendered behavior, or removing a rendered
  resource or feature.
- **Minor**: a backwards-compatible addition. Examples include a new optional
  values key, a new opt-in feature, or a new example.
- **Patch**: a backwards-compatible fix. Examples include correcting a template,
  tightening validation without rejecting valid existing values, or updating
  documentation and examples.

The `ksvc-app` wrapper chart follows the same rules. Its `ksvc` dependency
version moves with the library release.

### Deprecation

Deprecate before you remove:

1. Mark the values key or feature as deprecated in `values.yaml` and in the
   chart README. The note must name the replacement, if one exists.
2. Keep the deprecated behavior working for at least one minor release.
3. Record the deprecation and the removal in the release notes. When the
   repository maintains a `CHANGELOG`, add an entry there as well. The note must
   include the old key, the replacement, and a migration example.
4. Remove the behavior only in a major release. Removal is a breaking change.

A deprecation that has not been documented for at least one minor release must
not be removed.

### Experimental features

A new feature that is not ready to be covered by the compatibility promise is
marked **Experimental** in three places:

- the values comment in `values.yaml`
- the chart README entry
- the release notes for the release that introduces it

Experimental values keys may change or be removed in a minor release. They are
not covered by the SemVer guarantees above until they are promoted.

To promote an experimental feature:

1. Keep its behavior stable for at least one minor release.
2. Add or update tests and at least one example that exercises it.
3. Remove the Experimental marker from the values comment, README, and release
   notes, and announce the promotion in the release notes.

After promotion, the feature is part of the public values API.

### Breaking-change release notes

Every breaking change must use this format in the release notes and in the pull
request:

```markdown
### Breaking changes

- **Chart**: `ksvc` `<old version>` to `<new version>`
- **Affected values**: `services.<name>.<key>`
- **Before**: <the old behavior or accepted value>
- **After**: <the new behavior or required value>
- **Migration**: <the exact steps a consumer must take>
```

If more than one item breaks, use one block per item.

## Documentation

The root README, chart READMEs, and `flux/README.md` are checked for local links.
Run `make check-markdown-links` after moving or adding files. Run
`make check-docs` after changing chart requirements so the README stays in sync
with the templates and `Makefile`.

Markdown is linted with `markdownlint-cli2` using
[.markdownlint-cli2.yaml](.markdownlint-cli2.yaml).

## Security

Please read [SECURITY.md](SECURITY.md) for the supported versions and the
private reporting process.

## License

By contributing, you agree that your contributions are licensed under the
Apache License 2.0, as described in [LICENSE](LICENSE).
