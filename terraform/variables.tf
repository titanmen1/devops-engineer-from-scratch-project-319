# --- Доступ к облаку ---------------------------------------------------------

variable "cloud_id" {
  description = "Идентификатор облака Yandex Cloud"
  type        = string
}

variable "folder_id" {
  description = "Идентификатор каталога Yandex Cloud"
  type        = string
}

variable "yc_token" {
  description = "IAM-токен Yandex Cloud. Можно не задавать, если указан service_account_key_file"
  type        = string
  default     = ""
  sensitive   = true
}

variable "service_account_key_file" {
  description = "Путь к JSON с авторизованным ключом сервисного аккаунта"
  type        = string
  default     = ""
}

variable "zone" {
  description = "Зона доступности для кластера и базы"
  type        = string
  default     = "ru-central1-d"
}

variable "project_name" {
  description = "Префикс имён ресурсов"
  type        = string
  default     = "bulletins-319"
}

# --- Сеть --------------------------------------------------------------------

variable "subnet_cidr" {
  description = "CIDR подсети, в которой живут узлы кластера и хост базы"
  type        = string
  default     = "10.20.0.0/16"
}

variable "cluster_ipv4_range" {
  description = "Диапазон адресов для подов кластера"
  type        = string
  default     = "10.112.0.0/16"
}

variable "service_ipv4_range" {
  description = "Диапазон адресов для сервисов кластера"
  type        = string
  default     = "10.96.0.0/16"
}

# --- Kubernetes --------------------------------------------------------------

variable "k8s_version" {
  description = "Версия Kubernetes для мастера и группы узлов"
  type        = string
  default     = "1.32"
}

variable "k8s_release_channel" {
  description = "Канал обновлений кластера: RAPID, REGULAR или STABLE"
  type        = string
  default     = "STABLE"
}

variable "node_count" {
  description = "Количество рабочих узлов"
  type        = number
  default     = 1
}

variable "node_cores" {
  description = "Количество vCPU на узел"
  type        = number
  default     = 2
}

variable "node_core_fraction" {
  description = "Гарантированная доля vCPU в процентах (на standard-v3 доступны 20, 50, 100)"
  type        = number
  default     = 20
}

variable "node_memory" {
  description = "Оперативная память узла, ГБ"
  type        = number
  default     = 4
}

variable "node_disk_size" {
  description = "Размер загрузочного диска узла, ГБ"
  type        = number
  default     = 64
}

variable "node_disk_type" {
  description = "Тип загрузочного диска узла"
  type        = string
  default     = "network-hdd"
}

variable "node_preemptible" {
  description = "Прерываемые узлы дешевле, но останавливаются минимум раз в сутки"
  type        = bool
  default     = false
}

# --- База данных -------------------------------------------------------------

variable "db_version" {
  description = "Версия PostgreSQL"
  type        = string
  default     = "16"
}

variable "db_preset" {
  description = "Класс хоста PostgreSQL"
  type        = string
  default     = "b2.medium"
}

variable "db_disk_size" {
  description = "Размер диска PostgreSQL, ГБ"
  type        = number
  default     = 20
}

variable "db_disk_type" {
  description = "Тип диска PostgreSQL"
  type        = string
  default     = "network-ssd"
}

variable "db_name" {
  description = "Имя базы данных приложения"
  type        = string
  default     = "bulletins"
}

variable "db_user" {
  description = "Имя пользователя базы данных"
  type        = string
  default     = "bulletins"
}

# --- Object Storage ----------------------------------------------------------

variable "bucket_name" {
  description = "Имя бакета для картинок объявлений (уникально в пределах Object Storage)"
  type        = string
  default     = "bulletins-319-media"
}
