# ci

Reusable GitHub Actions workflows for Swift services: testing with private dependencies, building
and publishing one image per commit, and deploying it to Dokploy, staging first and production by
hand.

Everything [swiftlang/github-workflows](https://github.com/swiftlang/github-workflows) already does
is called from there directly: `soundness.yml` for every repository, and `swift_package_test.yml`
for every package without private dependencies. This repository adds only what it lacks.

| Workflow | Does |
| --- | --- |
| `tests.yml` | swiftlang's `swift_package_test.yml` Linux job, with the same inputs, for a package whose dependencies include private repositories: SwiftPM fetches them with `PACKAGES_TOKEN` |
| `build-image.yml` | Builds the `Containerfile` for linux/arm64 and checks that it runs as an unprivileged user and links every runtime library; with `publish: true` on `main`, pushes it once as `:<commit-sha>` |
| `deploy.yml` | Resolves a commit to `:<commit-sha>@sha256:…`, refuses production for a commit staging never ran, then deploys it to each Dokploy application in order and waits for each to finish |
| `cleanup-images.yml` | Keeps the newest versions of a container package (30 by default) |

## Delivery

```
pull request ──► soundness + tests + build image (validate, no push)
push to main ──► soundness + tests ──► build image (push :<commit-sha>) ──► deploy staging
Deploy production (manual) ──► the latest main commit, or a chosen one, if staging ran it
weekly ──► cleanup-images
```

`main` is the only long-lived branch. Production runs only a commit whose push to `main` deployed
it to staging. Rolling back means deploying an older commit; nothing is rebuilt.

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
  soundness:
    name: Soundness
    uses: swiftlang/github-workflows/.github/workflows/soundness.yml@<commit>  # <release>
    with:
      api_breakage_check_enabled: false
      docs_check_enabled: false

  tests:
    name: Tests
    # Without private dependencies, call swiftlang/github-workflows' swift_package_test.yml
    # with the same inputs instead, and drop `secrets`.
    uses: swift-microservices/ci/.github/workflows/tests.yml@<commit>  # <release>
    with:
      linux_build_command: swift test --disable-automatic-resolution
      swift_flags: >-
        -Xswiftc -warnings-as-errors
        --explicit-target-dependency-import-check error
        -Xswiftc -require-explicit-sendable
    secrets:
      PACKAGES_TOKEN: ${{ secrets.PACKAGES_TOKEN }}

  publish:
    name: Publish image
    needs: [soundness, tests]
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

The pull request workflow runs the same `soundness` and `tests` jobs and `build-image.yml` without
`publish`.

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
