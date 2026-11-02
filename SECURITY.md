# Security policy

## Supported versions

These charts are pre-1.0. Only the latest published release line receives
security fixes. There is no long-term support branch and no general backport
guarantee. A fix may be backported when it is low risk, but do not rely on it.

| Chart | Version | Supported |
|-------|---------|-----------|
| `ksvc` (library) | 0.10.x | Yes, current release line |
| `ksvc-app` (application) | 0.7.x | Yes, tracks `ksvc` 0.10.x |
| `ksvc` and `ksvc-app` | 1.0.x | Upcoming; supported once 1.0.0 is published |
| `ksvc` | earlier than 0.10 | No |
| `ksvc-app` | earlier than 0.7 | No |

When 1.0.0 is published, the 1.0.x line becomes the supported line and the
0.10.x line stops receiving fixes. This page will be updated at that point.

This policy covers this repository's chart templates, values, and automation.
Vulnerabilities in third-party operators, controllers, container images, or
Kubernetes itself should be reported to the upstream project.

## Reporting a vulnerability

Report vulnerabilities through GitHub Security Advisories, not in a public
issue, pull request, or discussion:

1. Open a private advisory at
   [github.com/enchantednatures/charts/security/advisories/new](https://github.com/enchantednatures/charts/security/advisories/new).
2. Describe the affected chart and version, the Kubernetes and Helm versions,
   the smallest values snippet that reproduces the problem, the rendered
   manifest or logs, the impact, and any suggested fix.
3. Do not include exploit details in public channels.

If you cannot use GitHub Security Advisories, contact
[@enchantednatures](https://github.com/enchantednatures) through GitHub without
including vulnerability details, and ask for a private channel.

The maintainers will use the advisory to acknowledge the report, discuss the
fix, and coordinate disclosure. Response times depend on maintainer
availability; this project does not promise a fixed response or fix deadline.

## Disclosure

Please give the maintainers time to investigate and release a fix before
disclosing the issue publicly. The maintainers will credit reporters in the
advisory and release notes when requested.

Security fixes follow the versioning rules in
[CONTRIBUTING.md](CONTRIBUTING.md#versioning-and-deprecation).
