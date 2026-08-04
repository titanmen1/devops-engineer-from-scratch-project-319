resource "yandex_logging_group" "app" {
  name             = "${var.project_name}-logs"
  description      = "Логи подов приложения «доска объявлений»"
  folder_id        = var.folder_id
  retention_period = var.logs_retention_period
}

locals {
  app_selector = "service=\"custom\", application=\"bulletins\""
  k8s_selector = "service=\"managed-kubernetes\", namespace=\"bulletins\""

  requests = "\"bulletins.http_server_requests_seconds_count\"{${local.app_selector}}"

  dashboard_queries = {
    requests   = "group_by_labels(${local.requests}, \"status\", v -> series_sum(v))"
    latency    = "series_sum(\"bulletins.http_server_requests_seconds_sum\"{${local.app_selector}}) / series_sum(${local.requests})"
    errors5xx  = "series_sum(\"bulletins.http_server_requests_seconds_count\"{${local.app_selector}, status=\"5*\"})"
    log_errors = "group_by_labels(\"bulletins.logback_events_total\"{${local.app_selector}}, \"level\", v -> series_sum(v))"
    pod_cpu    = "group_by_labels(\"pod.cpu.core_usage_time\"{${local.k8s_selector}}, \"pod\", v -> series_sum(v))"
    pod_memory = "group_by_labels(\"pod.memory.working_set_bytes\"{${local.k8s_selector}}, \"pod\", v -> series_sum(v))"
    mem_limit  = "group_by_labels(\"container.memory.limit_utilization\"{${local.k8s_selector}, container=\"app\"}, \"pod\", v -> series_sum(v))"
    restarts   = "group_by_labels(\"container.restart_count\"{${local.k8s_selector}}, \"pod\", v -> series_sum(v))"
  }
}

resource "yandex_monitoring_dashboard" "app" {
  name        = "${var.project_name}-dashboard"
  title       = "Доска объявлений"
  description = "Доступность, задержки и ресурсы приложения в Managed Kubernetes"
  folder_id   = var.folder_id

  widgets {
    position {
      x = 0
      y = 0
      w = 18
      h = 8
    }

    chart {
      chart_id       = "requests"
      title          = "Запросы по статусам, за интервал"
      display_legend = true

      queries {
        target {
          query = local.dashboard_queries.requests
        }
      }
    }
  }

  widgets {
    position {
      x = 18
      y = 0
      w = 18
      h = 8
    }

    chart {
      chart_id       = "latency"
      title          = "Средняя задержка ответа, с"
      display_legend = true

      queries {
        target {
          query = local.dashboard_queries.latency
        }
      }
    }
  }

  widgets {
    position {
      x = 0
      y = 8
      w = 18
      h = 8
    }

    chart {
      chart_id       = "errors-5xx"
      title          = "Ответы 5xx"
      display_legend = true

      queries {
        target {
          query = local.dashboard_queries.errors5xx
        }
      }
    }
  }

  widgets {
    position {
      x = 18
      y = 8
      w = 18
      h = 8
    }

    chart {
      chart_id       = "log-errors"
      title          = "Записи в логах по уровням"
      display_legend = true

      queries {
        target {
          query = local.dashboard_queries.log_errors
        }
      }
    }
  }

  widgets {
    position {
      x = 0
      y = 16
      w = 18
      h = 8
    }

    chart {
      chart_id       = "pod-cpu"
      title          = "Процессор подов, ядра"
      display_legend = true

      queries {
        target {
          query = local.dashboard_queries.pod_cpu
        }
      }
    }
  }

  widgets {
    position {
      x = 18
      y = 16
      w = 18
      h = 8
    }

    chart {
      chart_id       = "pod-memory"
      title          = "Память подов, байты"
      display_legend = true

      queries {
        target {
          query = local.dashboard_queries.pod_memory
        }
      }
    }
  }

  widgets {
    position {
      x = 0
      y = 24
      w = 18
      h = 8
    }

    chart {
      chart_id       = "memory-limit"
      title          = "Использование лимита памяти контейнером, доля"
      display_legend = true

      queries {
        target {
          query = local.dashboard_queries.mem_limit
        }
      }
    }
  }

  widgets {
    position {
      x = 18
      y = 24
      w = 18
      h = 8
    }

    chart {
      chart_id       = "restarts"
      title          = "Перезапуски контейнеров"
      display_legend = true

      queries {
        target {
          query = local.dashboard_queries.restarts
        }
      }
    }
  }
}
