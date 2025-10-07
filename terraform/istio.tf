# Istio Service Mesh Configuration for AEIMS
# Provides advanced traffic management, security, and observability

# Note: Providers are configured in main.tf

# Create Istio namespace
resource "kubernetes_namespace" "istio_system" {
  count = var.enable_service_mesh ? 1 : 0

  metadata {
    name = "istio-system"
    labels = {
      "istio-injection" = "disabled"
    }
  }
}

# Install Istio base components
resource "helm_release" "istio_base" {
  count = var.enable_service_mesh ? 1 : 0

  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  namespace  = kubernetes_namespace.istio_system[0].metadata[0].name
  version    = var.istio_version

  depends_on = [kubernetes_namespace.istio_system]
}

# Install Istiod (control plane)
resource "helm_release" "istiod" {
  count = var.enable_service_mesh ? 1 : 0

  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = kubernetes_namespace.istio_system[0].metadata[0].name
  version    = var.istio_version

  values = [
    yamlencode({
      global = {
        meshID  = "aeims-mesh"
        cluster = "aeims-cluster"
        network = "aeims-network"
      }
      pilot = {
        traceSampling = var.environment == "prod" ? 1.0 : 100.0
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }
    })
  ]

  depends_on = [helm_release.istio_base]
}

# Install Istio Gateway
resource "helm_release" "istio_gateway" {
  count = var.enable_service_mesh ? 1 : 0

  name       = "istio-gateway"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  namespace  = "istio-ingress"
  version    = var.istio_version

  create_namespace = true

  values = [
    yamlencode({
      service = {
        type = "LoadBalancer"
        ports = [
          {
            name       = "http"
            port       = 80
            protocol   = "TCP"
            targetPort = 8080
          },
          {
            name       = "https"
            port       = 443
            protocol   = "TCP"
            targetPort = 8443
          }
        ]
      }
    })
  ]

  depends_on = [helm_release.istiod]
}

# AEIMS namespace with Istio injection
resource "kubernetes_namespace" "aeims" {
  count = var.enable_service_mesh ? 1 : 0

  metadata {
    name = "aeims"
    labels = {
      "istio-injection" = "enabled"
    }
  }
}

