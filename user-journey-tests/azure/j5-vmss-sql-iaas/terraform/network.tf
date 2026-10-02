# One virtual network, split the way the 2022 lift split it: the MES web tier
# in front, the database server behind. The address space is the block the
# plant's network team handed over and has not changed since.

resource "azurerm_virtual_network" "main" {
  name                = "vsi-vnet"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.40.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "web" {
  name                 = "vsi-web-snet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.40.1.0/24"]
}

resource "azurerm_subnet" "data" {
  name                 = "vsi-data-snet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.40.2.0/24"]
}

# The web tier answers HTTP from the load balancer's frontend. Azure's own
# health probes arrive from 168.63.129.16, which the AzureLoadBalancer service
# tag covers; without that rule the probe never marks an instance healthy and
# the frontend serves nothing.
resource "azurerm_network_security_group" "web" {
  name                = "vsi-web-nsg"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.tags

  security_rule {
    name                       = "allow-http-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-lb-probe"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
}

# The database server takes TDS from the web subnet and nothing else from
# outside the network. The remote-desktop rule is scoped to VirtualNetwork, and
# since there is no gateway into that network and no jump host inside it, the
# only way onto this machine in practice is the portal's serial console.
resource "azurerm_network_security_group" "data" {
  name                = "vsi-data-nsg"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.tags

  security_rule {
    name                       = "allow-tds-from-web"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = "10.40.1.0/24"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-rdp-from-vnet"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

resource "azurerm_subnet_network_security_group_association" "data" {
  subnet_id                 = azurerm_subnet.data.id
  network_security_group_id = azurerm_network_security_group.data.id
}

# The data subnet's route out. Subnets created through recent API versions no
# longer get implicit outbound access, and the database server has no inbound
# public address to borrow one from, so the way out has to be explicit. The
# web subnet does not use this — its outbound path is the load balancer rule
# in web.tf.
#
# What actually needs it: Windows Update, the backup agent's calls home, and
# the vendor's licence check for the MES importer.
resource "azurerm_public_ip" "nat" {
  name                = "vsi-nat-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}

resource "azurerm_nat_gateway" "data" {
  name                    = "vsi-data-natgw"
  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4
  tags                    = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "data" {
  nat_gateway_id       = azurerm_nat_gateway.data.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "data" {
  subnet_id      = azurerm_subnet.data.id
  nat_gateway_id = azurerm_nat_gateway.data.id
}
