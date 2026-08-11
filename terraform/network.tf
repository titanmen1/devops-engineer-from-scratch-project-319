resource "yandex_vpc_security_group" "k8s" {
  name        = "${var.project_name}-k8s-sg"
  description = "Правила для мастера и узлов кластера"
  network_id  = yandex_vpc_network.main.id

  ingress {
    protocol          = "TCP"
    description       = "Проверки состояния от сетевого балансировщика"
    predefined_target = "loadbalancer_healthchecks"
    from_port         = 0
    to_port           = 65535
  }

  ingress {
    protocol          = "ANY"
    description       = "Взаимодействие мастера и узлов между собой"
    predefined_target = "self_security_group"
    from_port         = 0
    to_port           = 65535
  }

  ingress {
    protocol       = "ANY"
    description    = "Трафик подов и сервисов внутри кластера"
    v4_cidr_blocks = [var.cluster_ipv4_range, var.service_ipv4_range]
    from_port      = 0
    to_port        = 65535
  }

  ingress {
    protocol       = "ICMP"
    description    = "ping внутри сети"
    v4_cidr_blocks = [var.subnet_cidr]
  }

  ingress {
    protocol       = "TCP"
    description    = "Диапазон NodePort: через него балансировщик отдаёт трафик наружу"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 30000
    to_port        = 32767
  }

  ingress {
    protocol       = "TCP"
    description    = "Доступ к API кластера снаружи"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 6443
  }

  ingress {
    protocol       = "TCP"
    description    = "Доступ к API кластера снаружи через 443"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  egress {
    protocol       = "ANY"
    description    = "Исходящий трафик: образы, обновления, API облака"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_vpc_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Доступ к PostgreSQL из кластера"
  network_id  = yandex_vpc_network.main.id

  ingress {
    protocol          = "TCP"
    description       = "Пулер соединений PostgreSQL"
    security_group_id = yandex_vpc_security_group.k8s.id
    port              = 6432
  }

  egress {
    protocol       = "ANY"
    description    = "Исходящий трафик"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}
