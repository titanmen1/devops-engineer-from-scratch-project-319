### Hexlet tests and linter status:
[![Actions Status](https://github.com/titanmen1/devops-engineer-from-scratch-project-319/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/titanmen1/devops-engineer-from-scratch-project-319/actions)

# Доска объявлений в Managed Kubernetes

Приложение «доска объявлений» разворачивается в Yandex Managed Service for
Kubernetes. Вся инфраструктура описана в Terraform и поднимается с нуля одной
командой: сеть, кластер, управляемый PostgreSQL, Object Storage и Lockbox для
секретов.

Исходный код приложения: [titanmen1/project-devops-deploy](https://github.com/titanmen1/project-devops-deploy).
Образ собирается в CI и публикуется в GitHub Container Registry:
`ghcr.io/titanmen1/project-devops-deploy:latest`.

Pull request'ы в этот репозиторий не принимаются — это учебный проект.

## Схема инфраструктуры

```text
Yandex Cloud, зона ru-central1-d
│
├── VPC bulletins-319-net (10.20.0.0/16)
│   ├── NAT-шлюз + таблица маршрутизации — выход узлов в интернет
│   ├── security group bulletins-319-k8s-sg — мастер и узлы
│   └── security group bulletins-319-db-sg — только порт 6432 из кластера
│
├── Managed Kubernetes bulletins-319-k8s (зональный мастер, публичный API)
│   └── группа узлов bulletins-319-ng — 2 vCPU × 20%, 4 ГБ на узел
│
├── Managed PostgreSQL bulletins-319-pg (b2.medium, доступен только из кластера)
├── Object Storage bulletins-319-media — картинки объявлений
├── Object Storage bulletins-319-tfstate — состояние Terraform
└── Lockbox bulletins-319-app-secrets — доступы к базе и хранилищу
```

## Требования к рабочей машине

| Инструмент | Версия | Зачем |
|---|---|---|
| [Yandex Cloud CLI](https://yandex.cloud/ru/docs/cli/quickstart#install) | 1.22+ | аутентификация в облаке, kubeconfig, bootstrap состояния |
| [Terraform](https://developer.hashicorp.com/terraform/install) | 1.6+ | инфраструктура |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.32+ | работа с кластером |
| Docker | 24+ | локальный прогон приложения |
| GNU Make | — | все команды репозитория |
| Python 3 | 3.9+ | разбор JSON в bootstrap-скрипте |

Проверка:

```bash
yc version && terraform version && kubectl version --client
```

Нужен сервисный аккаунт Yandex Cloud с ролью `admin` в каталоге и настроенный
профиль `yc` (`yc init`). Все команды `make tf-*` сами берут `cloud-id` и
`folder-id` из профиля и запрашивают свежий IAM-токен.

## Развёртывание инфраструктуры

```bash
make tf-bootstrap   # сервисный аккаунт, ключ и бакет для состояния Terraform
make tf-init        # инициализация с backend в Object Storage
make tf-plan        # проверка плана
make tf-apply       # создание инфраструктуры (15–20 минут)
make kubeconfig     # доступ к кластеру
```

После `make tf-apply` проверить кластер:

```bash
kubectl get nodes
```

## Terraform

Конфигурация лежит в *terraform/* и разбита по смыслу:

| Файл | Что описывает |
|---|---|
| `versions.tf` | версии Terraform и провайдеров |
| `providers.tf` | провайдер Yandex Cloud и способ аутентификации |
| `backend.tf` | хранение состояния в Object Storage |
| `variables.tf` | все параметры инфраструктуры |
| `locals.tf` | строка подключения к базе и параметры S3 |
| `network.tf` | сеть, подсеть, NAT, security groups, публичный адрес |
| `kubernetes.tf` | сервисные аккаунты, кластер, группа узлов |
| `database.tf` | Managed PostgreSQL, база и пользователь |
| `storage.tf` | бакет для картинок и ключи доступа к нему |
| `lockbox.tf` | секрет с доступами приложения |
| `outputs.tf` | адреса и идентификаторы для следующих шагов |

Состояние хранится в бакете `bulletins-319-tfstate` с включённым
версионированием — в нём открытым текстом лежат пароль базы и ключи сервисных
аккаунтов, поэтому в репозиторий оно не попадает. Бакет и ключи доступа к нему
заводит `make tf-bootstrap`: сам бакет описать в Terraform нельзя, он нужен
раньше первого apply. Ключи складываются в `terraform/.backend-credentials` —
файл в `.gitignore`.

Полезные выводы:

```bash
make tf-output                                  # всё разом
terraform -chdir=terraform output -raw db_url   # строка подключения к базе
terraform -chdir=terraform output -raw lockbox_secret_id
```

## Локальный запуск приложения

Тот же образ, что едет в кластер, поднимается локально вместе с PostgreSQL и
MinIO вместо Object Storage:

```bash
docker compose up -d
curl http://localhost:8080/api/bulletins
curl http://localhost:9090/actuator/health
docker compose down -v
```

## Проверки

```bash
make lint   # terraform fmt -check + tflint
make test   # terraform init -backend=false + terraform validate
```

## Структура репозитория

```text
.
├── bin/tf-bootstrap.sh      # разовая подготовка бакета для состояния
├── terraform/               # инфраструктура Yandex Cloud
├── docker-compose.yaml      # локальный прогон приложения
├── Makefile                 # все команды проекта
└── README.md
```
