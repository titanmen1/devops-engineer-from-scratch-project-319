### Hexlet tests and linter status:
[![Actions Status](https://github.com/titanmen1/devops-engineer-from-scratch-project-319/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/titanmen1/devops-engineer-from-scratch-project-319/actions)

# Доска объявлений в Managed Kubernetes

Приложение «доска объявлений» разворачивается в Yandex Managed Service for
Kubernetes. Вся инфраструктура описана в Terraform и поднимается с нуля одной
командой: сеть, кластер, управляемый PostgreSQL, Object Storage и Lockbox для
секретов.

**Приложение: http://158.160.145.165**

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
│   └── группа узлов bulletins-319-ng — 2 узла, 2 vCPU × 20%, 4 ГБ
│       ├── ingress-nginx → публичный адрес 158.160.145.165
│       └── namespace bulletins: Deployment, Service, Ingress, PDB, HPA
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
| [Helm](https://helm.sh/docs/intro/install/) | 3.x | выкат приложения и сторонних чартов |
| Docker | 24+ | локальный прогон приложения |
| GNU Make | — | все команды репозитория |
| Python 3 | 3.9+ | разбор JSON в bootstrap-скрипте |

Проверка:

```bash
yc version && terraform version && kubectl version --client && helm version --short
```

Нужен сервисный аккаунт Yandex Cloud с ролью `admin` в каталоге и настроенный
профиль `yc` (`yc init`). Все команды `make tf-*` сами берут `cloud-id` и
`folder-id` из профиля и запрашивают свежий IAM-токен.

## Развёртывание с нуля

Полный цикл — от пустого облака до приложения с мониторингом:

```bash
make tf-bootstrap       # сервисный аккаунт, ключ и бакет для состояния Terraform
make tf-init            # инициализация с backend в Object Storage
make tf-plan            # проверка плана
make tf-apply           # создание инфраструктуры (15–20 минут)
make kubeconfig         # доступ к кластеру

make ingress-install    # ingress-контроллер на зарезервированном адресе
make secrets-install    # External Secrets Operator и ключ для чтения Lockbox
make deploy             # приложение Helm-чартом (вместе с sidecar метрик)

make logging-install    # сбор логов подов в Cloud Logging

make smoke              # проверка приложения снаружи
```

Все команды репозитория:

| Команда | Что делает |
|---|---|
| `make tf-bootstrap` | заводит бакет и ключи для состояния Terraform |
| `make tf-init` / `tf-plan` / `tf-apply` / `tf-destroy` | работа с инфраструктурой |
| `make tf-output` | выводы Terraform: адреса, идентификаторы, доступы |
| `make kubeconfig` | доступ к кластеру для kubectl и Helm |
| `make deploy` / `deploy-dev` | выкат чарта в прод или тестовое окружение |
| `make rollback` / `helm-history` | откат релиза и список ревизий |
| `make k8s-status` / `k8s-rollout` / `k8s-logs` / `k8s-forward` | состояние и отладка приложения |
| `make secrets-install` / `secrets-status` | Lockbox через External Secrets Operator |
| `make ingress-install` / `ingress-ip` | внешний доступ |
| `make logging-install` / `logs-cloud` | логи в Cloud Logging |
| `make monitoring-install` | включить метрики на уже развёрнутом релизе |
| `make smoke` | проверка приложения по публичному адресу |
| `make lint` / `test` | проверки Terraform и Helm |

## Приложение в кластере

Приложение живёт в namespace `bulletins`. Конфигурация разложена по двум
объектам: несекретные параметры — в ConfigMap `bulletin-board-config`, доступы к
базе и Object Storage — в Secret `bulletin-secret`. Секрет наполняет External
Secrets Operator из Lockbox (см. [Секреты](#секреты)); если оператор не нужен,
секрет можно завести напрямую из выводов Terraform командой `make k8s-secret`,
образец полей лежит в [k8s/secret.example.yaml](k8s/secret.example.yaml).

Проверить приложение без внешнего доступа:

```bash
make k8s-forward
curl http://localhost:8080/api/bulletins
```

Порт 8080 отдаёт приложение, 9090 — Actuator. Probes ходят именно в 9090:
`/actuator/health/readiness` и `/actuator/health/liveness`. Пока Spring Boot
стартует (около 30 секунд), под держит startupProbe, поэтому liveness не
перезапускает его на старте.

## Внешний доступ

Наружу трафик отдаёт ingress-nginx: контроллер получает публичный адрес через
сетевой балансировщик Yandex Cloud. Адрес зарезервирован в Terraform
(`yandex_vpc_address`), поэтому переживает пересоздание сервиса.

```bash
make ingress-install   # контроллер занимает зарезервированный адрес
make ingress-ip        # какой это адрес
make smoke             # проверка приложения снаружи
```

Приложение доступно по адресу **http://158.160.145.165**.

Правило Ingress описано без `host`, поэтому принимает запросы и по адресу, и по
доменному имени, если его позже привяжут к этому адресу.

У сервиса контроллера `externalTrafficPolicy: Local`. При `Cluster` kube-proxy
разбрасывает пакеты между узлами и подменяет адрес источника: до nginx и дальше
в приложение доезжает адрес узла, а не клиента, и в логах остаются внутренние
адреса. `Local` этого не делает и сохраняет реальный IP. Плата за это — узел
без пода контроллера перестаёт отвечать на проверки балансировщика, поэтому
реплик контроллера столько же, сколько узлов, а их разнос по узлам сделан
жёстким (`whenUnsatisfiable: DoNotSchedule` в *k8s/ingress-nginx-values.yaml*).

Если после `make ingress-install` приложение недоступно снаружи, а балансировщик
в консоли «Принимает трафик» — проверьте сам зарезервированный адрес. Бывает,
что Yandex Cloud выдаёт публичный IP, через который проходит ICMP (`ping`), но
не устанавливается TCP-соединение. Балансировщик при этом здоров, healthcheck
зелёный, изнутри кластера всё отвечает `200` — снаружи глухой таймаут. Лечится
пересозданием адреса:

```bash
terraform -chdir=terraform apply -replace=yandex_vpc_address.ingress
make ingress-install   # контроллер занимает новый адрес
```

Диагностика: `ping` идёт, а `nc -z <ip> 80` показывает таймаут (не «refused») —
почти наверняка дело в адресе, а не в кластере. Проверить доступность можно с
внешних нод (например, через check-host.net), чтобы исключить свою сеть.

## Масштабирование и релизы без простоя

Кластер держит два рабочих узла (`node_count` в *terraform/variables.tf*),
приложение — две реплики. За безостановочность отвечают четыре вещи:

| Что | Где | Зачем |
|---|---|---|
| `maxUnavailable: 0`, `maxSurge: 1` | Deployment | во время выката всегда есть полный набор рабочих подов |
| `preStop: sleep 10` | Deployment | под успевает уйти из endpoints до остановки |
| `topologySpreadConstraints` | Deployment | реплики стоят на разных узлах |
| PodDisruptionBudget | *templates/pdb.yaml* | при сливе узла остаётся минимум одна реплика |

`matchLabelKeys: [pod-template-hash]` в правиле разноса считает перекос только
среди подов текущей ревизии. Без него в расчёт попадают ещё живые поды старой
ревизии, и обе новые реплики законно уезжают на один узел.

Правило разноса мягкое (`whenUnsatisfiable: ScheduleAnyway`), и это осознанно.
Узла в кластере два, поэтому при `DoNotSchedule` вывод одного узла в
обслуживание — а `auto_upgrade` и `auto_repair` включены — оставил бы вторую
реплику в Pending: встать ей было бы некуда, перекос стал бы равен двум. То
есть ровно в тот момент, ради которого написан PDB, приложение осталось бы на
одной реплике. При `ScheduleAnyway` в обычной ситуации реплики всё так же
разъезжаются по разным узлам, а в момент слива не блокируются.

HorizontalPodAutoscaler (*templates/hpa.yaml*) держит от 2 до 4 реплик по загрузке
процессора (порог 70%). Metrics Server в Managed Kubernetes работает из
коробки, ставить ничего не нужно.

Пока HPA включён, `replicas` в Deployment не задаётся вовсе: иначе каждый
`helm upgrade` возвращал бы число реплик к значению из values и отменял то,
что намасштабировал автоскейлер. Значение `replicaCount` из values применяется
только там, где HPA выключен, — например, в dev.

Проверка выката под нагрузкой:

```bash
# в одном терминале — непрерывные запросы
while true; do curl -s -o /dev/null -w '%{http_code}\n' http://158.160.145.165/api/bulletins; sleep 0.3; done

# в другом — смена версии образа
kubectl -n bulletins set image deployment/bulletin-board \
  app=ghcr.io/titanmen1/project-devops-deploy:main-36200c4
kubectl -n bulletins rollout status deployment/bulletin-board
```

На таком прогоне выката (566 запросов за два переключения версии) все ответы
были `200`, ошибок и обрывов соединения не было.

Откат на предыдущую версию:

```bash
kubectl -n bulletins rollout undo deployment/bulletin-board
```

## Helm-чарт

Все ресурсы приложения собраны в чарт *k8s/bulletin-board*:

```text
k8s/bulletin-board/
├── Chart.yaml
├── values.yaml              # значения по умолчанию (прод)
├── values-dev.yaml          # окружение для проверок
└── templates/
    ├── _helpers.tpl                # имена и метки
    ├── namespace.yaml              # выключен: namespace заводит --create-namespace
    ├── configmap.yaml
    ├── unified-agent-config.yaml   # конфиг sidecar с метриками
    ├── secret.yaml                 # выключен: путь без Lockbox
    ├── secretstore.yaml            # доступ к Lockbox
    ├── externalsecret.yaml         # секрет приложения из Lockbox
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    ├── pdb.yaml
    └── hpa.yaml
```

Значения секретов в values не лежат: Deployment подключает секрет по имени из
`secret.existingSecret`, а наполняет его External Secrets Operator из Lockbox.
Так пароль базы не попадает ни в values, ни в историю релизов Helm. Шаблоны
`namespace.yaml` и `secret.yaml` по умолчанию выключены — они нужны только
для окружения без `--create-namespace` и без Lockbox.

В шаблон Deployment зашита аннотация `checksum/config` от ConfigMap — при
изменении конфигурации поды пересоздаются, иначе приложение продолжило бы
работать со старыми значениями.

Поды ходят с урезанными правами: `runAsNonRoot` с UID 1000, `drop: [ALL]`,
`allowPrivilegeEscalation: false`, `readOnlyRootFilesystem` и выключенный
`automountServiceAccountToken` — токен API приложению не нужен. Корень только
на чтение, поэтому под `/tmp` подмонтирован `emptyDir`: туда пишут и JVM
(`hsperfdata`), и само приложение при загрузке картинок.

Одно важное условие: **эти настройки требуют образа, собранного после правки
`logback-spring.xml`** в репозитории приложения. Проверено запуском образа
`main-36200c4` локально — под UID 1000 приложение падало на старте ещё до
Spring-контекста:

```text
RollingFileAppender[JSON_FILE] - openFile(logFile_IS_UNDEFINED,true) call failed.
java.io.FileNotFoundException: logFile_IS_UNDEFINED (Permission denied)
```

Свойства `logDir` и `logFile` в конфиге логирования были закомментированы,
поэтому `${logFile}` разворачивался в строку `logFile_IS_UNDEFINED`, и файловый
аппендер создавал файл с таким именем прямо в рабочем каталоге `/app`. От root
на writable-корне это проходило незаметно (и заодно мусорило в образ), а
непривилегированному пользователю каталог `/app` принадлежит root с правами
755 — записать туда нельзя. Теперь путь задан явно и по умолчанию ведёт в
`/tmp/bulletins-logs`, то есть в тот самый `emptyDir`; переопределяется
переменной `LOG_DIR`.

Если понадобится выкатить чарт на образ, собранный **до** этой правки,
хардненинг придётся ослабить:

```bash
helm upgrade --install bulletin-board k8s/bulletin-board -n bulletins \
  --set podSecurityContext.runAsNonRoot=false \
  --set podSecurityContext.runAsUser=0 \
  --set containerSecurityContext.readOnlyRootFilesystem=false
```

Куча памяти задаётся переменной `JAVA_TOOL_OPTIONS`, а не `JAVA_OPTS`.
`ENTRYPOINT` в образе приложения — exec-форма, переменные окружения в ней не
раскрываются, поэтому `JAVA_OPTS` до JVM не доезжал и куча молча оставалась
дефолтной (25% лимита, около 256 МиБ вместо заявленных 640).
`JAVA_TOOL_OPTIONS` JVM читает из окружения сама, править образ не нужно.

### Выкат и окружения

```bash
make deploy       # прод: ingress, HPA от 2 до 4 реплик, sidecar с метриками
make deploy-dev   # namespace bulletins-dev: 1 реплика, без ingress и HPA
```

В dev выключен и External Secrets, поэтому `bulletin-secret` там никто не
создаёт. Чтобы поды не вставали в `CreateContainerConfigError`, в
*values-dev.yaml* задан `secret.optional: true` — `envFrom.secretRef`
становится необязательным. Работать без доступов к базе и Object Storage dev
может потому, что там же переключён профиль: `SPRING_PROFILES_ACTIVE: dev`
поднимает H2 в памяти и локальное хранилище картинок. В проде
`secret.optional` остаётся `false` — молча стартовать без доступов приложение
не должно.

Выкат идёт с `--rollback-on-failure`: если поды не поднялись за таймаут, Helm
сам возвращает предыдущую ревизию.

Переопределить значения можно тремя способами — по возрастанию приоритета:

```bash
# 1. файл значений окружения
helm upgrade --install bulletin-board k8s/bulletin-board -n bulletins \
  -f k8s/bulletin-board/values-dev.yaml

# 2. отдельные ключи
helm upgrade --install bulletin-board k8s/bulletin-board -n bulletins \
  --set image.tag=main-36200c4 --set hpa.maxReplicas=6

# 3. и то и другое: --set перебивает значения из файлов
```

### Версия образа

В values зафиксирован конкретный тег `main-<sha>` — тот, что публикует CI
приложения на каждый push, а не `latest`. Причина простая: с `latest` выкат
невоспроизводим, а `helm rollback` не возвращает версию приложения — тег в
обеих ревизиях один и тот же, и Kubernetes остаётся на том образе, который уже
скачал. `pullPolicy` по той же причине `IfNotPresent`, а не `Always`:
фиксированный тег незачем перекачивать на каждый старт пода.

Выкат новой версии — это смена тега в *values.yaml* (или `--set` поверх):

```bash
helm upgrade --install bulletin-board k8s/bulletin-board -n bulletins \
  --set image.tag=main-<sha>
```

### Откаты

```bash
make helm-history   # список ревизий
make rollback       # вернуться на предыдущую ревизию
helm -n bulletins rollback bulletin-board 3   # на конкретную ревизию
```

Проверено на живом релизе: выкат `--set image.tag=main-36200c4` создал ревизию
2, `make rollback` вернул предыдущую ревизию вместе с её тегом образа.

## Секреты

Пароль базы и ключи Object Storage не хранятся ни в репозитории, ни в values
Helm. Они лежат в Yandex Lockbox (секрет `bulletins-319-app-secrets`, создаётся
Terraform вместе с базой и бакетом), а в кластер их приносит External Secrets
Operator.

```text
Terraform  ──создаёт──▶  Lockbox: SPRING_DATASOURCE_*, STORAGE_S3_*
                              │
                     читает   │  сервисный аккаунт bulletins-319-eso-sa
                              │  (роль lockbox.payloadViewer только на этот секрет)
                              ▼
External Secrets Operator ──▶ Secret bulletins/bulletin-secret ──▶ поды приложения
```

Установка:

```bash
make secrets-install   # оператор + ключ сервисного аккаунта в кластере
make deploy            # SecretStore и ExternalSecret из чарта
make secrets-status    # состояние синхронизации
```

Ключ сервисного аккаунта Terraform кладёт в вывод `eso_authorized_key`
(sensitive), а `make secrets-install` переносит его в Secret `yc-sa-key`.
Приватная часть живёт в состоянии Terraform — то есть в бакете, а не в git.

`ExternalSecret` использует `dataFrom.extract`, поэтому переносит все ключи
секрета Lockbox как есть: чтобы добавить новый параметр, достаточно положить
его в Lockbox, чарт править не нужно.

### Ротация

Проверено на живом стенде — смена пароля базы:

```bash
# 1. новый пароль в базе и в Lockbox
terraform -chdir=terraform apply -replace=random_password.db

# 2. не ждать час до планового обновления
kubectl -n bulletins annotate externalsecret bulletin-secret \
  force-sync=$(date +%s) --overwrite

# 3. приложение читает переменные при старте, поэтому нужен перевыкат
kubectl -n bulletins rollout restart deployment/bulletin-board
kubectl -n bulletins rollout status deployment/bulletin-board
```

Что произошло: Terraform сгенерировал новый пароль, применил его к пользователю
Managed PostgreSQL и записал новую версию секрета Lockbox. Оператор обновил
Kubernetes-секрет за секунды (в статусе `ExternalSecret` — `SecretSynced`).
Перевыкат прошёл штатной стратегией RollingUpdate: 137 запросов подряд во время
ротации — все `200`, простоя не было.

Третий шаг нужен потому, что переменные окружения из `secretRef` подставляются
в контейнер один раз при старте: обновление самого секрета в кластере
происходит автоматически, а вот подхватывает его приложение только при
перезапуске подов.

## Наблюдаемость

Метрики и логи уезжают в управляемые сервисы Yandex Cloud — отдельный стенд с
Prometheus и Grafana не поднимается.

### Логи

Логи подов собирает fluent-bit (DaemonSet в namespace `logging`) с плагином
Yandex Cloud Logging и складывает в лог-группу `bulletins-319-logs`. Срок
хранения — 7 суток (`logs_retention_period` в *terraform/variables.tf*).
Собираются только логи namespace `bulletins`: фильтр задан маской файлов
`/var/log/containers/*_bulletins_*.log`.

```bash
make logging-install   # DaemonSet + идентификатор лог-группы из Terraform
make logs-cloud        # последние 20 записей из Cloud Logging
```

Авторизации по ключам нет: агент представляется сервисным аккаунтом узла,
которому в *terraform/kubernetes.tf* выдана роль `logging.writer`.

Приложение пишет структурированный JSON, поэтому в fluent-bit включён
`Merge_Log` — поля `message` и `level` попадают в Cloud Logging как есть.
Указывать `Merge_Log_Key` при этом нельзя: из вложенного объекта плагин
сообщение не достаёт, и записи приезжают с пустым текстом.

### Метрики

| Что | Откуда | Сервис в Monitoring |
|---|---|---|
| Процессор, память, перезапуски подов | собирает сам Managed Kubernetes | `managed-kubernetes` |
| HTTP-запросы, задержки, JVM, логи по уровням | sidecar Unified Agent в поде приложения | `custom`, префикс `bulletins.` |

Sidecar с метриками входит в чарт и разворачивается вместе с приложением
(`make deploy`) — его ConfigMap описан в *templates/unified-agent-config.yaml*,
идентификатор каталога подставляется из вывода Terraform `folder_id`. Если
метрики выключали (`metricsAgent.enabled=false`), вернуть их на уже
развёрнутом релизе можно командой `make monitoring-install`.

Агент ездит sidecar-контейнером, а не отдельным Deployment: иначе он опрашивал
бы приложение через Service, и метрики двух реплик перемешивались бы. Метки
`pod` и `node` на метрики вешает само приложение через
`MANAGEMENT_METRICS_TAGS_*` — Micrometer добавляет их ко всем сериям.

Две вещи, на которые ушло время и которые стоит помнить:

- В Monitoring метка `name` зарезервирована под имя метрики. Группы
  `executor_*` и `jdbc_connections_*` используют её в своих данных, из-за чего
  агент отбраковывал **весь** батч. Обе группы выключены в ConfigMap
  приложения.
- Unified Agent отдаёт счётчики Prometheus уже дельтами за интервал сбора,
  поэтому `rate()` в запросах не нужен — с ним графики остаются пустыми.

### Дашборд

Дашборд `bulletins-319-dashboard` описан в *terraform/observability.tf* и
создаётся вместе с инфраструктурой. Открыть:
[Yandex Monitoring → Дашборды → Доска объявлений](https://monitoring.yandex.cloud/folders/b1glbnnomnf50r9g8kef/dashboards/bulletins-319-dashboard).

Восемь графиков: запросы по статусам, средняя задержка, ответы 5xx, записи в
логах по уровням, процессор и память подов, использование лимита памяти,
перезапуски контейнеров.

![Дашборд: запросы, задержки, логи](assets/monitoring-dashboard-top.jpg)

![Дашборд: ресурсы подов](assets/monitoring-dashboard-resources.jpg)

### Алерты

Terraform-ресурса и публичного API для алертов у Monitoring нет, поэтому они
заведены в консоли. Параметры для воспроизведения:

| Алерт | Запрос | Агрегация | Warning | Alarm |
|---|---|---|---|---|
| `bulletins-319-5xx` | `series_sum("bulletins.http_server_requests_seconds_count"{service="custom", application="bulletins", status="5*"})` | Сумма | 1 | 10 |
| `bulletins-319-latency` | `series_sum("bulletins.http_server_requests_seconds_sum"{…}) / series_sum("bulletins.http_server_requests_seconds_count"{…})` | Среднее | 0.5 | 1 |
| `bulletins-319-restarts` | `series_sum("container.restart_count"{service="managed-kubernetes", namespace="bulletins"})` | Максимум | 3 | 5 |

Во всех трёх окно вычисления 5 минут, задержка 30 секунд, сравнение «Больше».

![Алерты](assets/monitoring-alerts.jpg)

## Terraform

Конфигурация лежит в *terraform/* и разбита по смыслу:

| Файл | Что описывает |
|---|---|
| `versions.tf` | версии Terraform и провайдеров |
| `providers.tf` | провайдер Yandex Cloud и способ аутентификации |
| `backend.tf` | хранение состояния в Object Storage |
| `variables.tf` | все параметры инфраструктуры |
| `locals.tf` | строка подключения к базе и параметры S3 |
| `main.tf` | сеть, подсеть, NAT, публичный адрес — точка входа модуля |
| `network.tf` | security-группы кластера и базы |
| `kubernetes.tf` | сервисные аккаунты, кластер, группа узлов |
| `database.tf` | Managed PostgreSQL, база и пользователь |
| `storage.tf` | бакет для картинок и ключи доступа к нему |
| `lockbox.tf` | секрет с доступами приложения и аккаунт для External Secrets |
| `observability.tf` | лог-группа Cloud Logging и дашборд Monitoring |
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

### Доступы и права

**API мастера.** Порты 6443 и 443 открыты для `admin_cidr_blocks`. По
умолчанию там `0.0.0.0/0` — чтобы кластер поднимался из коробки, — но для
любого живого стенда адрес нужно сузить до своего:

```hcl
# terraform/terraform.tfvars
admin_cidr_blocks = ["203.0.113.10/32"]   # свой адрес: curl -s ifconfig.me
```

Диапазон NodePort (30000–32767) остаётся открытым: через него сетевой
балансировщик отдаёт трафик на узлы, и сузить его нельзя. Побочный эффект
стоит держать в голове — публичным становится любой NodePort-сервис кластера,
а не только ingress.

**Object Storage.** Аккаунту приложения выдана роль `storage.uploader` на
каталог — она нужна только для того, чтобы статический ключ вообще
аутентифицировался в S3 API. Что именно ему можно, ограничивает политика
самого бакета (`yandex_storage_bucket_policy`): чтение, запись и удаление
объектов в `bulletins-319-media` и ничего больше. Раньше здесь стоял
`storage.editor` на весь каталог, то есть полный доступ ко всем бакетам
проекта. Сам бакет создаёт Terraform своими правами, а не ключом приложения —
иначе аккаунту пришлось бы оставлять право заводить бакеты.

Это тот же принцип, что и с Lockbox: `lockbox.payloadViewer` там выдан на
конкретный секрет, а не на каталог.

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
make lint   # terraform fmt -check, tflint, helm lint + helm template
make test   # terraform init -backend=false + terraform validate
```

## Структура репозитория

```text
.
├── assets/                      # скриншоты дашборда и алертов
├── bin/tf-bootstrap.sh          # разовая подготовка бакета для состояния
├── k8s/
│   ├── bulletin-board/          # Helm-чарт приложения (в т.ч. sidecar метрик)
│   ├── logging/                 # fluent-bit для Cloud Logging
│   ├── ingress-nginx-values.yaml # values для чарта ingress-контроллера
│   └── secret.example.yaml      # образец секрета, реальные значения не в git
├── terraform/                   # инфраструктура Yandex Cloud
├── docker-compose.yaml          # локальный прогон приложения
├── Makefile                     # все команды проекта
└── README.md
```