# Virtual Service for AEIMS routing
resource "kubernetes_manifest" "aeims_virtual_service" {
  count = var.enable_service_mesh ? 1 : 0

  manifest = {
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "VirtualService"
    metadata = {
      name      = "aeims-vs"
      namespace = kubernetes_namespace.aeims[0].metadata[0].name
    }
    spec = {
      hosts    = ["*"]
      gateways = ["aeims-gateway"]
      http = [
        {
          match = [
            {
              uri = {
                prefix = "/api/"
              }
            }
          ]
          route = [
            {
              destination = {
                host = "aeims-core"
                port = {
                  number = 8000
                }
              }
            }
          ]
          timeout = "30s"
          retries = {
            attempts      = 3
            perTryTimeout = "10s"
            retryOn       = "5xx,reset,connect-failure,refused-stream"
          }
        },
        {
          match = [
            {
              uri = {
                prefix = "/ws/"
              }
            }
          ]
          route = [
            {
              destination = {
                host = "aeims-lib"
                port = {
                  number = 8080
                }
              }
            }
          ]
          timeout = "0s" # WebSocket connections
        },
        {
          match = [
            {
              uri = {
                prefix = "/admin/"
              }
            }
          ]
          route = [
            {
              destination = {
                host = "aeims-app"
                port = {
                  number = 80
                }
              }
            }
          ]
        },
        {
          route = [
            {
              destination = {
                host = "aeims-app"
                port = {
                  number = 80
                }
              }
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_namespace.aeims]
}

# Gateway configuration
resource "kubernetes_manifest" "aeims_gateway" {
  count = var.enable_service_mesh ? 1 : 0

  manifest = {
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "Gateway"
    metadata = {
      name      = "aeims-gateway"
      namespace = kubernetes_namespace.aeims[0].metadata[0].name
    }
    spec = {
      selector = {
        istio = "gateway"
      }
      servers = [
        {
          port = {
            number   = 80
            name     = "http"
            protocol = "HTTP"
          }
          hosts = ["*"]
          tls = {
            httpsRedirect = var.enable_https_redirect
          }
        },
        {
          port = {
            number   = 443
            name     = "https"
            protocol = "HTTPS"
          }
          hosts = ["*"]
          tls = {
            mode           = "SIMPLE"
            credentialName = var.tls_secret_name
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_namespace.aeims]
}

# Destination Rules for circuit breaking and load balancing
resource "kubernetes_manifest" "aeims_core_destination_rule" {
  count = var.enable_service_mesh ? 1 : 0

  manifest = {
    apiVersion = "networking.istio.io/v1beta1"
    kind       = "DestinationRule"
    metadata = {
      name      = "aeims-core-dr"
      namespace = kubernetes_namespace.aeims[0].metadata[0].name
    }
    spec = {
      host = "aeims-core"
      trafficPolicy = {
        connectionPool = {
          tcp = {
            maxConnections = 100
            connectTimeout = "30s"
          }
          http = {
            http1MaxPendingRequests  = 50
            maxRequestsPerConnection = 10
            maxRetries               = 3
            consecutiveGatewayErrors = 5
            interval                 = "30s"
            baseEjectionTime         = "30s"
          }
        }
        circuitBreaker = {
          consecutiveGatewayErrors = 5
          interval                 = "30s"
          baseEjectionTime         = "30s"
          maxEjectionPercent       = 50
        }
        loadBalancer = {
          simple = "LEAST_CONN"
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.aeims]
}

# Service Monitor for Prometheus integration
resource "kubernetes_manifest" "istio_service_monitor" {
  count = var.enable_service_mesh && var.enable_monitoring ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "istio-mesh"
      namespace = kubernetes_namespace.istio_system[0].metadata[0].name
      labels = {
        app = "istio-proxy"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "istio-proxy"
        }
      }
      endpoints = [
        {
          port     = "http-monitoring"
          interval = "15s"
          path     = "/stats/prometheus"
        }
      ]
    }
  }

  depends_on = [helm_release.istiod]
}

# Peer Authentication for mTLS
resource "kubernetes_manifest" "aeims_peer_authentication" {
  count = var.enable_service_mesh ? 1 : 0

  manifest = {
    apiVersion = "security.istio.io/v1beta1"
    kind       = "PeerAuthentication"
    metadata = {
      name      = "aeims-mtls"
      namespace = kubernetes_namespace.aeims[0].metadata[0].name
    }
    spec = {
      mtls = {
        mode = var.environment == "prod" ? "STRICT" : "PERMISSIVE"
      }
    }
  }

  depends_on = [kubernetes_namespace.aeims]
}

# Authorization Policy
resource "kubernetes_manifest" "aeims_authorization_policy" {
  count = var.enable_service_mesh ? 1 : 0

  manifest = {
    apiVersion = "security.istio.io/v1beta1"
    kind       = "AuthorizationPolicy"
    metadata = {
      name      = "aeims-authz"
      namespace = kubernetes_namespace.aeims[0].metadata[0].name
    }
    spec = {
      selector = {
        matchLabels = {
          app = "aeims-core"
        }
      }
      rules = [
        {
          from = [
            {
              source = {
                principals = ["cluster.local/ns/aeims/sa/aeims-app"]
              }
            }
          ]
          to = [
            {
              operation = {
                methods = ["GET", "POST"]
                paths   = ["/api/*"]
              }
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_namespace.aeims]
}

# Telemetry configuration
resource "kubernetes_manifest" "aeims_telemetry" {
  count = var.enable_service_mesh ? 1 : 0

  manifest = {
    apiVersion = "telemetry.istio.io/v1alpha1"
    kind       = "Telemetry"
    metadata = {
      name      = "aeims-telemetry"
      namespace = kubernetes_namespace.aeims[0].metadata[0].name
    }
    spec = {
      metrics = [
        {
          providers = [
            {
              name = "prometheus"
            }
          ]
          overrides = [
            {
              match = {
                metric = "ALL_METRICS"
              }
              tagOverrides = {
                destination_service_name = {
                  value = "%%{DESTINATION_SERVICE_NAME}"
                }
                source_app = {
                  value = "%%{SOURCE_APP}"
                }
              }
            }
          ]
        }
      ]
      tracing = [
        {
          providers = [
            {
              name = "jaeger"
            }
          ]
        }
      ]
      accessLogging = [
        {
          providers = [
            {
              name = "otel"
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_namespace.aeims]
}

# Variables for Istio configuration
variable "enable_service_mesh" {
  description = "Enable Istio service mesh"
  type        = bool
  default     = true
}

variable "istio_version" {
  description = "Istio version to install"
  type        = string
  default     = "1.19.0"
}

variable "enable_https_redirect" {
  description = "Enable HTTPS redirect"
  type        = bool
  default     = true
}

variable "tls_secret_name" {
  description = "TLS secret name for HTTPS"
  type        = string
  default     = "aeims-tls"
}

# Outputs
output "istio_gateway_ip" {
  description = "Istio Gateway external IP"
  value       = var.enable_service_mesh ? kubernetes_manifest.aeims_gateway[0].manifest.status.loadBalancer.ingress[0].ip : null
}

output "istio_namespace" {
  description = "Istio system namespace"
  value       = var.enable_service_mesh ? kubernetes_namespace.istio_system[0].metadata[0].name : null
}
