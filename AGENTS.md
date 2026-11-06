# Repository guidelines

This repository holds reusable GitHub Actions workflows for Swift packages and services built the
[swift-microservices-architect](https://github.com/swift-microservices/swift-microservices-architect-skill)
way. That skill's `delivery.md` reference owns every general CI/CD rule; this file records what is
specific to these workflows. Read it before adding or changing one.

## Pipelines and building blocks

- Repositories call only this repository's workflows, never swiftlang's or Apple's: this
  repository routes to them. Every repository calls one pipeline: `library.yml` or `service.yml`, plus `pull_request_label.yml` and `release.yml` for a library, and `deploy.yml`
  and `cleanup-images.yml` for a service. A change every repository needs (a toolchain, a flag, a
  check, a pin) is made here once and reaches them through the pin Dependabot moves.
- A pipeline holds the standard: which jobs run on which event, the default platforms, and the
  strict flags. Its inputs cover only what differs between repositories (platforms, products,
  Postgres, docs targets, application ids); a repository that needs more calls the building blocks
  directly.
- Foundation linking always runs, so every repository has the same required checks. A product that
  still links Foundation through a dependency is named in `excluded_products` until it doesn't.
- A pipeline calls this repository's workflows with `$/` (`uses: $/.github/workflows/tests.yml`), so
  they run at the pipeline's own commit. actionlint 1.7.12 doesn't know `$/`, so this repository's
  actionlint step ignores that one message.
- Changing a pipeline's behavior, such as its toolchain or a check, is a minor release: each
  repository adopts it through its own Dependabot pull request, whose CI shows what it breaks.
  Removing or renaming an input is a major release.

## Reuse first

- [swiftlang/github-workflows](https://github.com/swiftlang/github-workflows) does every job it can:
  the pipelines call its `soundness.yml` and `swift_package_test.yml`, and this repository never
  copies them.
- A workflow belongs here only when swiftlang has none for the job, or has one that cannot do it:
  - `tests.yml` is `swift_package_test.yml`'s Linux job for a package with private dependencies
    or Postgres tests. swiftlang's workflow takes no secrets, so it cannot fetch private
    dependencies ([swiftlang/github-workflows#59](https://github.com/swiftlang/github-workflows/issues/59)),
    and starts no service containers. It keeps swiftlang's input names and formats
    (`linux_swift_versions`, `linux_os_versions`, `linux_host_archs`, `linux_pre_build_command`,
    `linux_build_command`, `swift_flags`, `swift_nightly_flags`) and adds only `postgres_image`, so
    a package moves between the two by changing `uses:`, `secrets:`, and that input. Remove it if
    swiftlang gains both.
  - `foundation-linking.yml`, `build-image.yml`, `deploy.yml`, and `cleanup-images.yml` have no
    swiftlang counterpart.
- Inside a workflow, prefer a maintained action to shell: `actions/checkout`,
  `docker/setup-buildx-action`, `docker/build-push-action`, `docker/login-action`,
  `actions/delete-package-versions`. Shell is for what no action does well: the Foundation
  linking check, the image checks, the staging gate, and Dokploy's API.
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
  `tests.yml` and `foundation-linking.yml` write it to `~/.netrc` when it's given; `build-image.yml`
  passes it as the `netrc` build secret, which the Containerfile mounts for `swift package resolve`
  only.
- **Postgres.** With `postgres_image` set, `tests.yml` starts it as the `postgres` service, with
  user, password, and database `postgres`, and sets `POSTGRES_HOST`, `POSTGRES_PORT`,
  `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB` for the tests. Without it, it starts
  nothing and leaves them unset, so a test that checks for `POSTGRES_HOST` skips.
- **Foundation linking.** A library product, and an executable product `executable_products`
  names, links neither `libFoundation`, `libFoundationInternationalization`, nor `lib_FoundationICU`,
  unless `excluded_products` names the library product. Builds are dynamic, since `ldd` sees
  nothing in a static binary, and use the committed `Package.resolved` when there is one.
- **One deployment at a time** per caller repository and environment (`deploy-<environment>`),
  never cancelled midway.

## Conventions

- Pin every action and reusable workflow to its latest release's full commit with the release in
  a comment (`# v7.0.1`); `# main` only when the upstream publishes no releases.
- Shell lives in `.github/scripts/*.sh`, never in a `run:` block; a step runs one script with
  `bash "$SCRIPTS/<script>.sh"`. A called workflow runs in the caller's checkout, so it finds its
  scripts through `uses: $/.github/actions/scripts`, which returns this repository's
  `.github/scripts` at the workflow's own commit. A command input such as `linux_build_command`
  is the one `run:` that isn't a script: it runs as given, as in swiftlang.
- A script starts with `#!/bin/bash`, the `##` license header and `set -euo pipefail`, and lists
  the environment it reads. Inputs reach it through `env:`, never interpolated into a command.
  It quotes expansions, reports failures with `::error::`, and passes shellcheck, which Soundness
  runs.
- Workflow file names, inputs, secrets, and the `Deploy <environment>` job name are public API.
  Removing or renaming one is a major change.
- Files carry the compact MIT header from `.license_header_template`.

## Releases

- Every pull request carries exactly one label: `⚠️ semver/major`, `🆕 semver/minor`,
  `🔨 semver/patch`, or `semver/none`. The label check blocks merging without one.
- Releases are GitHub Releases created by the Release workflow, run by hand on `main`; it
  computes the next version from the merged pull requests' labels. A major bump is cut by hand.
- Callers pin a release's commit; Dependabot's `github-actions` updates move the pins.
