variable "subscription_id" {
  default = "ec0ba952-4ae9-4f69-b61c-4b96ff470038"
}

#############
# Providers #
#############

provider "azurerm" {
  version = ">=2.0.0"
  subscription_id = var.subscription_id
  features {}
}

provider "helm" {
alias = "aks"
kubernetes {
  host = module.kubernetes.host
    client_certificate = base64decode(module.kubernetes.client_certificate)
    client_key = base64decode(module.kubernetes.client_key)
    cluster_ca_certificate = base64decode(module.kubernetes.cluster_ca_certificate)
    config_path = "kube_config"
  }
}

#####################
# Pre-Build Modules #
#####################

module "subscription" {
  source = "github.com/Azure-Terraform/terraform-azurerm-subscription-data.git?ref=v1.0.0"
  subscription_id = var.subscription_id
}

module "rules" {
  source = "../../python-azure-naming"
}

module "metadata"{
  source = "github.com/Azure-Terraform/terraform-azurerm-metadata.git?ref=v1.0.0"

  naming_rules = module.rules.yaml
  
  market              = "us"
  project             = "test_by_godji"
  location            = "useast2"
  sre_team            = "hpcc_platform"
  environment         = "dev"
  product_name        = "tfe"
  business_unit       = "hpccplat"
  product_group       = "core"
  subscription_id     = module.subscription.output.subscription_id
  subscription_type   = "nonprod"
  resource_group_type = "app"
}

module "resource_group" {
  source = "github.com/Azure-Terraform/terraform-azurerm-resource-group.git?ref=v1.0.0"
  
  location = module.metadata.location
  names    = module.metadata.names
  tags     = module.metadata.tags
}

module "kubernetes" {
  source = "github.com/Azure-Terraform/terraform-azurerm-kubernetes.git?ref=v1.2.1"
  
  location                 = module.metadata.location
  names                    = module.metadata.names
  tags                     = module.metadata.tags
  kubernetes_version       = "1.18.8"
  resource_group_name      = module.resource_group.name

  default_node_pool_name                = "default"
  default_node_pool_vm_size             = "Standard_D2s_v3"
  default_node_pool_enable_auto_scaling = true
  default_node_pool_node_min_count      = 1
  default_node_pool_node_max_count      = 5
  default_node_pool_availability_zones  = [1,2,3]

  enable_kube_dashboard = true
}

###############
# HPCC Deploy #
###############

resource "helm_release" "hpcc" {
  provider    = helm.aks

  name       = "my-hpcc-terra-cluster"
  namespace  = "default"
  repository = "https://hpcc-systems.github.io/helm-chart/"
  chart      = "hpcc"
  version    = "7.12.18-rc1"

  set {
    name  = "global.image.version"
    value = "7.12.24-rc1"
  }

  set {
    name  = "storage.dllStorage.storageClass"
    value = "azurefile"
  }

  set {
    name  = "storage.daliStorage.storageClass"
    value = "azurefile"
  }

  set {
    name  = "storage.dataStorage.storageClass"
    value = "azurefile"
  }

}

##########
# Output #
##########

output "resource_group_name" {
  value = module.resource_group.name
}

output "aks_cluster_name" {
  value = module.kubernetes.name
}

output "aks_login" {
  value = "az aks get-credentials --name ${module.kubernetes.name} --resource-group ${module.resource_group.name}"
}

output "aks_browse"{
  value = "az aks browse --name ${module.kubernetes.name} --resource-group ${module.resource_group.name}"
}