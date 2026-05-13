package k8srestrictedregistries

test_denies_unapproved_registry {
  count(violation) == 1 with input as {
    "parameters": {
      "approvedRegistries": ["europe-west2-docker.pkg.dev/"]
    },
    "review": {
      "object": {
        "spec": {
          "containers": [{
            "name": "app",
            "image": "docker.io/library/nginx:latest"
          }]
        }
      }
    }
  }
}

test_allows_approved_registry {
  count(violation) == 0 with input as {
    "parameters": {
      "approvedRegistries": ["europe-west2-docker.pkg.dev/"]
    },
    "review": {
      "object": {
        "spec": {
          "containers": [{
            "name": "app",
            "image": "europe-west2-docker.pkg.dev/bank/app:1.0"
          }]
        }
      }
    }
  }
}

