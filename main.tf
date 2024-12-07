terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  token     = var.yandex_token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = "ru-central1-a"
}

# Сеть
resource "yandex_vpc_network" "default" {
  name = "my-vpc"
}

# Подсети
resource "yandex_vpc_subnet" "public" {
  name           = "public"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.default.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

resource "yandex_vpc_subnet" "private" {
  name           = "private"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.default.id
  v4_cidr_blocks = ["192.168.20.0/24"]
  route_table_id = yandex_vpc_route_table.private_routes.id
}

# Таблица маршрутизации
resource "yandex_vpc_route_table" "private_routes" {
  name       = "private-route-table"
  network_id = yandex_vpc_network.default.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    next_hop_address   = "192.168.10.254"
  }
}

# NAT-инстанс
resource "yandex_compute_instance" "nat_instance" {
  name = "nat-instance"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd80mrhj8fl2oe87o4e1" # ID образа Ubuntu или другой ОС
    }
  }

  network_interface {
    subnet_id  = yandex_vpc_subnet.public.id
    nat        = true
    ip_address = "192.168.10.254"  # Статический IP для внутреннего интерфейса
  }

  metadata = {
    user-data = <<EOF
#cloud-config
users:
  - name: ${var.ssh_user}
    groups: sudo
    shell: /bin/bash
    sudo: 'ALL=(ALL) NOPASSWD:ALL'
    ssh_authorized_keys:
      - ${file("${var.ssh_public_key}")}

runcmd:
  - sysctl -w net.ipv4.ip_forward=1
  - iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE
EOF
  }
}

# Публичная ВМ
resource "yandex_compute_instance" "public_instance" {
  name = "public-instance"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8ondkh1s6iakbqm635"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.public.id
    nat       = true
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_public_key)}"
  }
}

# Приватная ВМ
resource "yandex_compute_instance" "private_instance" {
  name = "private-instance"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8ondkh1s6iakbqm635"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.private.id
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_public_key)}"
  }
}
