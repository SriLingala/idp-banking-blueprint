# Sentinel policy set definition. Drop this directory into a Terraform
# Cloud / Enterprise policy set bound to the workspaces that manage the
# platform.
#
# Enforcement levels:
#   - hard-mandatory : block apply; no override
#   - soft-mandatory : block apply; can be overridden by an org admin (audit-trailed)
#   - advisory       : print a warning, do not block

policy "enforce-region" {
  source            = "./enforce-region.sentinel"
  enforcement_level = "hard-mandatory"
}

policy "enforce-cmek" {
  source            = "./enforce-cmek.sentinel"
  enforcement_level = "hard-mandatory"
}

policy "enforce-private-cluster" {
  source            = "./enforce-private-cluster.sentinel"
  enforcement_level = "hard-mandatory"
}

policy "enforce-master-authorized-networks" {
  source            = "./enforce-master-authorized-networks.sentinel"
  enforcement_level = "hard-mandatory"
}

policy "enforce-labels" {
  source            = "./enforce-labels.sentinel"
  enforcement_level = "soft-mandatory"
}
