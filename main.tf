terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.66.0"
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
  ssh_func_name = "ssh${random_string.unique.result}"
  ras_func_name = "ras${random_string.unique.result}"
  loc_for_naming = lower(replace(var.location, " ", ""))
}

data "azurerm_client_config" "current" {}

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
    working_dir = "DetermineActiveSite"
    app_settings = {
      "FUNCTIONS_WORKER_RUNTIME" = "python"
      "COSMOSDB_ENDPOINT"        = azurerm_cosmosdb_account.cosmos.endpoint
      "COSMOSDB_KEY"             = azurerm_cosmosdb_account.cosmos.primary_key
      "COSMOSDB_NAME"            = "${local.das_func_name}-db"
      "COSMOSDB_CONTAINER"       = "${local.das_func_name}-dbcontainer"
    }

}


module "sshfunction" {
  source = "github.com/implodingduck/tfmodules//functionapp"
  func_name = local.ssh_func_name
  resource_group_name = azurerm_resource_group.rg.name
  resource_group_location = azurerm_resource_group.rg.location
  working_dir = "PerformSSH"
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME" = "python"
    "SSH_PASSWORD"        = random_password.password.result
  }

}

resource "azurerm_cosmosdb_account" "cosmos" {
  name                = "${local.das_func_name}-dba"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  enable_free_tier    = false
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


resource "azurerm_virtual_network" "default" {
  name                = "demo-vnet-${local.loc_for_naming}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [var.vnet_cidr]
  dns_servers         = []
  tags                = {}
}

resource "azurerm_subnet" "default" {
  name                 = "default-subnet-${local.loc_for_naming}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = [var.default_subnet_cidr]

}

resource "azurerm_subnet" "vm" {
  name                 = "demo-subnet-${local.loc_for_naming}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = [var.vm_subnet_cidr]
  service_endpoints    = []

}

resource "azurerm_key_vault" "kv" {
  name                        = "${local.ssh_func_name}-kv"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Purge"
    ]
    certificate_permissions = []
    key_permissions = []
    storage_permissions = []
  }
  tags = {}
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "_!"
}

resource "azurerm_key_vault_secret" "vmpassword" {
  name         = "vmpassword"
  value        = random_password.password.result
  key_vault_id = azurerm_key_vault.kv.id
  tags         = {}
}



resource "azurerm_public_ip" "pip" {
  name                = "pipfor${local.ssh_func_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  zones               = []
  ip_tags             = {}
  tags                = {}
}

data "template_file" "nginx-vm-cloud-init" {
  template = file("${path.module}/install-nginx.sh")
}

resource "azurerm_storage_account" "sa" {
    name                        = "${local.ssh_func_name}vmdiag"
    resource_group_name         = azurerm_resource_group.rg.name
    location                    = azurerm_resource_group.rg.location
    account_replication_type    = "LRS"
    account_tier                = "Standard"
    tags                        = {}
}


resource "azurerm_network_interface" "nic" {
  name                = "${local.ssh_func_name}-vm-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.pip.id
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                = "${local.ssh_func_name}-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2s"
  admin_username      = "adminuser"
  admin_password      = random_password.password.result
  disable_password_authentication = false
  custom_data    = base64encode(data.template_file.nginx-vm-cloud-init.rendered)

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.sa.primary_blob_endpoint
  }
  tags = {
    "managed_by" = "terraform"
    "dossh"      = "true"
  }
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${local.ssh_func_name}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "httpstuff"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "httpsstuff"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "otherstuff"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2266"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

data "template_file" "logicapp" {
  template = file("${path.module}/arm_logicapp_template.json")
  vars = {
    "subscription_id" = var.subscription_id
    "displayName" = var.email
    "name" = "${local.ssh_func_name}-logicapp"
  }
}

data "template_file" "raslogicapp" {
  template = file("${path.module}/arm_ras_logicapp_template.json")
  vars = {
    "subscription_id" = var.subscription_id
    "name" = "${local.ras_func_name}-logicapp"
  }
}


data "template_file" "arm" {
  template = file("${path.module}/arm_armcon_template.json")
  vars = {
    "subscription_id" = var.subscription_id
    "displayName" = var.email
  }
}


