locals {
  # 6432 — пулер соединений Managed PostgreSQL. sslmode=require включает
  # шифрование без проверки сертификата: корневой сертификат Яндекса на узлы
  # кластера не раскладывается.
  db_url = format(
    "jdbc:postgresql://%s:6432/%s?sslmode=require",
    yandex_mdb_postgresql_cluster.main.host[0].fqdn,
    yandex_mdb_postgresql_database.app.name,
  )

  s3_endpoint = "https://storage.yandexcloud.net"
  s3_region   = "ru-central1"
}
