output "k8s_cluster_id" {
  description = "Идентификатор кластера Managed Kubernetes"
  value       = yandex_kubernetes_cluster.main.id
}

output "k8s_cluster_name" {
  description = "Имя кластера"
  value       = yandex_kubernetes_cluster.main.name
}

output "k8s_node_group_id" {
  description = "Идентификатор группы узлов"
  value       = yandex_kubernetes_node_group.main.id
}

output "k8s_external_endpoint" {
  description = "Внешний адрес API кластера"
  value       = yandex_kubernetes_cluster.main.master[0].external_v4_endpoint
}

output "get_kubeconfig" {
  description = "Команда для получения kubeconfig"
  value       = "yc managed-kubernetes cluster get-credentials --id ${yandex_kubernetes_cluster.main.id} --external --force"
}

output "db_host" {
  description = "FQDN хоста PostgreSQL"
  value       = yandex_mdb_postgresql_cluster.main.host[0].fqdn
}

output "db_port" {
  description = "Порт пулера соединений PostgreSQL"
  value       = 6432
}

output "db_name" {
  description = "Имя базы данных"
  value       = yandex_mdb_postgresql_database.app.name
}

output "db_user" {
  description = "Пользователь базы данных"
  value       = yandex_mdb_postgresql_user.app.name
}

output "db_password" {
  description = "Пароль пользователя базы данных"
  value       = random_password.db.result
  sensitive   = true
}

output "db_url" {
  description = "JDBC-строка подключения к базе"
  value       = local.db_url
}

output "storage_bucket" {
  description = "Имя бакета с картинками объявлений"
  value       = yandex_storage_bucket.media.bucket
}

output "storage_endpoint" {
  description = "Эндпоинт Object Storage"
  value       = local.s3_endpoint
}

output "storage_access_key" {
  description = "Access key сервисного аккаунта приложения"
  value       = yandex_iam_service_account_static_access_key.storage.access_key
  sensitive   = true
}

output "storage_secret_key" {
  description = "Secret key сервисного аккаунта приложения"
  value       = yandex_iam_service_account_static_access_key.storage.secret_key
  sensitive   = true
}

output "network_id" {
  description = "Идентификатор сети"
  value       = yandex_vpc_network.main.id
}

output "subnet_id" {
  description = "Идентификатор подсети"
  value       = yandex_vpc_subnet.main.id
}

output "ingress_ip" {
  description = "Зарезервированный публичный адрес для ingress-контроллера"
  value       = yandex_vpc_address.ingress.external_ipv4_address[0].address
}

output "lockbox_secret_id" {
  description = "Идентификатор Lockbox-секрета с доступами приложения"
  value       = yandex_lockbox_secret.app.id
}

output "eso_authorized_key" {
  description = "Авторизованный ключ сервисного аккаунта для External Secrets Operator"
  value       = local.eso_authorized_key
  sensitive   = true
}

output "log_group_id" {
  description = "Идентификатор лог-группы Cloud Logging"
  value       = yandex_logging_group.app.id
}

output "folder_id" {
  description = "Каталог, в котором развёрнута инфраструктура"
  value       = var.folder_id
}
