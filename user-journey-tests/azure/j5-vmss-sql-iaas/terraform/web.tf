# The MES web tier: a scale set of Windows instances behind a Standard load
# balancer, with an autoscale rule bolted on in 2024 after a month-end run
# saturated the two original servers.
#
# Two things about the load balancer are load-bearing:
#
#  1. The outbound rule is the web tier's only path off the network. Subnets
#     created through recent API versions no longer get implicit outbound
#     access, and without a path out the instances cannot fetch the script
#     extension package and never finish provisioning.
#  2. disable_outbound_snat is true on the HTTP rule because the outbound rule
#     reuses the same frontend address. Azure rejects an outbound rule that
#     redefines an address already carrying inbound SNAT, so leaving this unset
#     fails the deployment rather than merely wasting ports.

resource "azurerm_public_ip" "web" {
  name                = "vsi-mes-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_lb" "web" {
  name                = "vsi-mes-lb"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  tags                = local.tags

  frontend_ip_configuration {
    name                 = "vsi-mes-fe"
    public_ip_address_id = azurerm_public_ip.web.id
  }
}

resource "azurerm_lb_backend_address_pool" "web" {
  name            = "vsi-mes-bepool"
  loadbalancer_id = azurerm_lb.web.id
}

resource "azurerm_lb_probe" "web" {
  name            = "vsi-mes-http-probe"
  loadbalancer_id = azurerm_lb.web.id
  protocol        = "Http"
  port            = 80
  request_path    = "/"
}

resource "azurerm_lb_rule" "web" {
  name                           = "vsi-mes-http"
  loadbalancer_id                = azurerm_lb.web.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "vsi-mes-fe"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.web.id]
  probe_id                       = azurerm_lb_probe.web.id
  disable_outbound_snat          = true
}

resource "azurerm_lb_outbound_rule" "web" {
  name                     = "vsi-mes-egress"
  loadbalancer_id          = azurerm_lb.web.id
  backend_address_pool_id  = azurerm_lb_backend_address_pool.web.id
  protocol                 = "All"
  allocated_outbound_ports = 1024
  idle_timeout_in_minutes  = 4

  frontend_ip_configuration {
    name = "vsi-mes-fe"
  }
}

locals {
  # cmd.exe reads the whole thing, so the HTML stays free of attributes: one
  # quote inside the quoted region and the angle brackets turn back into
  # redirection operators.
  mes_status_page_command = join("", [
    "powershell.exe -ExecutionPolicy Unrestricted -NoProfile -Command ",
    "\"Install-WindowsFeature -Name Web-Server -IncludeManagementTools; ",
    "$html = '<html><head><title>Precision-parts MES</title></head>",
    "<body><h1>Precision-parts MES</h1>",
    "<p>Manufacturing execution system - shop floor portal</p>",
    "<p>status: ok</p><p>host: ' + $env:COMPUTERNAME + '</p></body></html>'; ",
    "Set-Content -Path C:\\inetpub\\wwwroot\\index.html -Value $html -Encoding UTF8; ",
    "Remove-Item -Path C:\\inetpub\\wwwroot\\iisstart.htm -Force -ErrorAction SilentlyContinue\"",
  ])
}

resource "azurerm_windows_virtual_machine_scale_set" "mes" {
  name                = "vsi-mes-vmss"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.web_vm_size
  instances           = var.web_instance_count

  # Instance computer names are capped at 9 characters on Windows before the
  # instance suffix, so they cannot simply be the scale set name.
  computer_name_prefix = "vsi-mes"
  admin_username       = var.admin_username
  admin_password       = var.admin_password

  overprovision          = true
  single_placement_group = true
  upgrade_mode           = "Manual"

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = var.web_image_sku
    version   = "latest"
  }

  os_disk {
    storage_account_type = "StandardSSD_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name                           = "vsi-mes-nic"
    primary                        = true
    accelerated_networking_enabled = true

    ip_configuration {
      name                                   = "vsi-mes-ipcfg"
      primary                                = true
      subnet_id                              = azurerm_subnet.web.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.web.id]
    }
  }

  # IIS and the status page are what the load balancer probe sees. There is no
  # deployment pipeline behind this: the MES vendor's installer runs by hand on
  # a maintenance window, and the page below is the placeholder the contractor
  # left in front of it in 2022.
  extension {
    name                       = "InstallIIS"
    publisher                  = "Microsoft.Compute"
    type                       = "CustomScriptExtension"
    type_handler_version       = "1.10"
    auto_upgrade_minor_version = true

    settings = jsonencode({
      commandToExecute = local.mes_status_page_command
    })
  }

  boot_diagnostics {}

  tags = local.tags

  # The instances cannot reach the extension repository until the outbound rule
  # exists, and the provider does not infer that ordering from the backend pool
  # reference alone.
  depends_on = [
    azurerm_lb_rule.web,
    azurerm_lb_outbound_rule.web,
    azurerm_subnet_network_security_group_association.web,
  ]
}

# Added after the March 2024 month-end close, when order confirmations queued
# behind a saturated web tier for most of an afternoon. The plant manager was
# shown the graph and signed it off on the spot.
resource "azurerm_monitor_autoscale_setting" "mes" {
  name                = "vsi-mes-autoscale"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = azurerm_windows_virtual_machine_scale_set.mes.id
  tags                = local.tags

  profile {
    name = "shop-floor-hours"

    capacity {
      default = 2
      minimum = 2
      maximum = 4
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.mes.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.mes.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}
