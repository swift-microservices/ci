# ci

The GitHub Actions CI and delivery of every Swift library and service built the
[swift-microservices-architect](https://github.com/swift-microservices/swift-microservices-architect-skill)
way. A repository's CI workflows call these workflows and nothing else; they route to
[swiftlang/github-workflows](https://github.com/swiftlang/github-workflows) and Apple's workflows,
so no repository pins those. A change made here reaches every repository through the pin Dependabot
moves.

## Workflows

| Workflow | A repository calls it from | Runs |
| --- | --- | --- |
| `library.yml` | `ci.yml` | Pull request: Soundness, Tests, Foundation linking. Push or schedule: Tests, Foundation linking |
| `service.yml` | `ci.yml` | Pull request: Soundness, Tests, Foundation linking, Build image. Push to `main`: Tests and Foundation linking, then Publish image as `:<commit-sha>` |
| `deploy_dokploy.yml` | `ci.yml` (staging) and `deploy.yml` (production) | A commit's image on Dokploy; production only for a commit staging ran |
| `cleanup_images.yml` | `cleanup_images.yml` | Keeps the newest versions of a container package (30 by default) |
| `pull_request_label.yml` | `pull_request_label.yml` | Exactly one semver label on a library's pull request |
| `release.yml` | `release.yml` | A library's next release, from the merged pull requests' labels |

`library.yml` and `service.yml` are the CI pipelines. They call the building blocks below, which a
repository with an unusual need can call too:

| Workflow | Does |
| --- | --- |
| `tests.yml` | swiftlang's `swift_package_test.yml` Linux job, with the same inputs, for a package that needs private dependencies or a Postgres, which swiftlang's workflow can't give |
| `foundation_linking.yml` | Builds an empty executable that links every library product, and each executable product `executable_products` names, and fails when one links Foundation's full library or ICU; `excluded_products` names the products it skips |
| `build_image.yml` | Builds the `Containerfile` for linux/arm64 and checks it runs as an unprivileged user and links every runtime library; with `publish: true` on `main`, pushes it once as `:<commit-sha>` |

### Deployment adapters

`service.yml` ends at a published image; deploying it is a separate workflow the service's CI
workflow calls, so the pipeline doesn't depend on a platform. `deploy_dokploy.yml` is the one
adapter; another platform adds `deploy_<platform>.yml` with the same inputs where they apply
(`environment`, `commit`, `image_repository`) and the same job name,
`Deploy <environment>`, which the production gate looks for.

## What the pipelines hold every repository to

- `main` changes only through pull requests that passed their checks, so a push to `main` skips
  Soundness and reruns the tests on the merged commit.
- The toolchain is the package's `swift-tools-version`: a pipeline reads it, so tests, Foundation
  linking and the Containerfile's `swift:<tools version>-noble` can't drift apart. A library others
  build with widens `linux_swift_versions`, `linux_host_archs` and `enable_linux_static_sdk_build`.
- Passing `PACKAGES_TOKEN` is what marks private dependencies; there's no other input for them.
- The tests pass `-warnings-as-errors` and `--explicit-target-dependency-import-check error`, and a
  library also `-require-explicit-sendable`, which checks `public` declarations. Nightlies drop
  `-warnings-as-errors`. The image build passes none of them, so a warning a newer toolchain adds
  never blocks a deploy or a hotfix.
- Foundation linking always runs. `foundation_linking_check_excluded_products` names the products
  that still link Foundation through a dependency; removing one checks it again.
- Production runs only a commit whose push to `main` deployed it to staging. Rolling back means
  deploying an older commit whose image cleanup kept; nothing is rebuilt.

## CI workflows

Pin each call to a release's commit, with the release in a comment. A job that sets `permissions`
gets only those, so each lists all it needs. A library:

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
      foundation_linking_check_excluded_products: <Org>Persistence
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

A library others build with tests more platforms:

```yaml
    with:
      linux_swift_versions: '["<tools version>", …, "nightly-main", "nightly-<next>.x"]'
      linux_host_archs: '["x86_64", "aarch64"]'
      enable_linux_static_sdk_build: true
```

A service; its staging job deploys each push to `main`:

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
    uses: swift-microservices/ci/.github/workflows/service.yml@<commit>  # <release>
    with:
      executable_product: orders
      image_repository: ghcr.io/<owner>/<repository>
      postgres_image: postgres:<major>-alpine
    secrets:
      PACKAGES_TOKEN: ${{ secrets.PACKAGES_TOKEN }}

  staging:
    name: Staging
    needs: [ci]
    if: github.event_name == 'push'
    permissions:
      contents: read
      actions: read
      packages: read
    uses: swift-microservices/ci/.github/workflows/deploy_dokploy.yml@<commit>  # <release>
    with:
      environment: staging
      image_repository: ghcr.io/<owner>/<repository>
      application_ids: '["<staging serve id>", "<staging worker id>"]'
    secrets:
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
    uses: swift-microservices/ci/.github/workflows/deploy_dokploy.yml@<commit>  # <release>
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
    with:
      package_name: <repository>
```

To put an older commit back on staging, re-run the Staging job of that commit's CI run.

## Requirements

- **Secrets**, as repository secrets of each service:
  - `PACKAGES_TOKEN`, only with private dependencies: a fine-grained token whose resource owner is
    the organization, limited to the private package repositories, with Contents read-only. It's a
    Dependabot secret too, since a Dependabot pull request reads only those.
  - `DOKPLOY_URL` and `DOKPLOY_TOKEN`, a Dokploy API key that can read, update, and deploy the
    applications.
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
