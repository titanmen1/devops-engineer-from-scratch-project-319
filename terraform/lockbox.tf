resource "yandex_lockbox_secret" "app" {
  name        = "${var.project_name}-app-secrets"
  description = "Доступы приложения к PostgreSQL и Object Storage"
  folder_id   = var.folder_id
}

resource "yandex_iam_service_account" "eso" {
  name        = "${var.project_name}-eso-sa"
  description = "Чтение Lockbox из кластера через External Secrets Operator"
}

resource "yandex_lockbox_secret_iam_member" "eso_payload_viewer" {
  secret_id = yandex_lockbox_secret.app.id
  role      = "lockbox.payloadViewer"
  member    = "serviceAccount:${yandex_iam_service_account.eso.id}"
}

resource "yandex_iam_service_account_key" "eso" {
  service_account_id = yandex_iam_service_account.eso.id
  description        = "Ключ для External Secrets Operator"
  key_algorithm      = "RSA_2048"
}

resource "yandex_lockbox_secret_version_hashed" "app" {
  secret_id = yandex_lockbox_secret.app.id

  key_1        = "SPRING_DATASOURCE_URL"
  text_value_1 = local.db_url

  key_2        = "SPRING_DATASOURCE_USERNAME"
  text_value_2 = yandex_mdb_postgresql_user.app.name

  key_3        = "SPRING_DATASOURCE_PASSWORD"
  text_value_3 = random_password.db.result

  key_4        = "STORAGE_S3_ENDPOINT"
  text_value_4 = local.s3_endpoint

  key_5        = "STORAGE_S3_BUCKET"
  text_value_5 = yandex_storage_bucket.media.bucket

  key_6        = "STORAGE_S3_REGION"
  text_value_6 = local.s3_region

  key_7        = "STORAGE_S3_ACCESSKEY"
  text_value_7 = yandex_iam_service_account_static_access_key.storage.access_key

  key_8        = "STORAGE_S3_SECRETKEY"
  text_value_8 = yandex_iam_service_account_static_access_key.storage.secret_key

  depends_on = [yandex_mdb_postgresql_database.app]
}
