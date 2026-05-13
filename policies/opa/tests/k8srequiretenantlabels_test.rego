package k8srequiretenantlabels

test_denies_missing_tenant_label {
  count(violation) == 1 with input as {
    "parameters": {
      "requiredLabels": ["platform.idp/tenant", "platform.idp/tier"]
    },
    "review": {
      "object": {
        "metadata": {
          "name": "payments",
          "labels": {
            "platform.idp/tier": "silver"
          }
        }
      }
    }
  }
}

test_allows_required_labels {
  count(violation) == 0 with input as {
    "parameters": {
      "requiredLabels": ["platform.idp/tenant", "platform.idp/tier"]
    },
    "review": {
      "object": {
        "metadata": {
          "name": "payments",
          "labels": {
            "platform.idp/tenant": "payments",
            "platform.idp/tier": "silver"
          }
        }
      }
    }
  }
}

