TF_DIR := terraform
BACKEND_CREDENTIALS := $(TF_DIR)/.backend-credentials
NAMESPACE := bulletins
CHART := k8s/bulletin-board
RELEASE := bulletin-board
APP_SECRET := bulletin-secret

.PHONY: tf-bootstrap tf-init tf-plan tf-apply tf-destroy tf-output \
	tf-fmt tf-validate tf-lint kubeconfig lint test \
	k8s-secret k8s-status k8s-forward k8s-logs k8s-rollout \
	deploy deploy-dev rollback helm-history helm-lint uninstall \
	secrets-install secrets-status \
	ingress-install ingress-ip smoke logging-install logs-cloud monitoring-install

# Доступы к бакету с состоянием и параметры облака подставляются в окружение
# каждой команды Terraform: в репозитории их нет, а IAM-токен живёт 12 часов и
# запрашивается заново на каждый запуск.
define tf_env
. ./$(BACKEND_CREDENTIALS) && \
export TF_VAR_cloud_id="$$(yc config get cloud-id)" && \
export TF_VAR_folder_id="$$(yc config get folder-id)" && \
export TF_VAR_yc_token="$$(yc iam create-token)"
endef

# --- Terraform ---------------------------------------------------------------

# Разовая подготовка: сервисный аккаунт, ключ доступа и бакет для состояния.
tf-bootstrap:
	./bin/tf-bootstrap.sh

tf-init:
	$(tf_env) && terraform -chdir=$(TF_DIR) init

tf-plan:
	$(tf_env) && terraform -chdir=$(TF_DIR) plan

tf-apply:
	$(tf_env) && terraform -chdir=$(TF_DIR) apply

tf-destroy:
	$(tf_env) && terraform -chdir=$(TF_DIR) destroy

tf-output:
	$(tf_env) && terraform -chdir=$(TF_DIR) output

# --- Проверки ----------------------------------------------------------------

tf-fmt:
	terraform fmt -recursive $(TF_DIR)

# Валидация идёт в отдельном TF_DATA_DIR: иначе init -backend=false подхватит
# закешированную конфигурацию бэкенда и потребует ключи доступа к бакету.
tf-validate:
	TF_DATA_DIR=.terraform-validate terraform -chdir=$(TF_DIR) init -backend=false -input=false
	TF_DATA_DIR=.terraform-validate terraform -chdir=$(TF_DIR) validate

tf-lint:
	tflint --config $(CURDIR)/.tflint.hcl --recursive --chdir=$(TF_DIR)

lint: tf-lint helm-lint
	terraform fmt -check -recursive $(TF_DIR)

test: tf-validate

# --- Кластер -----------------------------------------------------------------

# Записывает kubeconfig текущего кластера в ~/.kube/config.
kubeconfig:
	$(tf_env) && yc managed-kubernetes cluster get-credentials \
		--id "$$(terraform -chdir=$(TF_DIR) output -raw k8s_cluster_id)" --external --force

# --- Приложение --------------------------------------------------------------

# Секрет собирается из выводов Terraform и в репозиторий не попадает.
# После шага 70 его наполняет External Secrets Operator из Lockbox.
k8s-secret:
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	$(tf_env) && kubectl -n $(NAMESPACE) create secret generic bulletin-secret \
		--from-literal=SPRING_DATASOURCE_URL="$$(terraform -chdir=$(TF_DIR) output -raw db_url)" \
		--from-literal=SPRING_DATASOURCE_USERNAME="$$(terraform -chdir=$(TF_DIR) output -raw db_user)" \
		--from-literal=SPRING_DATASOURCE_PASSWORD="$$(terraform -chdir=$(TF_DIR) output -raw db_password)" \
		--from-literal=STORAGE_S3_ACCESSKEY="$$(terraform -chdir=$(TF_DIR) output -raw storage_access_key)" \
		--from-literal=STORAGE_S3_SECRETKEY="$$(terraform -chdir=$(TF_DIR) output -raw storage_secret_key)" \
		--dry-run=client -o yaml | kubectl apply -f -

# Выкат чарта. При неудаче Helm сам возвращает предыдущую ревизию.
deploy:
	$(tf_env) && helm upgrade --install $(RELEASE) $(CHART) \
		--namespace $(NAMESPACE) --create-namespace \
		--set externalSecrets.lockboxSecretId="$$(terraform -chdir=$(TF_DIR) output -raw lockbox_secret_id)" \
		--rollback-on-failure --timeout 10m

# Второе окружение: одна реплика, без ingress, HPA и sidecar с метриками.
deploy-dev:
	helm upgrade --install $(RELEASE)-dev $(CHART) \
		--namespace $(NAMESPACE)-dev --create-namespace \
		-f $(CHART)/values-dev.yaml \
		--rollback-on-failure --timeout 10m

# Откат на предыдущую ревизию релиза.
rollback:
	helm -n $(NAMESPACE) rollback $(RELEASE)

