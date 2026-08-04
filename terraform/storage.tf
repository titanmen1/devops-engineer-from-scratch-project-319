resource "yandex_iam_service_account" "storage" {
  name        = "${var.project_name}-storage-sa"
  description = "Сервисный аккаунт приложения для доступа к Object Storage"
}

resource "yandex_resourcemanager_folder_iam_member" "storage_editor" {
  folder_id = var.folder_id
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.storage.id}"
}

resource "yandex_iam_service_account_static_access_key" "storage" {
  service_account_id = yandex_iam_service_account.storage.id
  description        = "Статический ключ доступа к Object Storage"
}

# Бакет закрытый: приложение отдаёт картинки по presigned-ссылкам, публичное
# чтение для этого не требуется.
resource "yandex_storage_bucket" "media" {
  bucket = var.bucket_name

  access_key = yandex_iam_service_account_static_access_key.storage.access_key
  secret_key = yandex_iam_service_account_static_access_key.storage.secret_key

  depends_on = [yandex_resourcemanager_folder_iam_member.storage_editor]
}
