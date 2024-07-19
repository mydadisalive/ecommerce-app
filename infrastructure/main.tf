terraform {
  backend "remote" {
    organization = "avicii-corp"
    workspaces {
      name = "ecommerce-app"
    }
  }
}

provider "aws" {
  region = "il-central-1"
}

provider "local" {
  version = "~> 2.1"
}

# VPC and Subnet
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "default" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "il-central-1a"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
}

resource "aws_route_table" "default" {
  vpc_id = aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default.id
  }
}

resource "aws_route_table_association" "default" {
  subnet_id      = aws_subnet.default.id
  route_table_id = aws_route_table.default.id
}

# Security Group
resource "aws_security_group" "allow_ssh_http" {
  vpc_id      = aws_vpc.default.id
  name        = "allow_ssh_http"
  description = "Allow SSH and HTTP inbound traffic"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Key Pair
resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = file("${path.module}/id_rsa.pub")
}

# EC2 Instance
resource "aws_instance" "backend" {
  ami                          = "ami-0fbd08534ff5a05ff"
  instance_type                = "t3.micro"
  key_name                     = aws_key_pair.deployer.key_name
  vpc_security_group_ids       = [aws_security_group.allow_ssh_http.id]
  subnet_id                    = aws_subnet.default.id
  associate_public_ip_address  = true
  tags = {
    Name = "ecommerce-backend"
  }

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y python3
    pip3 install flask
    cat <<EOT > /home/ec2-user/app.py
    from flask import Flask, request, jsonify

    app = Flask(__name__)

    @app.route('/')
    def home():
        return "E-commerce API"

    @app.route('/products', methods=['POST'])
    def add_product():
        data = request.get_json()
        # Add product to database logic here
        return jsonify({"message": "Product added!"}), 201

    if __name__ == '__main__':
        app.run(host='0.0.0.0', port=80)
    EOT
    cat <<EOT > /etc/systemd/system/flask-app.service
    [Unit]
    Description=Flask App
    After=network.target

    [Service]
    User=ec2-user
    WorkingDirectory=/home/ec2-user
    ExecStart=/usr/bin/sudo /usr/bin/python3 /home/ec2-user/app.py
    Restart=always

    [Install]
    WantedBy=multi-user.target
    EOT
    systemctl daemon-reload
    systemctl enable flask-app.service
    systemctl start flask-app.service
  EOF

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("${path.module}/id_rsa")
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Setup complete'"
    ]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# S3 Bucket
resource "aws_s3_bucket" "frontend" {
  bucket = "ecommerce-frontend-bucket-unique-12345"
  tags = {
    Name        = "ecommerce-frontend"
    Environment = "Dev"
  }
}

resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.frontend.bucket
  key          = "index.html"
  source       = "${path.module}/../frontend/index.html"
  content_type = "text/html"
}

resource "aws_s3_object" "error_html" {
  bucket       = aws_s3_bucket.frontend.bucket
  key          = "error.html"
  source       = "${path.module}/../frontend/error.html"
  content_type = "text/html"
}

resource "aws_s3_object" "css_files" {
  for_each     = fileset("${path.module}/../frontend/css", "**/*")
  bucket       = aws_s3_bucket.frontend.bucket
  key          = "css/${each.key}"
  source       = "${path.module}/../frontend/css/${each.key}"
  content_type = "text/css"
}

resource "aws_s3_object" "image_files" {
  for_each     = fileset("${path.module}/../frontend/images", "**/*")
  bucket       = aws_s3_bucket.frontend.bucket
  key          = "images/${each.key}"
  source       = "${path.module}/../frontend/images/${each.key}"
  content_type = lookup({
    "jpg"  = "image/jpeg",
    "jpeg" = "image/jpeg",
    "png"  = "image/png",
    "gif"  = "image/gif",
    "svg"  = "image/svg+xml"
  }, substr(each.key, length(each.key) - 3, 3), "application/octet-stream")
}

resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = "*",
        Action = "s3:GetObject",
        Resource = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_website_configuration" "frontend_website" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend_public_access" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

output "backend_public_ip" {
  value = aws_instance.backend.public_ip
}

output "website_url" {
  value = "http://${aws_s3_bucket.frontend.website_endpoint}"
}

resource "null_resource" "start_instance" {
  provisioner "local-exec" {
    command = "aws ec2 start-instances --instance-ids ${aws_instance.backend.id}"
  }

  #depends_on = [aws_instance.backend]
}