data "template_file" "vm" {
  template = file("${path.module}/arm_vmcon_template.json")
  vars = {
    "subscription_id" = var.subscription_id
    "displayName" = var.email
  }
}

resource "azurerm_template_deployment" "logicapp" {
  name                = "${local.ssh_func_name}-logicapp"
  resource_group_name = azurerm_resource_group.rg.name

  template_body = data.template_file.logicapp.rendered
  deployment_mode = "Incremental"
}

resource "azurerm_template_deployment" "raslogicapp" {
  name                = "${local.ras_func_name}-logicapp"
  resource_group_name = azurerm_resource_group.rg.name

  template_body = data.template_file.raslogicapp.rendered
  deployment_mode = "Incremental"
}

resource "azurerm_template_deployment" "arm" {
  name                = "${local.ssh_func_name}-armcon"
  resource_group_name = azurerm_resource_group.rg.name

  template_body = data.template_file.arm.rendered
  deployment_mode = "Incremental"
}

resource "azurerm_template_deployment" "vm" {
  name                = "${local.ssh_func_name}-vmcon"
  resource_group_name = azurerm_resource_group.rg.name

  template_body = data.template_file.vm.rendered
  deployment_mode = "Incremental"
}

# resource "azurerm_user_assigned_identity" "runas" {
#   resource_group_name = azurerm_resource_group.rg.name
#   location            = azurerm_resource_group.rg.location

#   name = "${local.ras_func_name}-uai"
# }

# resource "azurerm_role_assignment" "role" {
#   scope                = azurerm_resource_group.rg.id
#   role_definition_name = "Contributor"
#   principal_id         = azurerm_user_assigned_identity.runas.principal_id
# }

module "rasfunction" {
  source = "github.com/implodingduck/tfmodules//functionapp"
  func_name = local.ras_func_name
  resource_group_name = azurerm_resource_group.rg.name
  resource_group_location = azurerm_resource_group.rg.location
  working_dir = "PerformRunCommand"
  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME" = "python"
    "SUBSCRIPTION_ID" = var.subscription_id
  }
  app_identity = [
    {
      type = "SystemAssigned"
      identity_ids = null
    }
  ]

}

resource "azurerm_logic_app_workflow" "example" {
  name                = "workflow_tf_type"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_logic_app_workflow" "test" {
  name                = "workflowresourcetype"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_logic_app_trigger_http_request" "test" {
  name         = "the-http-trigger"
  logic_app_id = azurerm_logic_app_workflow.test.id

  schema = <<SCHEMA
{
    "type": "object",
    "properties": {
        "name": {
            "type": "string"
        }
    }
}
SCHEMA

}

resource "azurerm_logic_app_action_custom" "test" {
  name         = "Condition"
  logic_app_id = azurerm_logic_app_workflow.example.id

  body = <<BODY
 {
    "Condition": {
        "actions": {
            "Set_variable": {
                "inputs": {
                    "name": "retval",
                    "value": "Hello, World is very original :P"
                },
                "runAfter": {},
                "type": "SetVariable"
            }
        },
        "else": {
            "actions": {
                "Set_variable_2": {
                    "inputs": {
                        "name": "retval",
                        "value": "Greetings, @{triggerBody()?['name']} !!!"
                    },
                    "runAfter": {},
                    "type": "SetVariable"
                }
            }
        },
        "expression": {
            "and": [
                {
                    "equals": [
                        "@triggerBody()?['name']",
                        "hello"
                    ]
                }
            ]
        },
        "runAfter": {
            "Initialize_variable": [
                "Succeeded"
            ]
        },
        "type": "If"
    },
    "Initialize_variable": {
        "inputs": {
            "variables": [
                {
                    "name": "retval",
                    "type": "string"
                }
            ]
        },
        "runAfter": {},
        "type": "InitializeVariable"
    },
    "Response": {
        "inputs": {
            "body": "@variables('retval')",
            "statusCode": 200
        },
        "kind": "Http",
        "runAfter": {
            "Condition": [
                "Succeeded"
            ]
        },
        "type": "Response"
    }
}
BODY

}