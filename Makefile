TF_DIR := terraform
BACKEND_CREDENTIALS := $(TF_DIR)/.backend-credentials

.PHONY: tf-bootstrap tf-init tf-plan tf-apply tf-destroy tf-output \
	tf-fmt tf-validate tf-lint kubeconfig lint test

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
