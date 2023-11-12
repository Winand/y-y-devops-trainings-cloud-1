terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  service_account_key_file = "./authorized_key.json"
  folder_id                = var.folder_id
  zone                     = "ru-central1-a"
}

/* Конфигурация ресурсов */

resource "yandex_vpc_network" "foo" {
  // Requires 'vpc.privateAdmin' role https://cloud.yandex.ru/docs/vpc/security
}

resource "yandex_vpc_subnet" "foo" {
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.foo.id
  v4_cidr_blocks = ["10.5.0.0/24"]
}

resource "yandex_container_registry" "registry1" {
  name = "registry1"
}

variable "folder_id" {
  type = string
}

locals {
  service-accounts = toset([
    "catgpt-sa",
  ])
  catgpt-sa-roles = toset([
    "container-registry.images.puller",
    "monitoring.editor",
  ])
}
resource "yandex_iam_service_account" "service-accounts" {
  // Requires 'iam.serviceAccounts.admin' role https://cloud.yandex.ru/docs/iam/security
  for_each = local.service-accounts
  name     = "${var.folder_id}-${each.key}"
  // folder_id = defaults to provider folder_id
}
resource "yandex_resourcemanager_folder_iam_member" "catgpt-roles" {
  // Requires 'resource-manager.admin' role https://cloud.yandex.ru/docs/resource-manager/security
  for_each  = local.catgpt-sa-roles
  folder_id = var.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["catgpt-sa"].id}"
  role      = each.key
}

// https://cloud.yandex.com/en/docs/cos/tutorials/coi-with-terraform
data "yandex_compute_image" "coi" {
  family = "container-optimized-image"
}
// https://terraform-provider.yandexcloud.net/Resources/compute_instance
resource "yandex_compute_instance" "catgpt-1" {
    // Requires 'compute.editor' role https://cloud.yandex.ru/docs/compute/security
    // Requires 'iam.serviceAccounts.admin' role
    // https://cloud.yandex.com/en/docs/compute/concepts/vm-platforms
    platform_id        = "standard-v2"  // Intel Cascade Lake
    // ID of the service account authorized for this instance = catgpt-sa
    service_account_id = yandex_iam_service_account.service-accounts["catgpt-sa"].id
    resources {
      cores         = 2
      memory        = 1 # Gb
      // Гарантированная доля CPU: доля может временно повышаться, но не будет меньше
      core_fraction = 5 # %
    }
    scheduling_policy {
      // Прерываемая ВМ работает не более 24 часов и может быть автоматически
      // остановлена. Все данные сохраняются, возможен перезапуск вручную.
      preemptible = true
    }
    network_interface {
      subnet_id = "${yandex_vpc_subnet.foo.id}"
      nat = true
    }
    boot_disk {
      initialize_params {
        type = "network-hdd"
        size = "30"
        image_id = data.yandex_compute_image.coi.id
      }
    }
    // https://cloud.yandex.ru/docs/compute/concepts/vm-metadata
    metadata = {
      user-data = "${file("cloud-config.yaml")}"
      docker-compose = templatefile("${path.module}/docker-compose.yaml", {
        registry_id = yandex_container_registry.registry1.id,
        folder_id = var.folder_id
      })
      // Для доступа к ВМ через SSH сгенерируйте пару SSH-ключей и передайте
      // публичную часть ключа на ВМ в параметре ssh-keys блока metadata.
      // https://cloud.yandex.ru/docs/compute/operations/vm-connect/ssh#creating-ssh-keys
      // Пользователь ВМ Container Optimized Image - ubuntu. Можно указать любого другого?
      ssh-keys  = "ubuntu:${file("./ssh_key.pub")}"
    }
}


