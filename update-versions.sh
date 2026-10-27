#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

UPSTREAM_URL="https://github.com/JasonRivers/Docker-Nagios.git"
MODE="update" # update | check | print-build-args
SYNC_UPSTREAM=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --check             Check for newer versions without modifying files
  --sync, --rebase    Fetch and rebase onto upstream/master ($UPSTREAM_URL), then update versions
  --print-build-args  Print docker build --build-arg flags for the latest versions
  -h, --help          Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            MODE="check"
            shift
            ;;
        --sync|--rebase)
            SYNC_UPSTREAM=true
            shift
            ;;
        --print-build-args)
            MODE="print-build-args"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

get_latest_tag() {
    local repo="$1"
    local prefix_filter="${2:-}"
    local tag=""

    # Try GitHub Releases API first
    tag="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' || true)"

    # Fallback to git ls-remote if API is rate-limited or repo has no formal release
    if [[ -z "$tag" ]]; then
        if [[ -n "$prefix_filter" ]]; then
            tag="$(git ls-remote --tags --refs "https://github.com/${repo}.git" | awk -F'refs/tags/' '{print $2}' | grep -E "$prefix_filter" | sort -V | tail -n1)"
        else
            tag="$(git ls-remote --tags --refs "https://github.com/${repo}.git" | awk -F'refs/tags/' '{print $2}' | sort -V | tail -n1)"
        fi
    fi

    echo "$tag"
}

get_latest_ubuntu_lts() {
    local lts=""
    lts="$(curl -fsSL "https://hub.docker.com/v2/repositories/library/ubuntu/tags?page_size=100" 2>/dev/null \
        | jq -r '.results[].name' \
        | grep -E '^[0-9]{2}\.04$' \
        | sort -V \
        | tail -n1 || true)"
    echo "${lts:-26.04}"
}

if [[ "$SYNC_UPSTREAM" == "true" ]]; then
    if ! git remote get-url upstream >/dev/null 2>&1; then
        echo "Adding upstream remote: $UPSTREAM_URL"
        git remote add upstream "$UPSTREAM_URL"
    fi
    echo "Fetching upstream..."
    git fetch upstream
    echo "Rebasing onto upstream/master (preferring local changes on conflict, then refreshing versions)..."
    git rebase -X theirs upstream/master
    # Clean up any vim swap files if upstream accidentally committed them
    git rm -f --ignore-unmatch .Dockerfile.swp .README.md.swp >/dev/null 2>&1 || true
fi

UBUNTU_VERSION="$(get_latest_ubuntu_lts)"
NAGIOS_BRANCH="$(get_latest_tag "NagiosEnterprises/nagioscore" '^nagios-[0-9]')"
NAGIOS_PLUGINS_BRANCH="$(get_latest_tag "nagios-plugins/nagios-plugins" '^release-[0-9]')"
NRPE_BRANCH="$(get_latest_tag "NagiosEnterprises/nrpe" '^nrpe-[0-9]')"
NCPA_BRANCH="$(get_latest_tag "NagiosEnterprises/ncpa" '^v[0-9]')"
NSCA_BRANCH="$(get_latest_tag "NagiosEnterprises/nsca" '^nsca-[0-9]')"
NAGIOSTV_TAG="$(get_latest_tag "chriscareycode/nagiostv-react" '^v[0-9]')"
NAGIOSTV_VERSION="${NAGIOSTV_TAG#v}"

NAGIOS_VER="${NAGIOS_BRANCH#nagios-}"
PLUGINS_VER="${NAGIOS_PLUGINS_BRANCH#release-}"
NRPE_VER="${NRPE_BRANCH#nrpe-}"
NCPA_VER="${NCPA_BRANCH#v}"
NSCA_VER="${NSCA_BRANCH#nsca-}"

if [[ "$MODE" == "print-build-args" ]]; then
    printf -- "--build-arg UBUNTU_VERSION=%s --build-arg NAGIOS_BRANCH=%s --build-arg NAGIOS_PLUGINS_BRANCH=%s --build-arg NRPE_BRANCH=%s --build-arg NCPA_BRANCH=%s --build-arg NSCA_BRANCH=%s --build-arg NAGIOSTV_VERSION=%s\n" \
        "$UBUNTU_VERSION" "$NAGIOS_BRANCH" "$NAGIOS_PLUGINS_BRANCH" "$NRPE_BRANCH" "$NCPA_BRANCH" "$NSCA_BRANCH" "$NAGIOSTV_VERSION"
    exit 0
fi

echo "Resolved latest versions:"
echo "  Ubuntu LTS     : ${UBUNTU_VERSION}"
echo "  Nagios Core    : ${NAGIOS_BRANCH} (${NAGIOS_VER})"
echo "  Nagios Plugins : ${NAGIOS_PLUGINS_BRANCH} (${PLUGINS_VER})"
echo "  NRPE           : ${NRPE_BRANCH} (${NRPE_VER})"
echo "  NCPA           : ${NCPA_BRANCH} (${NCPA_VER})"
echo "  NSCA           : ${NSCA_BRANCH} (${NSCA_VER})"
echo "  NagiosTV       : ${NAGIOSTV_VERSION}"

if [[ "$MODE" == "check" ]]; then
    echo ""
    echo "Current Dockerfile versions:"
    grep -E '^(ARG|FROM) (UBUNTU_VERSION|ubuntu|NAGIOS_BRANCH|NAGIOS_PLUGINS_BRANCH|NRPE_BRANCH|NCPA_BRANCH|NSCA_BRANCH|NAGIOSTV_VERSION)' Dockerfile || true
    exit 0
fi

# Update Dockerfile
sed -i -E \
    -e "s|^ARG UBUNTU_VERSION=.*|ARG UBUNTU_VERSION=${UBUNTU_VERSION}|" \
    -e "s|^ARG NAGIOS_BRANCH=.*|ARG NAGIOS_BRANCH=${NAGIOS_BRANCH}|" \
    -e "s|^ARG NAGIOS_PLUGINS_BRANCH=.*|ARG NAGIOS_PLUGINS_BRANCH=${NAGIOS_PLUGINS_BRANCH}|" \
    -e "s|^ARG NRPE_BRANCH=.*|ARG NRPE_BRANCH=${NRPE_BRANCH}|" \
    -e "s|^ARG NCPA_BRANCH=.*|ARG NCPA_BRANCH=${NCPA_BRANCH}|" \
    -e "s|^ARG NSCA_BRANCH=.*|ARG NSCA_BRANCH=${NSCA_BRANCH}|" \
    -e "s|^ARG NAGIOSTV_VERSION=.*|ARG NAGIOSTV_VERSION=${NAGIOSTV_VERSION}|" \
    Dockerfile

# Update README.md
sed -i -E \
    -e "s|Ubuntu [0-9]+\.[0-9]+ LTS|Ubuntu ${UBUNTU_VERSION} LTS|" \
    -e "s|^\| Nagios Core \| .* \||\| Nagios Core \| ${NAGIOS_VER} \||" \
    -e "s|^\| Nagios Plugins \| .* \||\| Nagios Plugins \| ${PLUGINS_VER} \||" \
    -e "s|^\| NRPE \| .* \||\| NRPE \| ${NRPE_VER} \||" \
    -e "s|^\| NCPA \| .* \||\| NCPA \| ${NCPA_VER} \||" \
    -e "s|^\| NSCA \| .* \||\| NSCA \| ${NSCA_VER} \||" \
    -e "s|^\| NagiosTV \| .* \||\| NagiosTV \| ${NAGIOSTV_VERSION} \||" \
    README.md

echo "Updated Dockerfile and README.md with the latest versions."
