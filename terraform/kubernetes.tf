resource "yandex_iam_service_account" "k8s" {
  name        = "${var.project_name}-k8s-sa"
  description = "Сервисный аккаунт кластера Kubernetes"
}

resource "yandex_resourcemanager_folder_iam_member" "k8s_agent" {
  folder_id = var.folder_id
  role      = "k8s.clusters.agent"
  member    = "serviceAccount:${yandex_iam_service_account.k8s.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "k8s_lb_admin" {
  folder_id = var.folder_id
  role      = "load-balancer.admin"
  member    = "serviceAccount:${yandex_iam_service_account.k8s.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "k8s_public_admin" {
  folder_id = var.folder_id
  role      = "vpc.publicAdmin"
  member    = "serviceAccount:${yandex_iam_service_account.k8s.id}"
}

resource "yandex_iam_service_account" "nodes" {
  name        = "${var.project_name}-nodes-sa"
  description = "Сервисный аккаунт узлов кластера"
}

resource "yandex_resourcemanager_folder_iam_member" "nodes_images_puller" {
  folder_id = var.folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.nodes.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "nodes_monitoring_editor" {
  folder_id = var.folder_id
  role      = "monitoring.editor"
  member    = "serviceAccount:${yandex_iam_service_account.nodes.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "nodes_logging_writer" {
  folder_id = var.folder_id
  role      = "logging.writer"
  member    = "serviceAccount:${yandex_iam_service_account.nodes.id}"
}

resource "yandex_kubernetes_cluster" "main" {
  name        = "${var.project_name}-k8s"
  description = "Кластер приложения «доска объявлений»"

  network_id      = yandex_vpc_network.main.id
  release_channel = var.k8s_release_channel

  cluster_ipv4_range = var.cluster_ipv4_range
  service_ipv4_range = var.service_ipv4_range

  master {
    version = var.k8s_version

    zonal {
      zone      = var.zone
      subnet_id = yandex_vpc_subnet.main.id
    }

    public_ip          = true
    security_group_ids = [yandex_vpc_security_group.k8s.id]

    maintenance_policy {
      auto_upgrade = true

      maintenance_window {
        start_time = "22:00"
        duration   = "3h"
      }
    }
  }

  service_account_id      = yandex_iam_service_account.k8s.id
  node_service_account_id = yandex_iam_service_account.nodes.id

  depends_on = [
    yandex_resourcemanager_folder_iam_member.k8s_agent,
    yandex_resourcemanager_folder_iam_member.k8s_lb_admin,
    yandex_resourcemanager_folder_iam_member.k8s_public_admin,
    yandex_resourcemanager_folder_iam_member.nodes_images_puller,
  ]
}

resource "yandex_kubernetes_node_group" "main" {
  cluster_id  = yandex_kubernetes_cluster.main.id
  name        = "${var.project_name}-ng"
  description = "Рабочие узлы приложения"
  version     = var.k8s_version

  scale_policy {
    fixed_scale {
      size = var.node_count
    }
  }

  allocation_policy {
    location {
      zone = var.zone
    }
  }

  instance_template {
    platform_id = "standard-v3"

    network_interface {
      subnet_ids         = [yandex_vpc_subnet.main.id]
      nat                = false
      security_group_ids = [yandex_vpc_security_group.k8s.id]
    }

    resources {
      cores         = var.node_cores
      core_fraction = var.node_core_fraction
      memory        = var.node_memory
    }

    boot_disk {
      type = var.node_disk_type
      size = var.node_disk_size
    }

    scheduling_policy {
      preemptible = var.node_preemptible
    }

    container_runtime {
      type = "containerd"
    }
  }

  deploy_policy {
    max_expansion   = 1
    max_unavailable = 0
  }

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true

    maintenance_window {
      day        = "monday"
      start_time = "22:00"
      duration   = "3h"
    }
  }
}
