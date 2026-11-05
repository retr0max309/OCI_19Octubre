resource "oci_core_instance" "ubuntu-vm" {
  compartment_id      = var.compartment_ocid
  display_name        = "ubuntu-vm"
  availability_domain = var.availability_domain
  shape               = "VM.Standard.E2.2"

  source_details {
    source_type = "image"
    source_id   = var.ubuntu_2404_image_ocid
  }

  create_vnic_details {
    subnet_id        = var.subnet_ocid
    assign_public_ip = true
    nsg_ids          = [oci_core_network_security_group.nsg_http.id]
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  lifecycle {
    ignore_changes = [metadata["user_data"]]
  }
}

# ejecuta el script tambien si la VM ya existia antes de este cambio
resource "terraform_data" "react_deploy" {
  triggers_replace = [
    oci_core_instance.ubuntu-vm.id,
    filesha256("${path.module}/setup-react.sh"),
    sha256(join("", [
      for filename in sort(fileset("${path.module}/react-app", "**")) :
      filesha256("${path.module}/react-app/${filename}")
      if !startswith(filename, "node_modules/") && !startswith(filename, "dist/")
    ])),
  ]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = oci_core_instance.ubuntu-vm.public_ip
    private_key = file(var.private_key_path)
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = ["rm -rf -- /home/ubuntu/react-app && mkdir -p /home/ubuntu/react-app/src /home/ubuntu/react-app/public"]
  }

  provisioner "file" {
    source      = "${path.module}/react-app/src/"
    destination = "/home/ubuntu/react-app/src"
  }

  provisioner "file" {
    source      = "${path.module}/react-app/public/"
    destination = "/home/ubuntu/react-app/public"
  }

  provisioner "file" {
    source      = "${path.module}/react-app/index.html"
    destination = "/home/ubuntu/react-app/index.html"
  }

  provisioner "file" {
    source      = "${path.module}/react-app/package.json"
    destination = "/home/ubuntu/react-app/package.json"
  }

  provisioner "file" {
    source      = "${path.module}/react-app/package-lock.json"
    destination = "/home/ubuntu/react-app/package-lock.json"
  }

  provisioner "file" {
    source      = "${path.module}/react-app/vite.config.js"
    destination = "/home/ubuntu/react-app/vite.config.js"
  }

  provisioner "remote-exec" {
    script = "${path.module}/setup-react.sh"
  }

  depends_on = [oci_core_network_security_group_security_rule.allow_http]
}

output "instance_public_ip" {
  value       = oci_core_instance.ubuntu-vm.public_ip
  description = "IP publica de la VM"
}

output "instance_id" {
  value       = oci_core_instance.ubuntu-vm.id
  description = "ID de la VM"
}


data "oci_core_subnet" "subnet" {
  subnet_id = var.subnet_ocid
}

# Network Security Group para la VM
resource "oci_core_network_security_group" "nsg_http" {
  compartment_id = var.compartment_ocid
  vcn_id         = data.oci_core_subnet.subnet.vcn_id
  display_name   = "nsg-allow-http-80"
}

# Regla de entrada: permite tráfico HTTP en puerto 80
resource "oci_core_network_security_group_security_rule" "allow_http" {
  network_security_group_id = oci_core_network_security_group.nsg_http.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}
