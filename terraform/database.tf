# Пароль генерируем здесь и кладём в Lockbox: в репозиторий он не попадает,
# а в состоянии Terraform лежит в бакете, а не в git.
# Спецсимволы ограничены безопасным набором, чтобы пароль не ломал JDBC-URL.
resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "-_"
}

resource "yandex_mdb_postgresql_cluster" "main" {
  name        = "${var.project_name}-pg"
  description = "База объявлений"
  environment = "PRODUCTION"

  network_id         = yandex_vpc_network.main.id
  security_group_ids = [yandex_vpc_security_group.db.id]

  config {
    version = var.db_version

    resources {
      resource_preset_id = var.db_preset
      disk_type_id       = var.db_disk_type
      disk_size          = var.db_disk_size
    }
  }

  host {
    zone      = var.zone
    subnet_id = yandex_vpc_subnet.main.id
    # Хост доступен только из своей сети — снаружи в базу ходить незачем.
    assign_public_ip = false
  }
}

resource "yandex_mdb_postgresql_user" "app" {
  cluster_id = yandex_mdb_postgresql_cluster.main.id
  name       = var.db_user
  password   = random_password.db.result
}

resource "yandex_mdb_postgresql_database" "app" {
  cluster_id = yandex_mdb_postgresql_cluster.main.id
  name       = var.db_name
  owner      = yandex_mdb_postgresql_user.app.name
}
