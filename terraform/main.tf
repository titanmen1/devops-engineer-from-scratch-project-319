resource "yandex_vpc_network" "main" {
  name        = "${var.project_name}-net"
  description = "Сеть кластера, базы данных и балансировщика"
}

resource "yandex_vpc_gateway" "nat" {
  name = "${var.project_name}-nat"

  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "main" {
  name       = "${var.project_name}-rt"
  network_id = yandex_vpc_network.main.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat.id
  }
}

resource "yandex_vpc_subnet" "main" {
  name           = "${var.project_name}-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.subnet_cidr]
  route_table_id = yandex_vpc_route_table.main.id
}

resource "yandex_vpc_address" "ingress" {
  name = "${var.project_name}-ingress-ip"

  external_ipv4_address {
    zone_id = var.zone
  }
}
