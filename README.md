# Weave migrated APIs

The services workspace: `services/<api>/`, `framework/integration-commons/`,
Helm values under `deploy/`, flows under `flows/`. `main` is what is deployed; every deploy is
a commit and a tag `<api>/v<N>`. Changes come as pull requests from `change/<api>/<id>`.
Settings values are never stored here: `deploy/settings-templates/` has the key names only.
