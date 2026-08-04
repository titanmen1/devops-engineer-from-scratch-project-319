locals {
  db_url = format(
    "jdbc:postgresql://%s:6432/%s?sslmode=require",
    yandex_mdb_postgresql_cluster.main.host[0].fqdn,
    yandex_mdb_postgresql_database.app.name,
  )

  s3_endpoint = "https://storage.yandexcloud.net"
  s3_region   = "ru-central1"

  eso_authorized_key = jsonencode({
    id                 = yandex_iam_service_account_key.eso.id
    service_account_id = yandex_iam_service_account.eso.service_account_id
    created_at         = yandex_iam_service_account_key.eso.created_at
    key_algorithm      = yandex_iam_service_account_key.eso.key_algorithm
    public_key         = yandex_iam_service_account_key.eso.public_key
    private_key        = yandex_iam_service_account_key.eso.private_key
  })
}
