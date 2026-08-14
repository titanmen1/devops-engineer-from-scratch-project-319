# Полное удаление инфраструктуры проекта 319 в Yandex Cloud

## Цель

Снести весь контур проекта в Yandex Cloud вместе с бакетом состояния Terraform,
чтобы каталог не тратил деньги. После этой процедуры контур поднимается только
с нуля через `make tf-bootstrap`.

## Предусловия

- `yc` настроен на нужное облако и каталог: `yc config list`
- `terraform`, `helm`, `kubectl`, `aws` (CLI нужен для работы с версиями объектов —
  `yc storage s3api` не умеет `list-object-versions`)
- `terraform/.backend-credentials` на месте: без него не открыть backend
- Доступ к кластеру: `make kubeconfig`

Проверить, что удаляется именно то, что нужно:

```bash
terraform -chdir=terraform state list
yc storage bucket list
```

## Шаги

### 1. Снять ingress-контроллер

Обязательно **до** `terraform destroy`. Сервис типа LoadBalancer держит сетевой
балансировщик Yandex Cloud, созданный не Terraform, а контроллером. Если его не
убрать, балансировщик остаётся висеть и мешает удалять сеть.

```bash
helm uninstall ingress-nginx -n ingress-nginx --wait --timeout 5m
kubectl get svc -A --field-selector spec.type=LoadBalancer   # ожидаем: No resources found
```

### 2. Опустошить бакет с картинками

Terraform не удаляет непустой бакет (`force_destroy` в конфиге не включён).

```bash
for k in $(yc storage s3api list-objects --bucket bulletins-319-media | awk '/key:/ {print $3}'); do
  yc storage s3api delete-object --bucket bulletins-319-media --key "$k"
done
yc storage s3api list-objects --bucket bulletins-319-media | grep -c 'key:'   # ожидаем: 0
```

Версионирование на этом бакете выключено, поэтому обычного удаления достаточно.

### 3. Удалить ресурсы Terraform

```bash
make tf-destroy   # либо terraform -chdir=terraform destroy -auto-approve
```

Занимает 10–15 минут, дольше всего удаляется кластер Kubernetes. Ожидаемый
вывод в конце: `Destroy complete! Resources: 32 destroyed.`

### 4. Опустошить и удалить бакет состояния

Бакет `bulletins-319-tfstate` создан скриптом `bin/tf-bootstrap.sh`, а не
Terraform, поэтому переживает `destroy`. Версионирование на нём **включено**, и
удалять надо именно версии объектов, а не объекты.

```bash
. ./terraform/.backend-credentials
export AWS_DEFAULT_REGION=ru-central1
EP=https://storage.yandexcloud.net

aws --endpoint-url=$EP s3api list-object-versions --bucket bulletins-319-tfstate \
  --query 'Versions[].{Key:Key,VersionId:VersionId}' --output json > /tmp/vers.json

python3 -c 'import json; v=json.load(open("/tmp/vers.json")); json.dump({"Objects":v,"Quiet":True},open("/tmp/del.json","w"))'

aws --endpoint-url=$EP s3api delete-objects --bucket bulletins-319-tfstate --delete file:///tmp/del.json
aws --endpoint-url=$EP s3api list-object-versions --bucket bulletins-319-tfstate \
  --query 'length(Versions||`[]`)'   # ожидаем: 0

yc storage bucket delete bulletins-319-tfstate
```

### 5. Удалить сервисный аккаунт bootstrap

```bash
SA_ID="$(yc iam service-account get --name bulletins-319-tfstate-sa --format json \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"

yc resource-manager folder remove-access-binding "$(yc config get folder-id)" \
  --role storage.editor --service-account-id "$SA_ID"
yc iam service-account delete --id "$SA_ID"
```

### 6. Почистить локальное окружение

```bash
kubectl config delete-context yc-bulletins-319-k8s
```

## Проверка

Ни одна из команд не должна показывать ресурсов проекта 319:

```bash
yc managed-kubernetes cluster list
yc managed-postgresql cluster list
yc storage bucket list          # остаются только чужие бакеты
yc vpc network list             # остаётся только default
yc iam service-account list     # не должно быть bulletins-319-*
```

## Грабли

- **`yc storage s3api` не умеет `list-object-versions`.** На бакете с включённым
  версионированием `yc storage bucket delete` падает с
  `The bucket you tried to delete is not empty`, даже когда `list-objects` пусто:
  живы старые версии. Помогает только `aws` CLI с `--endpoint-url`.
- **Ingress-контроллер надо снимать вручную и первым.** Балансировщик заводит
  контроллер, Terraform про него не знает и в `destroy` не учитывает.
- **`bin/tf-bootstrap.sh` не пересоздаёт ключ, если файл
  `terraform/.backend-credentials` существует** (проверка на строке 28). После
  удаления сервисного аккаунта ключи в файле мертвы, и повторный bootstrap молча
  оставит нерабочие. Перед новым разворачиванием файл нужно удалить.
- Бакет `bulletins-318-media` принадлежит другому проекту — не трогать.

## Откат

Отката нет: удалены и данные, и состояние Terraform. Контур поднимается заново
с нуля, порядок — в README, раздел «Развёртывание с нуля»:

```bash
rm -f terraform/.backend-credentials   # иначе bootstrap оставит мёртвые ключи
make tf-bootstrap && make tf-init && make tf-apply
```

Пароль базы и ключи доступа будут сгенерированы новые. Картинки объявлений,
лежавшие в `bulletins-319-media`, восстановлению не подлежат.
