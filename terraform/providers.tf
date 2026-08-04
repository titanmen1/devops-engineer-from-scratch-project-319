provider "yandex" {
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.zone

  token                    = var.yc_token != "" ? var.yc_token : null
  service_account_key_file = var.service_account_key_file != "" ? pathexpand(var.service_account_key_file) : null
}
