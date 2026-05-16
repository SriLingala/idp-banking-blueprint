package k8sexternalsecretscope

# ---- Inputs that should DENY ------------------------------------------------

test_denies_when_namespace_has_no_prefix_annotation {
  count(violation) == 1 with input as {
    "review": {
      "kind": {"group": "external-secrets.io", "kind": "ExternalSecret"},
      "namespace": {
        "metadata": {
          "annotations": {}
        }
      },
      "object": {
        "metadata": {"namespace": "payments", "name": "card-secrets"},
        "spec": {
          "data": [
            {"remoteRef": {"key": "payments/card/processor-api-key"}}
          ]
        }
      }
    }
  }
}

test_denies_when_remote_key_outside_prefix {
  count(violation) == 1 with input as {
    "review": {
      "kind": {"group": "external-secrets.io", "kind": "ExternalSecret"},
      "namespace": {
        "metadata": {
          "annotations": {"platform.idp/secret-prefix": "payments/"}
        }
      },
      "object": {
        "metadata": {"namespace": "payments", "name": "fraud-secrets"},
        "spec": {
          "data": [
            {"remoteRef": {"key": "fraud/scoring-model-token"}}
          ]
        }
      }
    }
  }
}

test_denies_dataFrom_path_outside_prefix {
  count(violation) == 1 with input as {
    "review": {
      "kind": {"group": "external-secrets.io", "kind": "ExternalSecret"},
      "namespace": {
        "metadata": {
          "annotations": {"platform.idp/secret-prefix": "payments/"}
        }
      },
      "object": {
        "metadata": {"namespace": "payments", "name": "mixed-secrets"},
        "spec": {
          "dataFrom": [
            {"extract": {"key": "kyc/aml-keys"}}
          ]
        }
      }
    }
  }
}

# ---- Inputs that should ALLOW ----------------------------------------------

test_allows_when_remote_key_starts_with_prefix {
  count(violation) == 0 with input as {
    "review": {
      "kind": {"group": "external-secrets.io", "kind": "ExternalSecret"},
      "namespace": {
        "metadata": {
          "annotations": {"platform.idp/secret-prefix": "payments/"}
        }
      },
      "object": {
        "metadata": {"namespace": "payments", "name": "card-secrets"},
        "spec": {
          "data": [
            {"remoteRef": {"key": "payments/card/processor-api-key"}},
            {"remoteRef": {"key": "payments/card/webhook-secret"}}
          ]
        }
      }
    }
  }
}

test_allows_dataFrom_within_prefix {
  count(violation) == 0 with input as {
    "review": {
      "kind": {"group": "external-secrets.io", "kind": "ExternalSecret"},
      "namespace": {
        "metadata": {
          "annotations": {"platform.idp/secret-prefix": "payments/"}
        }
      },
      "object": {
        "metadata": {"namespace": "payments", "name": "bulk-secrets"},
        "spec": {
          "dataFrom": [
            {"extract": {"key": "payments/3rd-party/stripe-bundle"}}
          ]
        }
      }
    }
  }
}

# Non-ESO admission reviews should be ignored — the constraint only
# applies to ExternalSecret kinds. (Belt-and-braces; Gatekeeper's match
# block also enforces this, but the rego should be safe to call against
# anything.)
test_ignores_unrelated_kinds {
  count(violation) == 0 with input as {
    "review": {
      "kind": {"group": "", "kind": "ConfigMap"},
      "namespace": {"metadata": {"annotations": {}}},
      "object": {
        "metadata": {"namespace": "payments", "name": "app-config"},
        "data": {"FOO": "bar"}
      }
    }
  }
}
