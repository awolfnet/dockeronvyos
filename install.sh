#!/bin/bash

#Reference https://brezular.com/2021/04/01/docker-installation-on-vyos/

# Show vyos version
lsb_release -a

VERSION_CODENAME=`lsb_release -c --short`

if [ "$VERSION_CODENAME" != 'buster' ]; then
	echo ""
	echo "***Warning***"
	echo "This install script only test on buster, but your system is $VERSION_CODENAME."
	echo -n "Are you sure want to continue?[N/y]"
	read -n 1 continue
	if [ "${continue,,}" != 'y' ]; then
		echo ""
		echo "User aborted."
		exit 1
	fi
fi

user=$(id -u)
docker_comp_ver='1.28.5'

# Check if running as root
[ "$user" != 0 ] && echo "Run script as root, exiting" && exit 1 
 
echo ""

# check apt source
aptsourcefile="/etc/apt/sources.list"
debsource="deb http://deb.debian.org/debian $VERSION_CODENAME main contrib non-free"

if [ `grep -c "$debsource" $aptsourcefile` -eq 0 ]; then
	echo "Adding Debian source to apt sources list($aptsourcefile)"
	echo $debsource >> /etc/apt/sources.list
fi

echo "Updating..."
apt-get update

echo "Installing tools"
apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common

# Add docker repo
echo "Adding Docker gpg keyring"
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -

echo "Adding Docker source"
echo "deb [arch=amd64] https://download.docker.com/linux/debian buster stable" > /etc/apt/sources.list.d/docker.list

echo "Updating..."
apt-get update



# Check if docker service is started
systemctl status docker &>/dev/null; ret_docker="$?"
if [ "$ret_docker" == 0 ]; then
  echo -e "\nDocker succesfully installed"
else
  echo -e "\nUPS, Docker service is not running"
fi