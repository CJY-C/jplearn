#!/usr/bin/env bash
set -euo pipefail

: "${GH_REPO:?GH_REPO is required}"
: "${APP_VERSION:?APP_VERSION is required}"
: "${RELEASE_COMMIT:?RELEASE_COMMIT is required}"

tag="v${APP_VERSION}"
if [[ "${RELEASE_REF:-}" == refs/tags/* && "${RELEASE_REF}" != "refs/tags/${tag}" ]]; then
  printf 'Tag does not match app version: %s / %s\n' "$RELEASE_REF" "$tag" >&2
  exit 1
fi

# A published version is immutable. Retrying a build never overwrites its IPA.
if gh release view "$tag" --repo "$GH_REPO" >/dev/null 2>&1; then
  printf 'Release %s already exists; keeping its original assets.\n' "$tag"
  exit 0
fi

python3 scripts/release_notes.py "$APP_VERSION" > build/release-notes.md
gh release create "$tag" build/release/JPLearn.ipa \
  --repo "$GH_REPO" --target "$RELEASE_COMMIT" \
  --title "日语拾阶 ${APP_VERSION}" --notes-file build/release-notes.md --latest
