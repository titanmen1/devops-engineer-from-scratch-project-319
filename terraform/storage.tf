resource "yandex_iam_service_account" "storage" {
  name        = "${var.project_name}-storage-sa"
  description = "Сервисный аккаунт приложения для доступа к Object Storage"
}

# Роль на каталог даёт только право обратиться к Object Storage от имени
# аккаунта; что именно ему можно, ограничивает политика бакета ниже.
# storage.uploader, а не storage.editor: создавать и удалять бакеты каталога
# приложению не нужно, оно кладёт и читает объекты в одном своём бакете.
resource "yandex_resourcemanager_folder_iam_member" "storage_uploader" {
  folder_id = var.folder_id
  role      = "storage.uploader"
  member    = "serviceAccount:${yandex_iam_service_account.storage.id}"
}

resource "yandex_iam_service_account_static_access_key" "storage" {
  service_account_id = yandex_iam_service_account.storage.id
  description        = "Статический ключ доступа к Object Storage"
}

# Бакет заводит сам Terraform своими правами, а не ключом приложения: иначе
# приложению пришлось бы выдавать storage.editor на весь каталог.
resource "yandex_storage_bucket" "media" {
  bucket = var.bucket_name
}

# Аккаунт приложения работает только с объектами этого бакета: читать и писать
# можно, управлять самим бакетом — нет.
resource "yandex_storage_bucket_policy" "media" {
  bucket = yandex_storage_bucket.media.bucket

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AppObjectAccess"
        Effect = "Allow"
        Principal = {
          CanonicalUser = yandex_iam_service_account.storage.id
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "arn:aws:s3:::${var.bucket_name}/*"
      },
      {
        Sid    = "AppBucketListing"
        Effect = "Allow"
        Principal = {
          CanonicalUser = yandex_iam_service_account.storage.id
        }
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = "arn:aws:s3:::${var.bucket_name}"
      },
    ]
  })
}
