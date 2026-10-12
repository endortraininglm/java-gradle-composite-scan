#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tools_root="$repo_root/.tools"
install_root="$tools_root/mandrel-java25-25.0.2.0-Final"
java_home="$install_root/Contents/Home"
url="https://github.com/graalvm/mandrel/releases/download/mandrel-25.0.2.0-Final/mandrel-java25-macos-aarch64-25.0.2.0-Final.tar.gz"
expected_sha="0b6d6c0ef85028b49080cba74c94090b73a281a01b1acf331990742ff8c6ea31"
archive=""
staging_root=""

cleanup() {
  if [[ -n "$archive" ]]; then
    rm -f "$archive"
  fi
  if [[ -n "$staging_root" ]]; then
    rm -rf "$staging_root"
  fi
}

validate_java_home() {
  local candidate="$1"
  local java_output
  local mandrel_output

  [[ -x "$candidate/bin/java" ]] || return 1
  [[ -x "$candidate/bin/native-image" ]] || return 1
  java_output="$("$candidate/bin/java" -version 2>&1)" || return 1
  mandrel_output="$("$candidate/bin/native-image" --version 2>&1)" || return 1
  [[ "$java_output" == *"25.0.2"* ]] || return 1
  [[ "$mandrel_output" == *"Mandrel-25.0.2.0-Final"* ]]
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

[[ "$(uname -s)" == "Darwin" ]] || {
  printf 'This setup script supports macOS only.\n' >&2
  exit 2
}
[[ "$(uname -m)" == "arm64" ]] || {
  printf 'This setup script supports macOS ARM64 only.\n' >&2
  exit 2
}

mkdir -p "$tools_root"

if ! validate_java_home "$java_home"; then
  rm -rf "$install_root"
  archive="$(mktemp "$tools_root/.mandrel-archive.XXXXXX")"
  staging_root="$(mktemp -d "$tools_root/.mandrel-stage.XXXXXX")"
  printf 'Downloading Mandrel 25.0.2.0-Final...\n' >&2
  curl -fL "$url" -o "$archive"

  actual_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
  [[ "$actual_sha" == "$expected_sha" ]] || {
    printf 'Mandrel SHA-256 mismatch.\nExpected: %s\nActual:   %s\n' \
      "$expected_sha" "$actual_sha" >&2
    exit 1
  }

  tar -xzf "$archive" -C "$staging_root"

  extracted_roots=()
  for candidate in "$staging_root"/*; do
    [[ -d "$candidate" ]] || continue
    if validate_java_home "$candidate/Contents/Home"; then
      extracted_roots+=("$candidate")
    fi
  done
  [[ "${#extracted_roots[@]}" -eq 1 ]] || {
    printf 'Mandrel extraction did not create one valid runtime.\n' >&2
    exit 1
  }

  extracted_root="${extracted_roots[0]}"
  if command -v xattr >/dev/null 2>&1; then
    chmod -R u+w "$extracted_root"
    xattr -c -r "$extracted_root"
  fi

  mv "$extracted_root" "$install_root"
  validate_java_home "$java_home" || {
    rm -rf "$install_root"
    printf 'Installed Mandrel runtime failed validation.\n' >&2
    exit 1
  }
fi

if command -v xattr >/dev/null 2>&1; then
  chmod -R u+w "$install_root"
  xattr -c -r "$install_root"
fi

printf '%s\n' "$java_home"
