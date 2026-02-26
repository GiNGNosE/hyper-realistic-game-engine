#!/usr/bin/env bash
set -euo pipefail

LLVM_MAJOR="${LLVM_MAJOR:-18}"
ACTIONLINT_VERSION="${ACTIONLINT_VERSION:-1.7.7}"
SHELLCHECK_VERSION="${SHELLCHECK_VERSION:-0.10.0}"
SHFMT_VERSION="${SHFMT_VERSION:-3.8.0}"
MARKDOWNLINT_CLI2_VERSION="${MARKDOWNLINT_CLI2_VERSION:-0.14.0}"
YAMLLINT_VERSION="${YAMLLINT_VERSION:-1.35.1}"

sudo apt-get update
sudo apt-get install -y curl jq python3-pip xz-utils npm "clang-tidy-${LLVM_MAJOR}" "clang-format-${LLVM_MAJOR}"

sudo ln -sf "/usr/bin/clang-tidy-${LLVM_MAJOR}" /usr/local/bin/clang-tidy
sudo ln -sf "/usr/bin/clang-format-${LLVM_MAJOR}" /usr/local/bin/clang-format

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

# shellcheck
curl -sSL "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" -o "${tmp_dir}/shellcheck.tar.xz"
tar -xf "${tmp_dir}/shellcheck.tar.xz" -C "${tmp_dir}"
sudo install -m 0755 "${tmp_dir}/shellcheck-v${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/shellcheck

# shfmt
curl -sSL "https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_amd64" -o "${tmp_dir}/shfmt"
sudo install -m 0755 "${tmp_dir}/shfmt" /usr/local/bin/shfmt

# actionlint
curl -sSL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" -o "${tmp_dir}/actionlint.tar.gz"
tar -xf "${tmp_dir}/actionlint.tar.gz" -C "${tmp_dir}"
sudo install -m 0755 "${tmp_dir}/actionlint" /usr/local/bin/actionlint

# markdownlint-cli2 (node)
sudo npm install -g "markdownlint-cli2@${MARKDOWNLINT_CLI2_VERSION}"

# yamllint (python)
python3 -m pip install --user --disable-pip-version-check "yamllint==${YAMLLINT_VERSION}"
if [[ -d "${HOME}/.local/bin" ]]; then
  echo "${HOME}/.local/bin" >> "${GITHUB_PATH:-/dev/null}" || true
fi
