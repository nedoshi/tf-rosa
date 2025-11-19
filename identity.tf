locals {
  # admin idp
  admin_username = "admin"
  admin_group    = "cluster-admins"

  # developer idp
  developer_username = "developer"
}

resource "rhcs_identity_provider" "admin" {
  count = var.admin_password != null && var.admin_password != "" ? 1 : 0

  cluster = local.cluster_id
  name    = local.admin_username
  htpasswd = {
    users = [{
      username = local.admin_username
      password = var.admin_password
    }]
  }
}

resource "rhcs_identity_provider" "developer" {
  count = var.developer_password != null && var.developer_password != "" ? 1 : 0

  cluster = local.cluster_id
  name    = local.developer_username
  htpasswd = {
    users = [{
      username = local.developer_username
      password = var.developer_password
    }]
  }
}

# NOTE: The rhcs_group_membership resource is deprecated.
# Group membership should be handled through OpenShift RBAC after cluster creation.
# To add the admin user to the cluster-admins group, run:
#   oc adm groups add-users cluster-admins admin
# Or use the OpenShift web console to add the user to the group.
