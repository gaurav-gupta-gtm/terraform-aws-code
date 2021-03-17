#! /bin/bash

sudo yum update -y
sudo yum install -y httpd git php
sudo systemctl start httpd
sudo systemctl enable httpd
