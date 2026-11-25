# Repository guidelines

This repository holds reusable GitHub Actions workflows for Swift packages and services built the
[swift-microservices-architect](https://github.com/swift-microservices/swift-microservices-architect-skill)
way. That skill's `delivery.md` reference owns every general CI/CD rule; this file records what is
specific to these workflows. Read it before adding or changing one.

## Pipelines and building blocks

- Repositories call only this repository's workflows, never swiftlang's or Apple's: this
  repository routes to them. Every repository's CI workflow calls one CI pipeline, `library.yml` or
  `service.yml`; a library also calls `pull_request_label.yml` and `release.yml`, and a service
  `deploy_dokploy.yml` (staging and production), `cleanup_images.yml` and, where GitHub stores its
  attestations, `attest_image.yml`. A change every repository needs (a flag, a check, a pin) is
  made here once and reaches them through the pin Dependabot moves.
- A CI pipeline holds the standard: which jobs run on which event, the default toolchains, and the
  strict flags. `linux_host_archs` has no default: where a package runs is each repository's to
  state, and an image of the wrong architecture fails only at deploy. Its inputs cover only what
  differs between repositories (platforms, products,
  Postgres, Valkey, docs targets); what it can read from the repository, it reads: the toolchain from
  `swift-tools-version`, private dependencies from a passed `PACKAGES_TOKEN`, the Protobuf check
  from a `buf.yaml` at the root, and the image's name and OCI metadata from the repository.
- Deployment isn't part of a CI pipeline: `service.yml` ends at a published image, and a
  deployment adapter, `deploy_dokploy.yml`, deploys it. Another platform is another
  `deploy_<platform>.yml` with the same inputs where they apply and the same `Deploy <environment>`
  job name.
- Foundation linking always runs, so every repository has the same required checks. A product that
  still links Foundation through a dependency is named in
  `foundation_linking_check_excluded_products` until it doesn't.
- A pipeline calls this repository's workflows with `$/` (`uses: $/.github/workflows/tests.yml`), so
  they run at the pipeline's own commit. actionlint 1.7.12 doesn't know `$/`, so this repository's
  actionlint step ignores that one message.
- Changing a pipeline's behavior, such as its toolchain or a check, is a minor release: each
  repository adopts it through its own Dependabot pull request, whose CI shows what it breaks.
  Removing or renaming an input is a major release.
- A deployment adapter runs only on a push or by hand, so a caller's Dependabot pull request can't
  show what its change breaks. Whatever a change newly requires of a caller, such as a key's
  permission or a platform setting, the adapter checks before changing anything, with an error that
  names it.

## Reuse first

- [swiftlang/github-workflows](https://github.com/swiftlang/github-workflows) does every job it can:
  the pipelines call its `soundness.yml` and `swift_package_test.yml`, and this repository never
  copies them.
- A workflow belongs here only when swiftlang has none for the job, or has one that cannot do it:
  - `tests.yml` is `swift_package_test.yml`'s Linux job for a package with private dependencies
    or Postgres or Valkey tests. swiftlang's workflow takes no secrets, so it cannot fetch private
    dependencies ([swiftlang/github-workflows#59](https://github.com/swiftlang/github-workflows/issues/59)),
    and starts no service containers. It keeps swiftlang's input names and formats
    (`linux_swift_versions`, `linux_os_versions`, `linux_host_archs`, `linux_pre_build_command`,
    `linux_build_command`, `swift_flags`, `swift_nightly_flags`) and adds only `postgres_image`
    and `valkey_image`, so a package moves between the two by changing `uses:`, `secrets:`, and
    those inputs. Remove it if swiftlang gains secrets and service containers.
  - `foundation_linking.yml`, `build_image.yml`, `deploy_dokploy.yml`, `attest_image.yml`, and
    `cleanup_images.yml` have no swiftlang counterpart.
  - `attest_image.yml` is a workflow of its own, not part of `service.yml`: signing needs
    `id-token: write` and `attestations: write`, which a nested job's caller must grant whatever
    its inputs, and GitHub stores attestations for a private repository only on Enterprise Cloud,
    so requiring them would fail every private service on another plan. A service that can attest
    calls it from its own job that grants them, as it calls `deploy_dokploy.yml`. It attests the
    provenance and an SBOM it reads from the published image, so both last as long as the image.
  - `library.yml`'s Protobuf job has none either; it runs `bufbuild/buf-action` with lint and
    breaking only, when `buf.yaml` is at the root, against the pull request's base in the local
    clone (`.git#ref=<base sha>`), since the action's default baseline clones the repository by
    URL, which a private repository's checkout without persisted credentials can't. Its `version`
    pins buf's CLI, which Dependabot doesn't read, so it's raised by hand, like actionlint's.
  - `service.yml`'s OpenAPI breakage job has none either; it runs
    `oasdiff/oasdiff-action/breaking` with `fail-on: ERR` against the pull request's base in the
    local clone (`<base sha>:<path>`), for the same reason. `review: false` and an empty
    `github-token` keep the document in CI and post nothing, since the action's defaults upload an
    encrypted copy for a side-by-side review and comment its link. When the base has no document
    yet, the job notes it and passes.
- Inside a workflow, prefer a maintained action to shell: `actions/checkout`,
  `docker/setup-buildx-action`, `docker/build-push-action`, `docker/login-action`,
  `docker/metadata-action` (for its `labels` and `annotations` only: its `tags` never reach a push),
  `dataaxiom/ghcr-cleanup-action`. Shell is for what no action does well: the Foundation
  linking check, the image checks, a published image's digest and platforms, the architectures' digests, the staging gate, the OpenAPI
  document's presence in the base commit, and Dokploy's API.
- This repository's own pull requests reuse swiftlang's `soundness.yml` (YAML lint, license
  headers, unacceptable language, broken symlinks) and add only actionlint, which swiftlang lacks,
  to check every workflow and the shell in its `run:` steps.
- A list input is a JSON list, as in swiftlang's workflows (`'["6.3"]'`, `'["app-id"]'`). An
  input that passes straight through to one of swiftlang's keeps its format too, so
  `docs_check_targets` stays space-separated like `soundness.yml`'s.

## What the workflows assume

- **Trunk.** `main` is the only long-lived branch. A push to `main` builds one image, publishes it
  once as `<image_repository>:<full commit SHA>`, and deploys it to staging. No other tags are
  published, and a commit's tag is never rewritten.
- **One deploy path.** Staging (from the CI workflow's push) and production (from the service's
  manual workflow) both run `deploy_dokploy.yml`. It resolves the commit to `:<commit-sha>@sha256:…`, so Dokploy
  shows the commit and Docker pulls by digest. Production requires a successful job whose name
  ends in `Deploy staging` in a push run of that commit, which is `deploy_dokploy.yml`'s own job
  name for staging. Deploying an older commit is the rollback; nothing is rebuilt.
- **Dokploy.** Applications use the Docker provider with registry credentials and auto-deploy off.
  Before changing any, `deploy_dokploy.yml` checks that every ID in `application_ids` names an
  application whose containers the key can read, and that each one
  `run_to_completion_application_ids` lists has a restart policy whose condition is `none` and an
  update config whose failure action is `continue`. Then, one at a time in the listed order, it
  sets the image, requests a deployment titled with the short commit, waits up to 15 minutes for a
  deployment newer than the one before the request to be `done`, then up to 10 minutes for a container of the deployed digest to run, healthy when
  it has a health check. An application `run_to_completion_application_ids` lists waits instead
  for its newest container of the digest, among those that didn't exist before the request, to
  exit; exit code 0 moves on. `error`, `cancelled`, another exit code, or no such container within
  the time fails the run and leaves the rest untouched. It is written against Dokploy's API
  (`application.one`, `application.update`, `application.deploy`, `deployment.allByType`,
  `docker.getContainersByAppNameMatch`, `docker.getConfig`) with the `x-api-key` header. Docker's
  `ps` and `inspect` see only the containers on the application's server, so a Swarm that spreads
  an application across nodes must run one on the server Dokploy deploys from.
- **Images.** A `Containerfile` at the repository root builds an image for each architecture in
  `linux_host_archs` (linux/arm64 for aarch64, linux/amd64 for x86_64), each built once on a
  runner of that architecture, that runs as an unprivileged user and has the product at
  `/app/<product>`, with every runtime library it links. A pull request loads it locally and
  pushes nothing. Publishing pushes each by digest, untagged, pulls that digest back for the
  checks, so the image checked is the image published, and writes the commit's tag once every
  architecture passed, with `imagetools create --prefer-index=false`: one architecture's image
  keeps its own manifest, several share an index. A failed check leaves only an untagged upload,
  which `cleanup_images.yml` deletes. The `Build and validate image` job aggregates the
  matrix and fails unless every architecture passed, so callers require one check whatever the list.
  `attest_image.yml` attests the provenance to the tagged digest and an SBOM to each platform's.
- **Image names and metadata.** `image_repository` defaults to `ghcr.io/<owner>/<repository>`,
  lowercased, in every workflow that takes it, and `cleanup_images.yml`'s `package_name` to the
  repository's name, lowercased, so the package has the repository's name. An image reference is
  lowercase while a GitHub owner or repository may not be, so a given name with a capital fails
  before anything is built. Each platform image carries `docker/metadata-action`'s OCI labels, read
  from the repository: `org.opencontainers.image.source`, which links the package to the repository
  from its first push so it inherits the repository's access permissions, `.description`,
  `.licenses` and `.revision`, which GHCR shows on the package page. An index of several
  architectures carries them as annotations too, where GHCR reads a multi-architecture image's; a
  single image gets none, since `imagetools create` wraps an annotated image in an index. Images
  are pushed with OCI media types, which an index's annotations need.
- **Tokens.** `GITHUB_TOKEN` publishes, attests, deploys and cleans up; no personal access token
  reaches the registry, and `PACKAGES_TOKEN` only reads private dependencies. Each job is granted
  only what it needs: `packages: write` where it pushes or deletes, `packages: read` where it only
  reads. Cleanup deletes with the admin role the repository whose workflow published a package
  holds on it.
  The image is not started in CI; staging is where a release first runs. Every build keeps the
  image's SPDX SBOM as a workflow artifact (`anchore/sbom-action`) and scans it with
  `anchore/scan-action`. A pull request's build fails only on a critical vulnerability with a
  fixed version; publishing reports one without failing, since the scanner's database changes
  after the pull request passed and a deploy or a hotfix mustn't wait on it.
- **Private packages.** `PACKAGES_TOKEN` reads the private repositories a package depends on.
  `tests.yml` and `foundation_linking.yml` write it to `~/.netrc` when it's given; `build_image.yml`
  passes it as the `netrc` build secret, which the Containerfile mounts for `swift package resolve`
  only.
- **Postgres.** With `postgres_image` set, `tests.yml` starts it as the `postgres` service, with
  user, password, and database `postgres`, and sets `POSTGRES_HOST`, `POSTGRES_PORT`,
  `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB` for the tests. Without it, it starts
  nothing and leaves them unset.
- **Valkey.** With `valkey_image` set, `tests.yml` starts it as the `valkey` service, without TLS
  or a password, and sets `VALKEY_HOST` and `VALKEY_PORT` for the tests. Without it, it starts
  nothing and leaves them unset.
- **Foundation linking.** A library product, and an executable product `executable_products`
  names, links neither `libFoundation`, `libFoundationInternationalization`, nor `lib_FoundationICU`,
  unless `excluded_products` names it. Builds are dynamic, since `ldd` sees
  nothing in a static binary, and use the committed `Package.resolved` when there is one.
- **One deployment at a time** per caller repository and environment (`deploy-<environment>`),
  never cancelled midway.

## Conventions

- **Names.** Workflow files and inputs are snake_case, as swiftlang's are
  (`swift_package_test.yml`, `linux_swift_versions`); job IDs and scripts are kebab-case. An input
  that passes through to, or mirrors, swiftlang's or Apple's keeps their name. A pipeline's own
  input names the check it configures, as swiftlang's `soundness.yml` does
  (`foundation_linking_check_excluded_products`); a building block's doesn't, since the workflow
  is its context (`foundation_linking.yml`'s `excluded_products`). A value the workflow can read
  from the repository, such as the toolchain, isn't an input; one a repository may still need to
  set, such as `image_repository`, is an input whose default the workflow reads from the
  repository.
- **Deprecation.** Renaming or removing a workflow, input or secret keeps the old one as a
  deprecated alias forwarding to the new for one release, and removes it in the next major
  release, so a repository moving its pin keeps working.

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
  Removing or renaming one is a major change, after a deprecated alias.
- Files carry the compact MIT header from `.license_header_template`.

## Releases

- Every pull request carries exactly one label: `⚠️ semver/major`, `🆕 semver/minor`,
  `🔨 semver/patch`, or `semver/none`. The label check blocks merging without one.
- Releases are GitHub Releases created by the Release workflow, run by hand on `main`; it
  computes the next version from the merged pull requests' labels. A major bump is cut by hand.
- Callers pin a release's commit; Dependabot's `github-actions` updates move the pins.
