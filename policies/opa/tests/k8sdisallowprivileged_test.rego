package k8sdisallowprivileged

test_denies_privileged_container {
  count(violation) == 1 with input as {
    "review": {
      "object": {
        "spec": {
          "containers": [{
            "name": "app",
            "securityContext": {
              "privileged": true
            }
          }]
        }
      }
    }
  }
}

test_denies_privileged_init_container {
  count(violation) == 1 with input as {
    "review": {
      "object": {
        "spec": {
          "containers": [],
          "initContainers": [{
            "name": "init",
            "securityContext": {
              "privileged": true
            }
          }]
        }
      }
    }
  }
}

test_allows_unprivileged_container {
  count(violation) == 0 with input as {
    "review": {
      "object": {
        "spec": {
          "containers": [{
            "name": "app",
            "securityContext": {
              "privileged": false
            }
          }]
        }
      }
    }
  }
}

