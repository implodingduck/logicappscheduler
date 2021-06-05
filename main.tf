terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.62.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "=3.1.0"
    }
  }
  backend "azurerm" {

  }
}

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
}

locals {
  das_func_name = "das${random_string.unique.result}"
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-logicapp-scheduler"
  location = var.location
}

resource "random_string" "unique" {
  length  = 8
  special = false
  upper   = false
}

module "function" {
    source = "github.com/implodingduck/tfmodules//functionapp"
    func_name = local.das_func_name
    resource_group_name = azurerm_resource_group.rg.name
    resource_group_location = azurerm_resource_group.rg.location
    app_settings = {
      "FUNCTIONS_WORKER_RUNTIME" = "python"
      "APPINSIGHTS_INSTRUMENTATIONKEY" = "${azurerm_application_insights.app.instrumentation_key}"
      "COSMOSDB_ENDPOINT"        = azurerm_cosmosdb_account.cosmos.endpoint
      "COSMOSDB_KEY"             = azurerm_cosmosdb_account.cosmos.primary_key
      "COSMOSDB_NAME"            = "${local.das_func_name}-db"
      "COSMOSDB_CONTAINER"       = "${local.das_func_name}-dbcontainer"
    }
    site_config {
      use_32_bit_worker_process   = false
      linux_fx_version = "Python|3.8"        
      ftps_state = "Disabled"
    }
}

resource "azurerm_cosmosdb_account" "cosmos" {
  name                = "${local.das_func_name}-dba"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  enable_free_tier    = true
  consistency_policy {
    consistency_level       = "Session"
  }

  geo_location {
    location          = "West US"
    failover_priority = 1
  }

  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
  }
}

resource "azurerm_cosmosdb_sql_database" "cosmos" {
  name                = "${local.das_func_name}-db"
  resource_group_name = azurerm_cosmosdb_account.cosmos.resource_group_name
  account_name        = azurerm_cosmosdb_account.cosmos.name
  throughput          = 400
}


resource "azurerm_cosmosdb_sql_container" "cosmos" {
  name                  = "${local.das_func_name}-dbcontainer"
  resource_group_name   = azurerm_cosmosdb_account.cosmos.resource_group_name
  account_name          = azurerm_cosmosdb_account.cosmos.name
  database_name         = azurerm_cosmosdb_sql_database.cosmos.name
  partition_key_path    = "/id"
  partition_key_version = 1
  throughput            = 400
}