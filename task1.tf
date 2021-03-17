provider "aws" {
  region   = "ap-south-1"
  profile  = "terrauser"
}

resource "tls_private_key" "task1_key_form"  {
  algorithm = "RSA"
}

resource "aws_key_pair" "task1-key" {
  key_name   = "task1-key"
  public_key = tls_private_key.task1_key_form.public_key_openssh
  }

resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow TLS inbound traffic"


  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "task1-sgroup"
  }
}

resource "aws_instance" "web_inst" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name      = "task1-key"
  security_groups = [ "allow_http" ]
 
   connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key =  tls_private_key.task1_key_form.private_key_pem
    host     = aws_instance.web_inst.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install -y httpd git php",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
    ]
  }
tags = {
    Name = "task1-inst"
  }
}

resource "aws_ebs_volume" "task1-ebs" {
  availability_zone = aws_instance.web_inst.availability_zone
  size              = 1

  tags = {
    Name = "task1-ebs"
  }
}

resource "aws_volume_attachment" "ebs-attach" {
  device_name = "/dev/sdh"
  volume_id    = "${aws_ebs_volume.task1-ebs.id}"
  instance_id  = "${aws_instance.web_inst.id}"
  force_detach = true
}

output "myos_ip" {
  value = aws_instance.web_inst.public_ip
}	

resource "null_resource" "save_instan_ip"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.web_inst.public_ip} > publicip.txt"
  	}
}

resource "null_resource" "null_vol_attach"  {

  depends_on = [
    aws_volume_attachment.ebs-attach,
  ]


 connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.task1_key_form.private_key_pem
    host     = aws_instance.web_inst.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/gaurav-gupta-gtm/terraform-aws-code.git /var/www/html/"
    ]
  }
}

resource "null_resource" "null_vol_depend"  {

depends_on = [
    null_resource.null_vol_attach,
  ]
}


#To create S3 bucket
resource "aws_s3_bucket" "my-terra-bucket-12341" {
  bucket = "my-terra-bucket-12341"
  acl    = "public-read"
  force_destroy  = true
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["https://my-terra-bucket-12341"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
depends_on = [
   aws_volume_attachment.ebs-attach,
  ]
}

resource "aws_s3_bucket_object" "obj" {
  key = "gaurav.jpeg"
  bucket = aws_s3_bucket.my-terra-bucket-12341.id
  source = "gaurav.jpeg"
  acl="public-read"
}


# Create Cloudfront distribution
resource "aws_cloudfront_distribution" "distribution" {
    origin {
        domain_name = "${aws_s3_bucket.my-terra-bucket-12341.bucket_regional_domain_name}"
        origin_id = "S3-${aws_s3_bucket.my-terra-bucket-12341.bucket}"

        custom_origin_config {
            http_port = 80
            https_port = 443
            origin_protocol_policy = "match-viewer"
            origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
        }
}
    # By default, show gaurav.jpeg file
    default_root_object = "gaurav.jpeg"
    enabled = true

    # If there is a 404, return gaurav.jpeg with a HTTP 200 Response
    custom_error_response {
        error_caching_min_ttl = 3000
        error_code = 404
        response_code = 200
        response_page_path = "/gaurav.jpeg"
    }

    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = "S3-${aws_s3_bucket.my-terra-bucket-12341.bucket}"

        #Not Forward all query strings, cookies and headers
        forwarded_values {
            query_string = false
	    cookies {
		forward = "none"
	    }
            
        }

        viewer_protocol_policy = "redirect-to-https"
        min_ttl = 0
        default_ttl = 3600
        max_ttl = 86400
    }

    # Restricts who is able to access this content
    restrictions {
        geo_restriction {
            # type of restriction, blacklist, whitelist or none
            restriction_type = "none"
        }
    }

    # SSL certificate for the service.
    viewer_certificate {
        cloudfront_default_certificate = true
    }
}
output "cloudfront_ip_addr" {
  value = aws_cloudfront_distribution.distribution.domain_name
}

output "key-pair" {
  value = tls_private_key.task1_key_form.private_key_pem
}




