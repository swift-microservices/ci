# Repository guidelines

This repository holds reusable GitHub Actions workflows that test, publish and deploy Swift
libraries and services. The [README](README.md) is their documentation for callers; this file
records how they're built. Read both before adding or changing a workflow. The
[swift-microservices-architect](https://github.com/swift-microservices/swift-microservices-architect-skill)
skill's `delivery.md` states what a repository built its way declares and must pass.

## Shape

- **Pipelines** are what a repository calls: `library.yml` and `service.yml`, from its
  `pull_request.yml` and `main.yml`. A pipeline holds the standard: which jobs run on which event,
  the toolchains, the strict flags. It runs its pull-request-only jobs when `github.event_name` is
  `pull_request`, and everything else on every event. It ends with `Passed`, which fails when any
  other job failed, so a ruleset requires one check whatever the matrix.
- **Deployment adapters**, `deploy_<platform>.yml`, deploy an image to one GitHub environment.
  `deploy_dokploy.yml` is the only one. A service's `main.yml` calls one after `service.yml` with
  its `image` output, and its `deploy.yml` calls one with `promote_from`. Every adapter takes
  `environment`, `environment_url`, `image`, `promote_from` and `commit` with the same meanings,
  runs its job in the environment with `deployment: false`, and wraps its own deploy between
  `start-deployment.sh` and `finish-deployment.sh`, which record the GitHub deployment with its
  image; its own inputs and secrets follow. A deployment runs only on a push or by hand, so a
  caller's Dependabot pull request can't show what a change breaks: whatever a change newly
  requires of a caller, such as a key's permission or a platform setting, the adapter checks
  before changing anything, with an error that names it.
- **Maintenance**: `attest_image.yml`, `cleanup_images.yml`, `pull_request_label.yml` and
  `release.yml`. `attest_image.yml` is a workflow of its own, not part of `service.yml`: signing
  needs `id-token: write` and `attestations: write`, which a nested job's caller must grant
  whatever its inputs, and GitHub stores attestations for a private repository only on Enterprise
  Cloud, so requiring them would fail every private service on another plan.
- **Building blocks** are what pipelines call: `tests.yml`, `foundation_linking.yml`,
  `build_image.yml` and `publish_image.yml`. They take what they need as inputs; a pipeline reads
  the rest from the repository.

## Reuse first

- [swiftlang/github-workflows](https://github.com/swiftlang/github-workflows) does every job it
  can: the pipelines call its `soundness.yml`, `package_test.yml` (Platforms), `toolchain_matrix.yml`
  (the Tests' toolchains) and `pull_request_label.yml`, and this repository never copies them.
- A workflow belongs here only when swiftlang has none for the job, or has one that cannot do it:
  - `tests.yml` runs the toolchains `toolchain_matrix.yml` lists itself, since swiftlang's
    `package_test.yml` and `execute_matrix.yml` take no secrets, so they can't fetch private
    dependencies ([swiftlang/github-workflows#59](https://github.com/swiftlang/github-workflows/issues/59)),
    and start no service containers. It keeps `package_test.yml`'s input names, formats and
    defaults and adds only `postgres_image` and `valkey_image`. It reads only `name`, `runner`,
    `swift_build.swift_version` and `swift_build.container.image` of the matrix, the fields
    swiftlang's architecture document defines. Remove it if swiftlang gains secrets and service
    containers.
  - `foundation_linking.yml`, the image workflows, the deployment adapters and `cleanup_images.yml`
    have no swiftlang counterpart.
  - The Protobuf job runs `bufbuild/buf-action` with lint and breaking only, against the pull
    request's base in the local clone (`.git#ref=<base sha>`), since the action's default baseline
    clones the repository by URL, which a private repository's checkout without persisted
    credentials can't. Its `version` pins buf's CLI, which Dependabot doesn't read, so it's raised
    by hand, like actionlint's.
  - The OpenAPI breakage job runs `oasdiff/oasdiff-action/breaking` with `fail-on: ERR` against the
    pull request's base in the local clone (`<base sha>:<path>`), for the same reason.
    `review: false` and an empty `github-token` keep the document in CI and post nothing. When the
    base has no document yet, the job notes it and passes.
- Inside a workflow, prefer a maintained action to shell: `actions/checkout`, the `docker/*`
  actions (`docker/metadata-action` for its `labels` and `annotations` only: its `tags` never reach
  a push), `anchore/sbom-action`, `anchore/scan-action`, `actions/attest*`,
  `dataaxiom/ghcr-cleanup-action`. Shell is for what no action does well: the Foundation linking
  check, the image checks, the image's digests and platforms, the tests' matrix and environment,
  the deployment records, and Dokploy's API.
- This repository's own pull requests run swiftlang's `soundness.yml` and actionlint, which
  swiftlang lacks, on every workflow and the shell in its `run:` steps.

## What the workflows assume

- **Trunk.** The default branch is the only long-lived one. A push to it publishes the commit's
  image once as `<image_repository>:<full commit SHA>`; no other tag is published, and a commit's
  tag is never rewritten.
- **Toolchain.** A pipeline reads the package's `swift-tools-version`: Soundness and Foundation
  linking run on it, and a service's tests and Containerfile too. A library's tests run on
  swiftlang's default versions, from it up.
- **Images.** A `Containerfile` (or the file `containerfile` names) builds an image per
  architecture, each once, on a runner of that architecture (linux/arm64 for aarch64, linux/amd64
  for x86_64). The image runs as an unprivileged user, and its entrypoint, or its command when it
  has none, starts the executable. A pull request loads the image locally and pushes nothing. On
  the default branch each image is pushed by digest, untagged, pulled back for the checks, so the
  image checked is the image published, and its digest kept as an artifact; `publish_image.yml`
  tags them once the tests pass, with `imagetools create --prefer-index=false`: one architecture's
  image keeps its own manifest, several share an index carrying the OCI metadata as annotations. A
  failed run leaves only untagged uploads, which `cleanup_images.yml` deletes. The image isn't
  started in CI; staging is where a release first runs.
- **Registries.** `image_repository` defaults to `ghcr.io/<owner>/<repository>`, lowercased; a
  given one with a capital fails before anything is built. `GITHUB_TOKEN` logs in to ghcr.io;
  another registry needs `REGISTRY_USERNAME` and `REGISTRY_PASSWORD`, which `image-repository.sh`
  checks before anything is built. Images carry `docker/metadata-action`'s OCI labels, and an
  index the same as annotations, with OCI media types.
- **Tokens.** `GITHUB_TOKEN` publishes, attests, records deployments and cleans up; no personal
  access token reaches GHCR. Permissions are the caller's: a pull request's workflow grants
  `contents: read`, so nothing it runs can push, and `main.yml` grants `packages: write` to the
  pipeline and `deployments: write` to the deployment. A pipeline or building block that a
  read-only caller also calls declares no job permission above `contents: read`, since GitHub
  rejects a nested job that asks for more than its caller grants, even when it's skipped.
- **Private packages.** `PACKAGES_TOKEN` reads the private repositories a package depends on.
  `tests.yml` and `foundation_linking.yml` write it to `~/.netrc`; `build_image.yml` passes it as
  the `netrc` build secret, which the Containerfile mounts for `swift package resolve` only.
  swiftlang's workflows can't read it, so Soundness's API breakage and documentation checks and
  the Platforms can't build a package with private dependencies.
- **Postgres and Valkey.** With `postgres_image`, `tests.yml` starts it as the `postgres` service,
  with user, password and database `postgres`, and sets `POSTGRES_HOST`, `POSTGRES_PORT`,
  `POSTGRES_USER`, `POSTGRES_PASSWORD` and `POSTGRES_DB`. With `valkey_image`, it starts it as the
  `valkey` service, without TLS or a password, and sets `VALKEY_HOST` and `VALKEY_PORT`. Without
  them, it starts nothing and sets none.
- **Foundation linking.** No product, library or executable, links `libFoundation`,
  `libFoundationInternationalization` or `lib_FoundationICU`, unless excluded. Builds are dynamic,
  since `ldd` sees nothing in a static binary, and use the committed `Package.resolved` when there
  is one.
- **Deployments.** Each is a GitHub deployment of the commit to the environment, created with
  `required_contexts: []` and the image in its payload, `in_progress`, then `success`, `failure`
  or `error`. `promote_from` takes the image of that environment's newest deployment of the commit
  whose latest status is `success` or `inactive`, which GitHub sets on a successful deployment a
  newer one replaced. One deployment at a time per caller repository and environment
  (`deploy-<environment>`), never cancelled midway.
- **Dokploy.** Before changing any application, `deploy_dokploy.yml` checks that every ID in
  `application_ids` names an application whose containers the key can read, and that each one
  `run_to_completion_application_ids` lists has a restart policy whose condition is `none` and an
  update config whose failure action is `continue`. Then, one at a time in order, it sets the
  image, requests a deployment titled with the short commit, waits up to 15 minutes for a
  deployment newer than the one before the request to be `done`, then up to 10 minutes for a
  container of the deployed digest to run, healthy when it has a health check, or, for an
  application that runs to completion, for its newest new container of the digest to exit 0.
  `error`, `cancelled`, another exit code, or no such container in time fails the run and leaves
  the rest untouched. It is written against Dokploy's API (`application.one`,
  `application.update`, `application.deploy`, `deployment.allByType`,
  `docker.getContainersByAppNameMatch`, `docker.getConfig`) with the `x-api-key` header.

## Conventions

- **Names.** Workflow files and inputs are snake_case, as swiftlang's are; job IDs and scripts are
  kebab-case; job names are sentence case and name what the job checks or makes (`Tests`, `Image`,
  `Publish`). A caller's job is named for the package kind (`Library`, `Service`), so its required
  check reads `Library / Passed`. An input that exists in swiftlang's workflows keeps its
  name and meaning (`linux_swift_versions`, `linux_host_archs`, `linux_os`, `linux_command`,
  `linux_setup_command`, `linux_env_vars`, `swift_flags`). A check's setting is
  `<check>_check_<setting>` in a pipeline, as in swiftlang's `soundness.yml`
  (`foundation_linking_check_excluded_products`), and plain in a building block, whose workflow is
  its context (`foundation_linking.yml`'s `excluded_products`). Secrets are SCREAMING_SNAKE_CASE.
- **Switches.** A Boolean that turns a job or check on or off is `<job>_enabled`, which reads as a
  statement about the job, as Swift's API Design Guidelines name a Boolean, and as swiftlang's
  `soundness.yml` names its checks (`format_check_enabled`, `linux_static_sdk_build_enabled`,
  `windows_tests_enabled`). Where swiftlang names one otherwise, such as `package_test.yml`'s
  `enable_windows`, the pipeline maps it. A Boolean that changes what a job does rather than
  whether it runs keeps the name of what it drives, as `build_image.yml`'s `push` does
  `docker/build-push-action`'s.
- **Formats.** A list is a JSON list (`'["x86_64", "aarch64"]'`), a map a JSON object, an image a
  full reference. Where swiftlang takes another format, the pipeline converts it, as
  `docs_check_targets` is joined with spaces for `soundness.yml`.
- **Defaults.** Every input has the common case as its default; only what differs between
  repositories is required, such as a service's `linux_host_archs` or an adapter's applications.
  A value the workflow can read from the repository, such as the toolchain, isn't an input; one a
  repository may still need to set, such as `image_repository`, is an input whose default the
  workflow reads.
- **Inputs.** A pipeline groups its inputs under a comment naming the job they configure. Each
  description is one sentence: what the input is, its format for a list or a map (`(JSON list)`),
  and what empty means when empty does something. A secret is required only when every run needs
  it. Every input appears in the README's Inputs table with its default, and a renamed or removed
  one in the pull request's notes on moving.
- **Workflows.** A reusable workflow starts with the license header, its `name:`, and a comment
  saying what it does, on which events, who calls it, and the permissions its caller grants. A
  comment above a job or step says why it's there, not what it runs.
- **Jobs.** Every job has a `timeout-minutes` and runs on a pinned runner image, `ubuntu-24.04`
  or `ubuntu-24.04-arm`, never a `-latest` one. A job for an architecture runs on that
  architecture's runner, never under emulation. A checkout sets `persist-credentials: false` and
  fetches only what the job reads: a sparse checkout to read a file, the full history only to
  compare with a base.
- **Conditions.** A job runs only where it applies, by an `if` on the event, a switch, or a file the
  setup job found, such as `buf.yaml`; a job that always applies has none. A pull-request-only job
  tests `github.event_name == 'pull_request'`, and a default-branch-only one compares `github.ref`
  with `github.event.repository.default_branch`, never with `main` written out. Every job a
  pipeline adds is in its `Passed` job's `needs`, or a failure in it passes the required check.
- **Pins.** Every action and reusable workflow is pinned to its latest release's full commit with
  the release in a comment (`# v7.0.1`); `# main` only when the upstream publishes no releases.
  Every call to swiftlang's workflows pins the same release.
- **Self-references.** A workflow calls this repository's workflows and scripts with `$/`
  (`uses: $/.github/workflows/tests.yml`, `uses: $/.github/actions/scripts`), so they run at its
  own commit. actionlint 1.7.12 doesn't know `$/`, so this repository's actionlint step ignores
  those messages.
- **Shell** lives in `.github/scripts/*.sh`, never in a `run:` block; a step runs one script with
  `bash "$SCRIPTS/<script>.sh"`. A command input such as `linux_command` is the one `run:` that
  isn't a script: it runs as given, as in swiftlang. A script starts with `#!/bin/bash`, the `##`
  license header, a comment saying what it does and the environment it reads, and
  `set -euo pipefail`. Inputs reach it through `env:`, never interpolated into a command. It checks
  the inputs it reads before acting on them and fails early with an `::error::` that names the
  input and the form it expects, as `start-deployment.sh` does for an image without a digest. It
  quotes expansions and passes shellcheck. A value a script writes to GITHUB_OUTPUT or GITHUB_ENV
  over several lines uses a random heredoc delimiter, and its comment names every output it writes.
- **Docs.** A change updates the README, for callers, and this file, for maintainers, in the same
  pull request.
- **Headers.** Files carry the compact MIT header from `.license_header_template`.
- **API.** Workflow file names, inputs, secrets, outputs and the `Passed` job are public API.
  Renaming or removing one is a major release, whose notes say how to move.

## Releases

- Every pull request carries one label: `⚠️ semver/major`, `🆕 semver/minor`, `🔨 semver/patch`, or
  `semver/none`. The label check blocks merging without one.
- Releases are GitHub Releases created by the Release workflow, run by hand on `main`; it
  computes the next version from the merged pull requests' labels. A major release is cut by hand.
- Callers pin a release's commit; Dependabot's `github-actions` updates move the pins.
