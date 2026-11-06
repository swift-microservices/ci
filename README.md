# ci

The GitHub Actions CI and delivery of every Swift library and service built the
[swift-microservices-architect](https://github.com/swift-microservices/swift-microservices-architect-skill)
way. A repository calls one pipeline, for a library or a service; a change made here reaches every repository
through the pin Dependabot moves.

## Pipelines

| Workflow | Called by | Runs |
| --- | --- | --- |
| `library.yml` | A library's `ci.yml` | Pull request: Soundness, Tests, Foundation linking. Push or schedule: Tests, Foundation linking |
| `service.yml` | A service's `ci.yml` | Pull request: Soundness, Tests, Foundation linking, Build image. Push to `main`: Tests and Foundation linking, then Publish image as `:<commit-sha>`, then Staging |
| `pull_request_label.yml` | A library's `pull_request_label.yml` | Exactly one semver label on the pull request |
| `release.yml` | A library's `release.yml` | The next release from the merged pull requests' labels |
| `deploy.yml` | A service's `deploy.yml`, for production | A commit's image on Dokploy, refused for a commit staging never ran |
| `cleanup-images.yml` | A service's `cleanup-images.yml` | Keeps the newest versions of a container package (30 by default) |

The pipelines choose their jobs by the event that started the run and call these building blocks,
also callable on their own:

| Workflow | Does |
| --- | --- |
| `tests.yml` | swiftlang's `swift_package_test.yml` Linux job, with the same inputs, for a package that needs private dependencies, which SwiftPM fetches with `PACKAGES_TOKEN`, or a Postgres beside its tests, started from `postgres_image` |
| `foundation-linking.yml` | Builds an empty executable that links every library product, and each executable product `executable_products` names, and fails when one links Foundation's full library or ICU; `excluded_products` names the library products allowed to |
| `build-image.yml` | Builds the `Containerfile` for linux/arm64 and checks that it runs as an unprivileged user and links every runtime library; with `publish: true` on `main`, pushes it once as `:<commit-sha>` |

Everything [swiftlang/github-workflows](https://github.com/swiftlang/github-workflows) does is called
from there: `soundness.yml`, and `swift_package_test.yml` for a library that needs neither private
dependencies nor a Postgres.

## What the pipelines hold every repository to

- `main` changes only through pull requests that passed their checks, so a push to `main` skips
  Soundness and reruns the tests on the merged commit.
- A library tests in release, by default on Swift 6.3, Ubuntu noble and linux/arm64, the platform
  services run on; one that others build with passes more `linux_swift_versions`, `linux_host_archs`
  and `enable_linux_static_sdk_build: true`. A service tests its committed `Package.resolved` on
  `swift_version` and linux/arm64.
- Foundation linking always runs. `excluded_products` names the products, a library's or a service's
  executable, that still link Foundation through a dependency; removing one from the list checks it
  again.
- The tests pass `-warnings-as-errors` and `--explicit-target-dependency-import-check error`, and a
  library also `-require-explicit-sendable`, which checks `public` declarations. Nightlies drop
  `-warnings-as-errors`. The image build passes none of them, so a warning a newer toolchain adds
  never blocks a deploy or a hotfix.
- Production runs only a commit whose push to `main` deployed it to staging. Rolling back means
  deploying an older commit; nothing is rebuilt.

## Callers

Pin each call to a release's commit, with the release in a comment. A library:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
  push:
    branches: [main]
  schedule:
    - cron: "0 6 * * 1"

permissions:
  contents: read

concurrency:
  group: ci-${{ github.event.pull_request.number || github.sha }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  ci:
    name: CI
    uses: swift-microservices/ci/.github/workflows/library.yml@<commit>  # <release>
    with:
      excluded_products: <Org>Persistence
    secrets:
      PACKAGES_TOKEN: ${{ secrets.PACKAGES_TOKEN }}
```

```yaml
# .github/workflows/pull_request_label.yml
name: PR label

on:
  pull_request:
    types: [labeled, unlabeled, opened, reopened, synchronize]

permissions:
  contents: read
  pull-requests: read

jobs:
  label:
    name: PR label
    uses: swift-microservices/ci/.github/workflows/pull_request_label.yml@<commit>  # <release>
```

```yaml
# .github/workflows/release.yml
name: Release

on:
  workflow_dispatch:

permissions:
  contents: write
  pull-requests: read

jobs:
  release:
    name: Release
    uses: swift-microservices/ci/.github/workflows/release.yml@<commit>  # <release>
```

A service:

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ci-${{ github.event.pull_request.number || github.sha }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  ci:
    name: CI
    permissions:
      contents: read
      packages: write
      actions: read
    uses: swift-microservices/ci/.github/workflows/service.yml@<commit>  # <release>
    with:
      service_product: orders
      image_repository: ghcr.io/<owner>/<repository>
      staging_application_ids: '["<staging serve id>", "<staging worker id>"]'
      postgres_image: postgres:18-alpine
    secrets:
      PACKAGES_TOKEN: ${{ secrets.PACKAGES_TOKEN }}
      DOKPLOY_URL: ${{ secrets.DOKPLOY_URL }}
      DOKPLOY_TOKEN: ${{ secrets.DOKPLOY_TOKEN }}
```

```yaml
# .github/workflows/deploy.yml
name: Deploy to production
run-name: Deploy ${{ inputs.commit || 'latest main' }} to production

on:
  workflow_dispatch:
    inputs:
      commit:
        description: Commit to deploy (default the latest on main); an older one rolls back
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
      actions: read
      packages: read
    uses: swift-microservices/ci/.github/workflows/deploy.yml@<commit>  # <release>
    with:
      environment: production
      commit: ${{ inputs.commit }}
      image_repository: ghcr.io/<owner>/<repository>
      application_ids: '["<production serve id>", "<production worker id>"]'
    secrets:
      DOKPLOY_URL: ${{ secrets.DOKPLOY_URL }}
      DOKPLOY_TOKEN: ${{ secrets.DOKPLOY_TOKEN }}
```

```yaml
# .github/workflows/cleanup-images.yml
name: Clean up container images

on:
  schedule:
    - cron: "0 3 * * 1"
  workflow_dispatch:

permissions:
  contents: read

jobs:
  cleanup:
    name: Clean up
    permissions:
      packages: write
    uses: swift-microservices/ci/.github/workflows/cleanup-images.yml@<commit>  # <release>
    with:
      package_name: <repository>
```

A library others build with tests more platforms:

```yaml
    with:
      linux_swift_versions: '["6.2", "6.3", "6.4", "nightly-main", "nightly-6.4.x"]'
      linux_host_archs: '["x86_64", "aarch64"]'
      enable_linux_static_sdk_build: true
```

To put an older commit back on staging, re-run the Staging job of that commit's CI run.

## Requirements

- **Secrets**, as repository secrets of each service:
  - `DOKPLOY_URL` and `DOKPLOY_TOKEN`, a Dokploy API key that can read, update, and deploy the
    applications.
  - `PACKAGES_TOKEN`, only with private dependencies: a fine-grained token whose resource owner is
    the organization, limited to the private package repositories, with Contents read-only.
- **Containerfile**, only with private dependencies: resolve with the secret mounted, so the token
  never enters a layer:

  ```dockerfile
  RUN --mount=type=secret,id=netrc,target=/root/.netrc swift package --disable-automatic-resolution resolve
  ```

  A local build passes `--secret id=netrc,src=$HOME/.netrc`.
- **Dokploy**: each application uses the Docker provider with the registry's credentials and
  auto-deploy off, so only these workflows change what runs. List the application that runs
  migrations first in `application_ids`.
- **Migrations** are expand/contract: the previous image must run on the current schema, because a
  rollback redeploys it.

## License

MIT. See [LICENSE](LICENSE).
