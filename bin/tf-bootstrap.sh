#!/usr/bin/env bash
set -euo pipefail

SA_NAME="${SA_NAME:-bulletins-319-tfstate-sa}"
BUCKET="${BUCKET:-bulletins-319-tfstate}"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-terraform/.backend-credentials}"

FOLDER_ID="$(yc config get folder-id)"
echo "Каталог: ${FOLDER_ID}"

if yc iam service-account get --name "${SA_NAME}" >/dev/null 2>&1; then
  echo "Сервисный аккаунт ${SA_NAME} уже есть"
else
  echo "Создаю сервисный аккаунт ${SA_NAME}"
  yc iam service-account create \
    --name "${SA_NAME}" \
    --description "Доступ Terraform к бакету с состоянием" >/dev/null
fi

SA_ID="$(yc iam service-account get --name "${SA_NAME}" --format json | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
echo "Идентификатор аккаунта: ${SA_ID}"

echo "Назначаю роль storage.editor"
yc resource-manager folder add-access-binding "${FOLDER_ID}" \
  --role storage.editor \
  --service-account-id "${SA_ID}" >/dev/null 2>&1 || true

if [ -f "${CREDENTIALS_FILE}" ]; then
  echo "Ключ доступа уже сохранён в ${CREDENTIALS_FILE}, новый не создаю"
else
  echo "Создаю статический ключ доступа"
  KEY_JSON="$(yc iam access-key create \
    --service-account-id "${SA_ID}" \
    --description "Доступ Terraform к бакету с состоянием" \
    --format json)"

  mkdir -p "$(dirname "${CREDENTIALS_FILE}")"
  KEY_JSON="${KEY_JSON}" python3 -c '
import json, os, sys

data = json.loads(os.environ["KEY_JSON"])
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    handle.write("export AWS_ACCESS_KEY_ID=%s\n" % data["access_key"]["key_id"])
    handle.write("export AWS_SECRET_ACCESS_KEY=%s\n" % data["secret"])
' "${CREDENTIALS_FILE}"
  chmod 600 "${CREDENTIALS_FILE}"
  echo "Ключ сохранён в ${CREDENTIALS_FILE} (файл в .gitignore)"
fi

if yc storage bucket get "${BUCKET}" >/dev/null 2>&1; then
  echo "Бакет ${BUCKET} уже есть"
else
  echo "Создаю бакет ${BUCKET}"
  yc storage bucket create "${BUCKET}" >/dev/null
fi

yc storage bucket update "${BUCKET}" --versioning versioning-enabled >/dev/null 2>&1 \
  || echo "Не удалось включить версионирование — включите вручную в консоли"

echo
echo "Готово. Дальше:"
echo "  make tf-init"
