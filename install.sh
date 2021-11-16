#!/bin/bash

#Reference https://brezular.com/2021/04/01/docker-installation-on-vyos/

user=$(id -u)
docker_comp_ver='1.28.5'

# Check if running as root
[ "$user" != 0 ] && echo "Run script as root, exiting" && exit 1 
