# ci

Reusable GitHub Actions workflows that test, publish and deploy Swift packages: libraries, and
services that ship as a container image. A repository's workflows call these and nothing else; they
build on [swiftlang/github-workflows](https://github.com/swiftlang/github-workflows), so a new Swift
release, check or flag reaches every repository through the one pin Dependabot moves.

Every default is the common case, so a repository passes only what is its own: the architectures
its servers run, the databases its tests need, the applications it deploys to.

## Workflows

| Workflow | Called from | Does |
| --- | --- | --- |
| `library.yml` | `pull_request.yml`, `main.yml` | A library's CI: Soundness, Tests, Platforms, Foundation linking, Protobuf |
| `service.yml` | `pull_request.yml`, `main.yml` | A service's CI: Soundness, Tests, Foundation linking, OpenAPI breakage, Image; on `main`, publishes the image |
| `deploy_dokploy.yml` | `main.yml`, `deploy.yml` | Deploys an image to an environment's Dokploy applications |
| `attest_image.yml` | `main.yml` | Signs a published image's build provenance and SBOMs |
| `cleanup_images.yml` | `cleanup_images.yml` | Keeps the newest commits' images on GHCR and deletes the rest |
| `pull_request_label.yml` | `pull_request_label.yml` | Requires a semver label on a library's pull request |
| `release.yml` | `release.yml` | Releases a library's next minor or patch version from the merged pull requests' labels |

The pipelines are built from these, which a repository with an unusual need can call too:

| Building block | Does |
| --- | --- |
| `tests.yml` | swiftlang's Linux tests with private dependencies, Postgres and Valkey, which swiftlang's own can't give |
| `foundation_linking.yml` | Fails when a product links Foundation's full library or ICU |
| `build_image.yml` | Builds, checks and scans the image for each architecture; optionally pushes each by digest |
| `publish_image.yml` | Tags the pushed images once as `:<commit-sha>` |

## A library

```yaml
# .github/workflows/pull_request.yml
name: PR

on:
  pull_request:
    types: [opened, reopened, synchronize]

permissions:
  contents: read

concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  library:
    name: Library
    uses: swift-microservices/ci/.github/workflows/library.yml@<commit>  # <release>
```

```yaml
# .github/workflows/main.yml
name: Main

on:
  push:
    branches: [main]
  schedule:
    - cron: "0 6 * * 1"

permissions:
  contents: read

jobs:
  library:
    name: Library
    uses: swift-microservices/ci/.github/workflows/library.yml@<commit>  # <release>
```

```yaml
# .github/workflows/pull_request_label.yml
name: PR label

on:
  pull_request:
    types: [labeled, unlabeled, opened, reopened, synchronize]

permissions:
  contents: read

jobs:
  label:
    name: PR label
    permissions:
      contents: read
      pull-requests: read
    uses: swift-microservices/ci/.github/workflows/pull_request_label.yml@<commit>  # <release>
```

```yaml
# .github/workflows/release.yml
name: Release

on:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  release:
    name: Release
    if: github.ref == 'refs/heads/main'
    permissions:
      contents: write
      pull-requests: read
    uses: swift-microservices/ci/.github/workflows/release.yml@<commit>  # <release>
```

`pull_request.yml` and `main.yml` pass the same inputs, such as a library whose tests need Postgres:

```yaml
    with:
      postgres_image: postgres:18-alpine
      foundation_linking_check_excluded_products: '["PersistencePostgres"]'
```

## A service

```yaml
# .github/workflows/pull_request.yml
name: PR

on:
  pull_request:
    types: [opened, reopened, synchronize]

permissions:
  contents: read

concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  service:
    name: Service
    uses: swift-microservices/ci/.github/workflows/service.yml@<commit>  # <release>
    with:
      linux_host_archs: '["aarch64"]'
      postgres_image: postgres:18-alpine
    secrets:
      PACKAGES_TOKEN: ${{ secrets.PACKAGES_TOKEN }}
```

```yaml
# .github/workflows/main.yml
name: Main

on:
  push:
    branches: [main]

permissions:
  contents: read

# One push at a time reaches staging, in order.
concurrency:
  group: ${{ github.workflow }}
  cancel-in-progress: false

jobs:
  service:
    name: Service
    permissions:
      contents: read
      packages: write
    uses: swift-microservices/ci/.github/workflows/service.yml@<commit>  # <release>
    with:
      linux_host_archs: '["aarch64"]'
      postgres_image: postgres:18-alpine
    secrets:
      PACKAGES_TOKEN: ${{ secrets.PACKAGES_TOKEN }}

  staging:
    name: Staging
    needs: [service]
    permissions:
      contents: read
      deployments: write
    uses: swift-microservices/ci/.github/workflows/deploy_dokploy.yml@<commit>  # <release>
    with:
      environment: staging
      image: ${{ needs.service.outputs.image }}
      application_ids: '["<migrate id>", "<serve id>", "<worker id>"]'
      run_to_completion_application_ids: '["<migrate id>"]'
    secrets:
      DOKPLOY_URL: ${{ secrets.DOKPLOY_URL }}
      DOKPLOY_TOKEN: ${{ secrets.DOKPLOY_TOKEN }}

  # Only where GitHub stores attestations: a public repository, or a private one on GitHub
  # Enterprise Cloud. `gh attestation verify oci://<image> --owner <owner>` checks them.
  attest:
    name: Attest
    needs: [service]
    permissions:
      contents: read
      packages: write
      id-token: write
      attestations: write
    uses: swift-microservices/ci/.github/workflows/attest_image.yml@<commit>  # <release>
    with:
      image: ${{ needs.service.outputs.image }}
```

```yaml
# .github/workflows/deploy.yml
name: Deploy
run-name: Deploy ${{ inputs.commit || 'what staging runs' }} to production

on:
  workflow_dispatch:
    inputs:
      commit:
        description: Commit to deploy, by default the one staging runs; an older one rolls back
        type: string
        required: false

permissions:
  contents: read

jobs:
  production:
    name: Production
    if: github.ref == 'refs/heads/main'
    permissions:
      contents: read
      deployments: write
    uses: swift-microservices/ci/.github/workflows/deploy_dokploy.yml@<commit>  # <release>
    with:
      environment: production
      promote_from: staging
      commit: ${{ inputs.commit }}
      application_ids: '["<migrate id>", "<serve id>", "<worker id>"]'
      run_to_completion_application_ids: '["<migrate id>"]'
    secrets:
      DOKPLOY_URL: ${{ secrets.DOKPLOY_URL }}
      DOKPLOY_TOKEN: ${{ secrets.DOKPLOY_TOKEN }}
```

```yaml
# .github/workflows/cleanup_images.yml
name: Clean up images

on:
  schedule:
    - cron: "0 3 * * 1"
  workflow_dispatch:

permissions:
  contents: read

jobs:
  cleanup:
    name: Clean up images
    permissions:
      packages: write
    uses: swift-microservices/ci/.github/workflows/cleanup_images.yml@<commit>  # <release>
```

Pin each call to a release's full commit, with the release in a comment; Dependabot moves the
pins. A job that sets `permissions` gets only those, so each lists all it needs.

## Libraries and services test differently

| | Library | Service |
| --- | --- | --- |
| Swift versions | Each supported release from the package's `swift-tools-version` up, `nightly-release` and `nightly-main` | The package's `swift-tools-version`, the toolchain its `Containerfile` builds with |
| Architectures | `x86_64` and `aarch64` | The ones its servers run, which it states in `linux_host_archs` |
| Other platforms | The Static Linux SDK; Wasm, Android and Windows when enabled | None |
| Flags | `-warnings-as-errors`, `--explicit-target-dependency-import-check error` and `-require-explicit-sendable`; nightlies drop `-warnings-as-errors` | `-warnings-as-errors` and `--explicit-target-dependency-import-check error` |

A library runs wherever its users build, on toolchains and machines it doesn't choose, so its CI
covers them: a new release's diagnostics, a nightly's changes, and the differences between
architectures, such as aarch64's weaker memory ordering, which surfaces races x86_64 hides, a C
target's `char`, unsigned on aarch64 Linux, and code behind `#if arch`. A service ships one binary
to servers it knows, so it tests
exactly what it ships: its toolchain, on its servers' architectures, which its image is built for
too. Another architecture or toolchain would cost runners and test nothing that runs. A library
that only a project's own services use may narrow its matrix to theirs.

## What the pipelines run

| Job | Library | Service |
| --- | --- | --- |
| Soundness | Pull requests | Pull requests |
| Tests | Every run | Every run |
| Platforms | Every run, when one is enabled | |
| Foundation linking | Every run | Every run |
| Protobuf | Pull requests, when `buf.yaml` is at the root | |
| OpenAPI breakage | | Pull requests, with `openapi_breakage_check_path` |
| Image | | Every run; pushed by digest on `main` |
| Publish | | `main`, once Tests, Foundation linking and Image passed |
| Passed | Every run | Every run |

- **Passed** fails when any other job failed, so a repository's ruleset requires `Library / Passed`
  or `Service / Passed`, whatever its matrix, plus a library's `PR label / Semver label / Semantic
  version label check`.
- **Soundness** is swiftlang's: formatting, license headers, documentation, API breakage,
  unacceptable language, YAML, shell and broken symlinks, on the package's `swift-tools-version`.
  A service checks no documentation or API breakage, since nothing builds against it.
- **Tests** run in each toolchain's Swift image, on a runner of each architecture, so nothing runs
  under emulation. The toolchains are swiftlang's `toolchain_matrix.yml`'s, so `current` and
  `nightly-release` follow the swiftlang release this repository pins, and versions below the
  package's `swift-tools-version` are left out.
- **Platforms** are swiftlang's `package_test.yml`, which can't read private dependencies.
- **Foundation linking** builds every product, library and executable, and fails when one links
  `libFoundation`, `libFoundationInternationalization` or `lib_FoundationICU`, so code that imports
  `FoundationEssentials` keeps its binaries small. A product that links Foundation through a
  dependency is listed in `foundation_linking_check_excluded_products` until it doesn't.
- **Protobuf** runs buf's lint and breaking checks against the pull request's base, since the Swift
  API breakage check can't see a renumbered field or a reused tag. `buf.yaml` lists the modules and
  rules.
- **OpenAPI breakage** runs oasdiff against the pull request's base and fails on a change it rates
  `ERR`, such as a removed operation or a parameter made required; a `WARN` shows as an
  annotation, and a `.oasdiff.yaml` at the root can ignore a break the service means to make. The
  document never leaves CI, and nothing is commented.
- **Image** builds the `Containerfile` once per architecture and checks it: it runs as an
  unprivileged user, and the executable its entrypoint starts finds every runtime library it
  links. A static executable links none, and an image without `ldd` or whose entrypoint is a script
  has its libraries left unchecked, with a warning. Each image's SPDX SBOM is kept with the run
  and scanned; a critical vulnerability with a fixed version fails a pull request, while `main`
  reports it, so a vulnerability disclosed after a pull request passed never blocks a deploy or a
  hotfix. The build passes none of the tests' flags, for the same reason.
- **Publish** tags the images pushed by digest once as `<image_repository>:<commit-sha>`, a single
  image for one architecture and an index for several, from which each server pulls its own. The
  image checked is the image published, and a commit's tag is never rewritten.

## Inputs

Lists are JSON lists, written `'["x86_64", "aarch64"]'`, and maps JSON objects, written
`'{"LOG_LEVEL": "debug"}'`. An input that exists in swiftlang's workflows keeps its name, such as
`linux_host_archs`, `linux_command` and `enable_windows`; a check's settings are named
`<check>_check_<setting>`, as in swiftlang's `soundness.yml`.

### `library.yml`

| Input | Default | Description |
| --- | --- | --- |
| `linux_swift_versions` | `""` | Swift versions to test on: releases such as `"6.3"`, or `current`, `current-1`, `current-2`, `nightly-release` and `nightly-main`. Empty is `current-2` through `nightly-main` |
| `linux_host_archs` | `'["x86_64", "aarch64"]'` | Architectures to test on |
| `linux_os` | `'["noble"]'` | Distributions to test on |
| `linux_setup_command` | `""` | Run before `linux_command` |
| `linux_command` | `swift test` | Builds and tests; a package without tests runs `swift build` |
| `linux_env_vars` | `'{}'` | Variables the tests read |
| `postgres_image` | `""` | Postgres started beside the tests, such as `postgres:18-alpine`; the tests read `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD` and `POSTGRES_DB` |
| `valkey_image` | `""` | Valkey started beside the tests, such as `valkey/valkey:9-alpine`; the tests read `VALKEY_HOST` and `VALKEY_PORT` |
| `enable_linux_static_sdk_build` | `true` | Build with the Static Linux SDK |
| `enable_wasm_sdk_build` | `false` | Build with the Swift SDK for Wasm |
| `enable_android_sdk_build` | `false` | Build with the Swift SDK for Android and test on its emulator |
| `enable_windows` | `false` | Test on Windows |
| `api_breakage_check_enabled` | `true` | Fail a pull request that breaks the public API; `false` before 1.0 |
| `docs_check_targets` | `'[]'` | Targets whose documentation must build without warnings; empty reads `.spi.yml`'s `documentation_targets` |
| `docs_check_container_image` | `""` | Image the documentation builds in; empty is the `swift-tools-version`'s |
| `format_check_enabled` | `true` | Check formatting against `.swift-format` |
| `license_header_check_enabled` | `true` | Check license headers against `.license_header_template` |
| `foundation_linking_check_enabled` | `true` | Run Foundation linking |
| `foundation_linking_check_excluded_products` | `'[]'` | Products that link Foundation through a dependency |

Secrets: `PACKAGES_TOKEN`.

### `service.yml`

| Input | Default | Description |
| --- | --- | --- |
| `linux_host_archs` | Required | Architectures the servers run: the tests run on each, and the image is built for each |
| `linux_setup_command` | `""` | Run before `linux_command` |
| `linux_command` | `swift test --disable-automatic-resolution` | Builds and tests at the committed `Package.resolved` |
| `linux_env_vars` | `'{}'` | Variables the tests read |
| `postgres_image` | `""` | As `library.yml`'s |
| `valkey_image` | `""` | As `library.yml`'s |
| `format_check_enabled` | `true` | Check formatting against `.swift-format` |
| `license_header_check_enabled` | `true` | Check license headers against `.license_header_template` |
| `foundation_linking_check_enabled` | `true` | Run Foundation linking |
| `foundation_linking_check_excluded_products` | `'[]'` | Products that link Foundation through a dependency, such as an executable whose generated OpenAPI code does |
| `openapi_breakage_check_path` | `""` | The OpenAPI document the service serves, such as `Sources/<Target>/openapi.yaml`; empty checks none |
| `image_repository` | `""` | Where the image is published; empty is `ghcr.io/<owner>/<repository>`, lowercased |
| `containerfile` | `Containerfile` | The Containerfile or Dockerfile |
| `containerfile_target` | `""` | The stage to build; empty builds the last |

Secrets: `PACKAGES_TOKEN`, and `REGISTRY_USERNAME` and `REGISTRY_PASSWORD` for a registry other
than GHCR. Output: `image`, the published `<image_repository>:<commit-sha>@sha256:<hex>`, empty
except on `main`.

### `deploy_dokploy.yml`

| Input | Default | Description |
| --- | --- | --- |
| `environment` | Required | The GitHub environment, such as `staging` or `production` |
| `environment_url` | `""` | Where the environment serves, shown on its deployments |
| `image` | `""` | The image to deploy by digest, such as `service.yml`'s output |
| `promote_from` | `""` | Instead of `image`: the environment whose image to deploy |
| `commit` | `""` | With `promote_from`, the commit to deploy; empty is the newest `promote_from` ran. An older one rolls back |
| `application_ids` | Required | The environment's Dokploy applications, in deploy order |
| `run_to_completion_application_ids` | `'[]'` | Those whose command exits, such as a migration |

Secrets: `DOKPLOY_URL` and `DOKPLOY_TOKEN`.

### The others

- `attest_image.yml` takes `image`, the published image by digest, and the registry secrets.
- `cleanup_images.yml` takes `package_name`, empty for the repository's name, lowercased, and
  `min_versions_to_keep`, 30 by default: the newest commits' images it keeps, each with its
  platform images and attestations. It deletes untagged uploads older than a day too.

## Deployments

`service.yml` ends at a published image; deploying it is a workflow of its own, so a pipeline
depends on no platform.

- **Environments.** A deployment runs in a GitHub environment, so the environment's protection
  rules apply, such as production's required reviewers and its deployment branches, and its secrets
  take precedence over the repository's, so staging and production can hold different keys.
- **Records.** Each run records a GitHub deployment of the commit to the environment, with the
  image it ran, in progress and then succeeded or failed. The repository's Environments page shows
  what each environment runs.
- **Promotion.** `promote_from: staging` deploys the image staging's newest successful deployment
  of the commit ran, so production runs only what staging ran, and fails for a commit staging never
  ran or is still deploying. Naming an older commit is the rollback; nothing is rebuilt, and the
  image must still be kept by cleanup. To put an older commit back on staging, re-run that commit's
  Staging job.
- **Order.** One deployment at a time per environment, never cancelled midway.

Another platform adds `deploy_<platform>.yml` that takes `environment`, `environment_url`, `image`,
`promote_from` and `commit` with these meanings, runs its job in the environment, wraps its own
deploy between `start-deployment.sh` and `finish-deployment.sh`, and adds the inputs and secrets the
platform needs. Since every platform records deployments the same way, one environment can promote
from another on a different platform.

## Requirements

- **Rulesets.** `main` changes only through pull requests that pass `Library / Passed` or
  `Service / Passed`, and a library's label check.
- **Registry.** GHCR needs nothing: `GITHUB_TOKEN` pushes, and the first push creates the package,
  linked to the repository by the `org.opencontainers.image.source` label, so it inherits the
  repository's access and its workflows hold the admin role cleanup deletes with. A package of that
  name that already exists, such as one pushed from a laptop, refuses `GITHUB_TOKEN` until its
  settings connect it to the repository with the admin role. Another registry takes its own
  `image_repository` and the `REGISTRY_USERNAME` and `REGISTRY_PASSWORD` secrets; its own
  retention rules replace `cleanup_images.yml`.
- **Secrets.** `PACKAGES_TOKEN`, only with private dependencies: a fine-grained token owned by the
  organization, limited to the private package repositories, with Contents read-only, stored as an
  Actions secret and as a Dependabot secret. `DOKPLOY_URL` and `DOKPLOY_TOKEN`, for a service on
  Dokploy, as repository or environment secrets.
- **Containerfile.** It builds on the package's `swift-tools-version`, runs as an unprivileged
  `USER`, and starts the service's executable as its entrypoint. With private dependencies, it
  resolves with the secret mounted, so the token never enters a layer, and a local build passes
  `--secret id=netrc,src=$HOME/.netrc`:

  ```dockerfile
  RUN --mount=type=secret,id=netrc,target=/root/.netrc swift package --disable-automatic-resolution resolve
  ```

- **Environments.** `staging` and `production` exist in the repository's settings, with
  production's required reviewers and its `main` deployment branch, where the plan has them.
- **Dokploy.** Each application uses the Docker provider with the registry's credentials and
  auto-deploy off, so only these workflows change what runs. The application that applies
  migrations comes first in `application_ids`. Each application waits for the one before it: for a
  container of the new image to run, and to pass its health check when it has one, or, for one
  `run_to_completion_application_ids` lists, for its new container to exit 0. Any other exit fails
  the deployment, as does none within 10 minutes. Such an application needs a restart policy whose
  condition is `none`, since Swarm restarts an exited container under `any`, and an update config
  whose failure action is `continue`, since Swarm rolls back an update whose task exits within its
  monitor period. The key must read the applications' containers. `deploy_dokploy.yml` checks all
  of this before it changes anything. Docker's `ps` and `inspect` see only the containers on the
  application's server, so a Swarm that spreads an application across nodes runs one on the server
  Dokploy deploys from.
- **Migrations** are expand/contract: the previous image must run on the current schema, because a
  rollback redeploys it.

## Versioning

The workflow file names, their inputs, secrets and outputs, and the `Passed` job are this
repository's API: renaming or removing one is a major release, whose notes say how to move.
Changing what a pipeline checks or builds with, such as a toolchain or a flag, is a minor release,
which each repository adopts through its own Dependabot pull request, whose CI shows what it
breaks.

## License

MIT. See [LICENSE](LICENSE).
