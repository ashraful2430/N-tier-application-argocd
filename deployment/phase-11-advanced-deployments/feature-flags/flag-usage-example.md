# Feature Flag Usage

Mount `launchboard-feature-flags` as environment variables in the backend deployment. Change values with `kubectl -n devops-launchboard edit configmap launchboard-feature-flags`, then restart the deployment.
