#!/usr/bin/env bash
#
# find-previous-version.sh — discover the highest published chart version
# lower than the version being released.
#
# Reads the OCI registry tag list for the chart repository and selects the
# highest SemVer tag strictly lower than --current. Unknown or non-SemVer tags
# (for example cosign signature tags) are ignored. A registry/API failure exits
# non-zero; a successful lookup with no lower version prints nothing and exits
# 0, which lets the caller skip the upgrade step for a first-ever release while
# still proving that discovery was attempted.
#
# Usage:
#   hack/release/find-previous-version.sh \
#     --repository ghcr.io/enchantednatures/charts/ksvc \
#     --current 1.0.0
#
# Authentication:
#   REGISTRY_TOKEN     optional bearer/basic credential for the registry
#   REGISTRY_USERNAME  username paired with REGISTRY_TOKEN (default x-access-token)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository=""
current=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repository) repository="${2:?--repository requires a value}"; shift 2 ;;
    --current) current="${2:?--current requires a value}"; shift 2 ;;
    -h|--help)
      sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "find-previous-version.sh: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$repository" ] || [ -z "$current" ]; then
  echo "::error::find-previous-version.sh: --repository and --current are required" >&2
  exit 2
fi

for tool in curl jq python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "::error::find-previous-version.sh requires '$tool' on PATH" >&2
    exit 1
  fi
done

repository="${repository#oci://}"
registry="${repository%%/*}"
repository_path="${repository#*/}"
if [ "$registry" = "$repository" ] || [ -z "$repository_path" ]; then
  echo "::error::--repository must be <registry>/<owner>/<chart> (got '$repository')" >&2
  exit 2
fi

token_args=()
if [ -n "${REGISTRY_TOKEN:-}" ]; then
  token_args=(-u "${REGISTRY_USERNAME:-x-access-token}:${REGISTRY_TOKEN}")
fi

# Obtain a registry pull token. GHCR (and the distribution spec generally)
# issues an anonymous token for public repositories and an authenticated token
# for private ones.
if ! token_response="$(curl -fsS --get "https://${registry}/token" \
  --data-urlencode "service=${registry}" \
  --data-urlencode "scope=repository:${repository_path}:pull" \
  "${token_args[@]}")"; then
  echo "::error::Could not request a registry token for ${repository}" >&2
  exit 1
fi

token="$(jq -r '.token // empty' <<<"$token_response")"
if [ -z "$token" ]; then
  echo "::error::Registry token response for ${repository} did not include a token" >&2
  exit 1
fi

if ! tags_json="$(curl -fsS \
  -H "Authorization: Bearer ${token}" \
  -H 'Accept: application/json' \
  "https://${registry}/v2/${repository_path}/tags/list?n=1000")"; then
  echo "::error::Could not list published tags for ${repository}" >&2
  exit 1
fi

echo "find-previous-version.sh: discovered published tags for ${repository}" >&2
python3 "${script_dir}/select-previous-version.py" --current "$current" <<<"$tags_json"
