### Hexlet tests and linter status:
[![Actions Status](https://github.com/titanmen1/devops-engineer-from-scratch-project-319/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/titanmen1/devops-engineer-from-scratch-project-319/actions)

# Доска объявлений в Managed Kubernetes

Приложение «доска объявлений» разворачивается в Yandex Managed Service for
Kubernetes. Инфраструктура описывается кодом, релизы проходят без простоя.

Исходный код приложения: [titanmen1/project-devops-deploy](https://github.com/titanmen1/project-devops-deploy).
Образ собирается в CI и публикуется в GitHub Container Registry:
`ghcr.io/titanmen1/project-devops-deploy:latest`.

Pull request'ы в этот репозиторий не принимаются — это учебный проект.

## Образ приложения

Образ собирает [.github/workflows/ci.yml](https://github.com/titanmen1/project-devops-deploy/blob/main/.github/workflows/ci.yml)
в репозитории приложения: после линтера и тестов пушится `latest` для основной
ветки и `<branch>-<sha>` для каждого коммита. Инструкции по ручному логину и
пушу лежат в README самого приложения.

Проверить опубликованный образ:

```bash
docker manifest inspect ghcr.io/titanmen1/project-devops-deploy:latest
```

## Локальный запуск

Тот же образ, что поедет в кластер, поднимается локально вместе с PostgreSQL и
MinIO вместо Object Storage:

```bash
docker compose up -d
curl http://localhost:8080/api/bulletins
curl http://localhost:9090/actuator/health
docker compose down -v
```

Переменной `APP_IMAGE` можно подменить образ на локально собранный:

```bash
APP_IMAGE=project-devops-deploy:local docker compose up -d
```

Порт 8080 — само приложение, 9090 — эндпоинты Actuator (health, метрики).
