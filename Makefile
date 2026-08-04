TF_DIR := terraform
BACKEND_CREDENTIALS := $(TF_DIR)/.backend-credentials
NAMESPACE := bulletins

.PHONY: tf-bootstrap tf-init tf-plan tf-apply tf-destroy tf-output \
	tf-fmt tf-validate tf-lint kubeconfig lint test \
	k8s-secret k8s-apply k8s-status k8s-forward k8s-logs k8s-rollout \
	ingress-install ingress-ip smoke

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

lint: tf-lint
	terraform fmt -check -recursive $(TF_DIR)

test: tf-validate

# --- Кластер -----------------------------------------------------------------

# Записывает kubeconfig текущего кластера в ~/.kube/config.
kubeconfig:
	$(tf_env) && yc managed-kubernetes cluster get-credentials \
		--id "$$(terraform -chdir=$(TF_DIR) output -raw k8s_cluster_id)" --external --force

# --- Приложение --------------------------------------------------------------

# Секрет собирается из выводов Terraform и в репозиторий не попадает.
k8s-secret:
	kubectl apply -f k8s/manifests/00-namespace.yaml
	$(tf_env) && kubectl -n $(NAMESPACE) create secret generic bulletin-secret \
		--from-literal=SPRING_DATASOURCE_URL="$$(terraform -chdir=$(TF_DIR) output -raw db_url)" \
		--from-literal=SPRING_DATASOURCE_USERNAME="$$(terraform -chdir=$(TF_DIR) output -raw db_user)" \
		--from-literal=SPRING_DATASOURCE_PASSWORD="$$(terraform -chdir=$(TF_DIR) output -raw db_password)" \
		--from-literal=STORAGE_S3_ACCESSKEY="$$(terraform -chdir=$(TF_DIR) output -raw storage_access_key)" \
		--from-literal=STORAGE_S3_SECRETKEY="$$(terraform -chdir=$(TF_DIR) output -raw storage_secret_key)" \
		--dry-run=client -o yaml | kubectl apply -f -

k8s-apply:
	kubectl apply -f k8s/manifests/

k8s-status:
	kubectl -n $(NAMESPACE) get deploy,pods,svc -o wide

k8s-rollout:
	kubectl -n $(NAMESPACE) rollout status deployment/bulletin-board

k8s-logs:
	kubectl -n $(NAMESPACE) logs -l app=bulletin-board --tail 100 -f

# Проверка приложения без внешнего доступа.
k8s-forward:
	kubectl -n $(NAMESPACE) port-forward svc/bulletin-board 8080:80

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

# Быстрая проверка живости через публичный адрес.
smoke:
	@$(tf_env) && ip="$$(terraform -chdir=$(TF_DIR) output -raw ingress_ip)" && \
		curl -sS -o /dev/null -w 'GET / -> %{http_code}\n' "http://$$ip/" && \
		curl -sS -o /dev/null -w 'GET /api/bulletins -> %{http_code}\n' "http://$$ip/api/bulletins"