helm-history:
	helm -n $(NAMESPACE) history $(RELEASE)

# Идентификатор секрета Lockbox обязателен в шаблоне, поэтому для проверки
# подставляем заглушку — в кластер этот рендер не уезжает.
helm-lint:
	helm lint $(CHART) --set externalSecrets.lockboxSecretId=lint
	helm template $(RELEASE) $(CHART) --set externalSecrets.lockboxSecretId=lint >/dev/null
	helm template $(RELEASE) $(CHART) -f $(CHART)/values-dev.yaml >/dev/null

uninstall:
	helm -n $(NAMESPACE) uninstall $(RELEASE)

k8s-status:
	kubectl -n $(NAMESPACE) get deploy,pods,svc,ingress,hpa,pdb -o wide

k8s-rollout:
	kubectl -n $(NAMESPACE) rollout status deployment/$(RELEASE)

k8s-logs:
	kubectl -n $(NAMESPACE) logs -l app=$(RELEASE) --tail 100 -f

# Проверка приложения без внешнего доступа.
k8s-forward:
	kubectl -n $(NAMESPACE) port-forward svc/$(RELEASE) 8080:80

# --- Секреты -----------------------------------------------------------------

# External Secrets Operator и ключ сервисного аккаунта для чтения Lockbox.
# После этого секрет приложения наполняется из Lockbox автоматически.
secrets-install:
	helm repo add external-secrets https://charts.external-secrets.io
	helm repo update external-secrets
	helm upgrade --install external-secrets external-secrets/external-secrets \
		--namespace external-secrets --create-namespace --wait --timeout 10m
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	$(tf_env) && kubectl -n $(NAMESPACE) create secret generic yc-sa-key \
		--from-literal=key.json="$$(terraform -chdir=$(TF_DIR) output -raw eso_authorized_key)" \
		--dry-run=client -o yaml | kubectl apply -f -

# Что оператор думает о секрете приложения.
secrets-status:
	kubectl -n $(NAMESPACE) get secretstore,externalsecret
	kubectl -n $(NAMESPACE) get secret $(APP_SECRET) -o jsonpath='{.metadata.annotations}' 2>/dev/null || true

# --- Внешний доступ ----------------------------------------------------------

# Контроллер занимает зарезервированный в Terraform публичный адрес.
ingress-install:
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
	helm repo update ingress-nginx
	$(tf_env) && helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
		--namespace ingress-nginx --create-namespace \
		-f k8s/ingress-nginx-values.yaml \
		--set controller.service.loadBalancerIP="$$(terraform -chdir=$(TF_DIR) output -raw ingress_ip)" \
		--wait --timeout 10m

ingress-ip:
	@$(tf_env) && terraform -chdir=$(TF_DIR) output -raw ingress_ip && echo

# --- Наблюдаемость -----------------------------------------------------------

# Идентификатор лог-группы приезжает из Terraform отдельным ConfigMap, чтобы
# сам манифест DaemonSet не зависел от конкретного окружения.
logging-install:
	kubectl apply -f k8s/logging/fluent-bit.yaml
	$(tf_env) && kubectl -n logging create configmap fluent-bit-target \
		--from-literal=log_group_id="$$(terraform -chdir=$(TF_DIR) output -raw log_group_id)" \
		--dry-run=client -o yaml | kubectl apply -f -
	kubectl -n logging rollout restart daemonset/fluent-bit
	kubectl -n logging rollout status daemonset/fluent-bit --timeout=5m

# Sidecar с метриками появляется в подах приложения после этой команды.
# Каталог подставляется в конфиг здесь: переменные окружения Unified Agent
# внутри конфига не раскрывает.
monitoring-install:
	$(tf_env) && sed "s|__FOLDER_ID__|$$(terraform -chdir=$(TF_DIR) output -raw folder_id)|" \
		k8s/monitoring/unified-agent.yml > /tmp/unified-agent.yml
	kubectl -n $(NAMESPACE) create configmap unified-agent-config \
		--from-file=config.yml=/tmp/unified-agent.yml \
		--dry-run=client -o yaml | kubectl apply -f -
	rm -f /tmp/unified-agent.yml
	kubectl -n $(NAMESPACE) rollout restart deployment/$(RELEASE)
	kubectl -n $(NAMESPACE) rollout status deployment/$(RELEASE) --timeout=10m

# Последние записи приложения из Cloud Logging.
logs-cloud:
	@$(tf_env) && yc logging read \
		--group-id "$$(terraform -chdir=$(TF_DIR) output -raw log_group_id)" --limit 20

# Быстрая проверка живости через публичный адрес.
smoke:
	@$(tf_env) && ip="$$(terraform -chdir=$(TF_DIR) output -raw ingress_ip)" && \
		curl -sS -o /dev/null -w 'GET / -> %{http_code}\n' "http://$$ip/" && \
		curl -sS -o /dev/null -w 'GET /api/bulletins -> %{http_code}\n' "http://$$ip/api/bulletins"
