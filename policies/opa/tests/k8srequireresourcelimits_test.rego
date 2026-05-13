package k8srequireresourcelimits

test_denies_missing_cpu_and_memory_limits {
  count(violation) == 2 with input as {
    "parameters": {
      "exemptImages": []
    },
    "review": {
      "object": {
        "spec": {
          "containers": [{
            "name": "app",
            "image": "europe-west2-docker.pkg.dev/bank/app:1.0",
            "resources": {
              "limits": {}
            }
          }]
        }
      }
    }
  }
}

test_allows_limited_container {
  count(violation) == 0 with input as {
    "parameters": {
      "exemptImages": []
    },
    "review": {
      "object": {
        "spec": {
          "containers": [{
            "name": "app",
            "image": "europe-west2-docker.pkg.dev/bank/app:1.0",
            "resources": {
              "limits": {
                "cpu": "500m",
                "memory": "256Mi"
              }
            }
          }]
        }
      }
    }
  }
}

test_skips_exempt_image {
  count(violation) == 0 with input as {
    "parameters": {
      "exemptImages": ["registry.k8s.io/"]
    },
    "review": {
      "object": {
        "spec": {
          "containers": [{
            "name": "system",
            "image": "registry.k8s.io/pause:3.9",
            "resources": {}
          }]
        }
      }
    }
  }
}

