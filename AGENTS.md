# Repository guidelines

This repository holds reusable GitHub Actions workflows for Swift services built the
[swift-microservices skills](https://github.com/swift-microservices/skills) way. The
`delivering-swift-services` skill owns every general delivery rule; this file records what is
specific to these workflows. Read it before adding or changing one.

## Reuse first

- [swiftlang/github-workflows](https://github.com/swiftlang/github-workflows) is the default.
  Services and libraries call its `soundness.yml` and `swift_package_test.yml` directly; this
  repository never wraps them, re-exports them, or copies their inputs into a workflow that only
  forwards them.
- A workflow belongs here only when swiftlang has none for the job, or has one that cannot do it:
  - `tests.yml` is `swift_package_test.yml`'s Linux job for a package with private dependencies.
    swiftlang's workflow takes no secrets, so it cannot fetch them
    ([swiftlang/github-workflows#59](https://github.com/swiftlang/github-workflows/issues/59)).
    It keeps swiftlang's input names and formats (`linux_swift_versions`, `linux_os_versions`,
    `linux_host_archs`, `linux_pre_build_command`, `linux_build_command`, `swift_flags`), so a
    package moves between the two by changing `uses:` and `secrets:` only. Remove it if swiftlang
    gains a way to pass credentials.
  - `build-image.yml`, `deploy.yml`, and `cleanup-images.yml` have no swiftlang counterpart.
- Inside a workflow, prefer a maintained action to shell: `actions/checkout`,
  `docker/setup-buildx-action`, `docker/build-push-action`, `docker/login-action`,
  `actions/delete-package-versions`. Shell is for what no action does well: the image checks,
  the staging gate, and Dokploy's API.
- This repository's own pull requests reuse swiftlang's `soundness.yml` (YAML lint, license
  headers, unacceptable language, broken symlinks) and add only actionlint, which swiftlang lacks,
  to check every workflow and the shell in its `run:` steps.
- A list input is a JSON list, as in swiftlang's workflows (`'["6.3"]'`, `'["app-id"]'`).

## What the workflows assume

- **Trunk.** `main` is the only long-lived branch. A push to `main` builds one image, publishes it
  once as `<image_repository>:<full commit SHA>`, and deploys it to staging. No other tags are
  published, and a commit's tag is never rewritten.
- **One deploy path.** Staging (from the push) and production (from the service's manual
  workflow) both run `deploy.yml`. It resolves the commit to `:<commit-sha>@sha256:…`, so Dokploy
  shows the commit and Docker pulls by digest. Production requires a successful job whose name
  ends in `Deploy staging` in a push run of that commit, which is `deploy.yml`'s own job name for
  staging. Deploying an older commit is the rollback; nothing is rebuilt.
- **Dokploy.** Applications use the Docker provider with registry credentials and auto-deploy off.
  `deploy.yml` checks that every ID in `application_ids` names an application before changing any,
  then, one at a time in the listed order, sets the image, requests a deployment titled with the
  short commit, and waits up to 15 minutes for a deployment newer than the one before the request
  to be `done`. `error`, `cancelled`, or the timeout fails the run and leaves the rest untouched.
  It is written against Dokploy's API (`application.one`, `application.update`,
  `application.deploy`, `deployment.allByType`) with the `x-api-key` header.
- **Images.** A `Containerfile` at the repository root builds a linux/arm64 image that runs as an
  unprivileged user and has the product at `/app/<product>`, with every runtime library it links.
  The image is not started in CI; staging is where a release first runs.
- **Private packages.** `PACKAGES_TOKEN` reads the private repositories a package depends on.
  `tests.yml` writes it to `~/.netrc`; `build-image.yml` passes it as the `netrc` build secret,
  which the Containerfile mounts for `swift package resolve` only.
- **One deployment at a time** per caller repository and environment (`deploy-<environment>`),
  never cancelled midway.

## Conventions

- Pin every action and reusable workflow to its latest release's full commit with the release in
  a comment (`# v7.0.1`); `# main` only when the upstream publishes no releases.
- Logic stays inline in `run:` steps: a called workflow runs in the caller's checkout, so a script
  here would need a second checkout of this repository, and inline steps show callers exactly
  what ran.
- Steps run under GitHub's `bash -e -o pipefail`. Quote expansions, pass inputs through `env:`
  rather than interpolating them into scripts (a command input such as `linux_build_command` is
  the exception: it runs as given, as in swiftlang), and report failures with `::error::`.
- Workflow file names, inputs, secrets, and the `Deploy <environment>` job name are public API.
  Removing or renaming one is a major change.
- Files carry the compact MIT header from `.license_header_template`.

## Releases

- Every pull request carries exactly one label: `⚠️ semver/major`, `🆕 semver/minor`,
  `🔨 semver/patch`, or `semver/none`. The label check blocks merging without one.
- Releases are GitHub Releases created by the Auto Release workflow, run by hand on `main`; it
  computes the next version from the merged pull requests' labels. A major bump is cut by hand.
- Callers pin a release's commit; Dependabot's `github-actions` updates move the pins.
