# Аутентификация — либо IAM-токеном (`yc iam create-token`), либо файлом с
# авторизованным ключом сервисного аккаунта. Пустая строка превращается в null,
# чтобы провайдер не считал незаполненную переменную заданной.
provider "yandex" {
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.zone

  token                    = var.yc_token != "" ? var.yc_token : null
  service_account_key_file = var.service_account_key_file != "" ? pathexpand(var.service_account_key_file) : null
}
