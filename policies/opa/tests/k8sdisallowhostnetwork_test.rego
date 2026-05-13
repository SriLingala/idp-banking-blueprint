package k8sdisallowhostnetwork

test_denies_host_network {
  count(violation) == 1 with input as {
    "review": {
      "object": {
        "spec": {
          "hostNetwork": true
        }
      }
    }
  }
}

test_allows_normal_pod {
  count(violation) == 0 with input as {
    "review": {
      "object": {
        "spec": {
          "hostNetwork": false
        }
      }
    }
  }
}

