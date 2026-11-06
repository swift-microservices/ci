# ci

Reusable GitHub Actions workflows for Swift packages and services: testing with private
dependencies or a Postgres, checking that libraries don't link Foundation, building and publishing
one image per commit, and deploying it to Dokploy, staging first and production by hand.

Everything [swiftlang/github-workflows](https://github.com/swiftlang/github-workflows) already does
is called from there directly: `soundness.yml` for every repository, and `swift_package_test.yml`
for every package that needs neither private dependencies nor a Postgres. This repository adds only
what it lacks.

| Workflow | Does |
| --- | --- |
| `tests.yml` | swiftlang's `swift_package_test.yml` Linux job, with the same inputs, for a package that needs private dependencies, which SwiftPM fetches with `PACKAGES_TOKEN`, or a Postgres beside its tests, started from `postgres_image` |
| `foundation-linking.yml` | Builds an empty executable that links every library product, and each executable product `executable_products` names, and fails when one links Foundation's full library or ICU; `excluded_products` names the library products allowed to |
| `build-image.yml` | Builds the `Containerfile` for linux/arm64 and checks that it runs as an unprivileged user and links every runtime library; with `publish: true` on `main`, pushes it once as `:<commit-sha>` |
| `deploy.yml` | Resolves a commit to `:<commit-sha>@sha256:…`, refuses production for a commit staging never ran, then deploys it to each Dokploy application in order and waits for each to finish |
| `cleanup-images.yml` | Keeps the newest versions of a container package (30 by default) |

## Delivery

```
pull request ──► soundness + tests + build image (validate, no push); a new push cancels the run
push to main ──► tests ──► build image (push :<commit-sha>) ──► deploy staging
Deploy production (manual) ──► the latest main commit, or a chosen one, if staging ran it
weekly ──► cleanup-images
```

`main` is the only long-lived branch, and it changes only through pull requests that passed their
checks, so Main skips soundness and reruns the tests on the merged commit. Production runs only a
commit whose push to `main` deployed it to staging. Rolling back means deploying an older commit;
nothing is rebuilt.

The tests' strict flags gate the pull request; the image build passes none of them, so a warning a
newer toolchain adds never blocks a release or a hotfix. `-require-explicit-sendable` checks `public`
declarations, so libraries pass it and services, built on `package` access, don't.

## Callers

Pin each workflow to a release's commit, with the release in a comment.

```yaml
# .github/workflows/main.yml
name: Main

permissions:
  contents: read

on:
  push:
    branches: [main]

jobs:
  tests:
    name: Tests
    # Without private dependencies or a Postgres, call swiftlang/github-workflows'
    # swift_package_test.yml with the same inputs instead, and drop `secrets`.
    uses: swift-microservices/ci/.github/workflows/tests.yml@<commit>  # <release>
    with:
      linux_build_command: swift test --disable-automatic-resolution
      postgres_image: postgres:18-alpine
      swift_flags: -Xswiftc -warnings-as-errors --explicit-target-dependency-import-check error
    secrets:
      PACKAGES_TOKEN: ${{ secrets.PACKAGES_TOKEN }}

  publish:
    name: Publish image
    needs: [tests]
    permissions:
      contents: read
      packages: write
    uses: swift-microservices/ci/.github/workflows/build-image.yml@<commit>  # <release>
    with:
      service_product: orders
      image_repository: ghcr.io/<owner>/<repository>
      publish: true
    secrets:
      PACKAGES_TOKEN: ${{ secrets.PACKAGES_TOKEN }}

  staging:
    name: Staging
    needs: [publish]
    permissions:
      contents: read
      actions: read
      packages: read
    uses: swift-microservices/ci/.github/workflows/deploy.yml@<commit>  # <release>
    with:
      environment: staging
      image_repository: ghcr.io/<owner>/<repository>
      application_ids: '["<staging service application id>", "<staging worker application id>"]'
    secrets:
      DOKPLOY_URL: ${{ secrets.DOKPLOY_URL }}
      DOKPLOY_TOKEN: ${{ secrets.DOKPLOY_TOKEN }}
```

The pull request workflow runs swiftlang's `soundness.yml` (with `api_breakage_check_enabled` and
`docs_check_enabled` off), the same `tests` job, and `build-image.yml` without `publish`, in a
`concurrency` group of the pull request's number with `cancel-in-progress: true`.

```yaml
# .github/workflows/deploy.yml
name: Deploy production
run-name: Deploy ${{ inputs.commit || 'latest main' }} to production

permissions:
  contents: read

on:
  workflow_dispatch:
    inputs:
      commit:
        description: Commit to deploy (default the latest on main); an older one rolls back
        type: string
        required: false

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
      application_ids: '["<production service application id>", "<production worker application id>"]'
    secrets:
      DOKPLOY_URL: ${{ secrets.DOKPLOY_URL }}
      DOKPLOY_TOKEN: ${{ secrets.DOKPLOY_TOKEN }}
```

To put an older commit back on staging, re-run the Staging job of that commit's Main run.

```yaml
# .github/workflows/cleanup-images.yml
name: Clean up container images

permissions:
  contents: read

on:
  schedule:
    - cron: "0 3 * * 1"
  workflow_dispatch:

jobs:
  cleanup:
    name: Clean up
    permissions:
      packages: write
    uses: swift-microservices/ci/.github/workflows/cleanup-images.yml@<commit>  # <release>
    with:
      package_name: <repository>
```

A library calls `foundation-linking.yml` from its pull request and `main` workflows, beside its
tests:

```yaml
  foundation-linking:
    name: Foundation linking
    uses: swift-microservices/ci/.github/workflows/foundation-linking.yml@<commit>  # <release>
    with:
      excluded_products: <Org>Testing
```

A service adds the same job, with `executable_products: <product>` and `PACKAGES_TOKEN`, once every
package it depends on is Foundation-free.

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
