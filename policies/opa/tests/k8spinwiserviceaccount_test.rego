package k8spinwiserviceaccount

test_denies_gsa_not_allowed_for_namespace {
  count(violation) == 1 with input as {
    "review": {
      "kind": {
        "kind": "ServiceAccount"
      },
      "namespace": {
        "metadata": {
          "annotations": {
            "platform.idp/allowed-gsa": "tenant-payments-runtime@bank.iam.gserviceaccount.com"
          }
        }
      },
      "object": {
        "metadata": {
          "namespace": "payments",
          "name": "tenant-runtime",
          "annotations": {
            "iam.gke.io/gcp-service-account": "tenant-fraud-runtime@bank.iam.gserviceaccount.com"
          }
        }
      }
    }
  }
}

test_allows_gsa_in_namespace_allowlist {
  count(violation) == 0 with input as {
    "review": {
      "kind": {
        "kind": "ServiceAccount"
      },
      "namespace": {
        "metadata": {
          "annotations": {
            "platform.idp/allowed-gsa": "tenant-payments-runtime@bank.iam.gserviceaccount.com, tenant-fraud-runtime@bank.iam.gserviceaccount.com"
          }
        }
      },
      "object": {
        "metadata": {
          "namespace": "payments",
          "name": "tenant-runtime",
          "annotations": {
            "iam.gke.io/gcp-service-account": "tenant-fraud-runtime@bank.iam.gserviceaccount.com"
          }
        }
      }
    }
  }
}

