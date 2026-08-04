# Состояние лежит в Object Storage, а не в репозитории: в нём открытым текстом
# пароль базы и ключи сервисных аккаунтов. Бакет и статический ключ доступа
# заводит `make tf-bootstrap` — они создаются до первого apply, поэтому не
# описаны в Terraform.
terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://storage.yandexcloud.net"
    }

    bucket = "bulletins-319-tfstate"
    key    = "kubernetes/terraform.tfstate"
    region = "ru-central1"

    # Object Storage совместим с S3 частично, поэтому проверки AWS отключены.
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    skip_metadata_api_check     = true
  }
}
