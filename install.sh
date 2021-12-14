#!/bin/bash 

#Reference https://brezular.com/2021/04/01/docker-installation-on-vyos/

# Check if running as root
user=$(id -u)
[ "$user" != 0 ] && echo "Run script as root, exiting" && exit 1 

VERSION_CODENAME=$(lsb_release -c --short)
OS=$(uname -s)
ARCH=$(uname -m)

if [ "$VERSION_CODENAME" != 'buster' ]; then
	echo "***Warning***"
	echo "This install script only test on buster, your system is $VERSION_CODENAME."
	echo -n "Are you sure want to continue?[N]"
	read -n 1 continue
	if [ "${continue,,}" != 'y' ]; then
		echo "User aborted."
		exit 1
	fi
fi

echo "Checking network"
nslookup deb.debian.org > /dev/null 2>&1
if [ $? -ne 0 ]; then
	echo "connection timed out; no servers could be reached"
	echo "Exited."
	exit 1;	
fi

echo

echo "Checking Debian source"
# check apt source
aptsourcefile="/etc/apt/sources.list"
debsource="deb http://deb.debian.org/debian $VERSION_CODENAME main contrib non-free"

if [ $(grep -c "$debsource" $aptsourcefile) -eq 0 ]; then
	echo "Adding Debian source to apt sources list($aptsourcefile)"
	echo $debsource >> /etc/apt/sources.list
fi

echo "Updating..."
apt-get update

echo "Installing tools"
apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common

echo

echo "Checking docker source"
dockersourcefile="/etc/apt/sources.list.d/docker.list"
if [ ! -f $dockersourcefile ]; then
	# Add docker repo
	echo "Adding Docker gpg keyring"
	curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
	echo "Adding Docker source"
	echo "deb [arch=amd64] https://download.docker.com/linux/debian $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
fi


echo "Updating..."
apt-get update

echo

# Make persistent var for docker to live between vyos upgrades
echo -n "Enter a path where to store the docker libraries.[/config/user-data/docker]"
read dockerpath
if [ -z "$dockerpath" ]; then
	dockerpath="/config/user-data/docker"
fi

echo "Creating docker directory $dockerpath"
mkdir -p $dockerpath
ln -s $dockerpath /var/lib/docker

echo

# Install docker and docker-compose
echo -n "Which version of docker-compose to install?[2.2.2]"
read docker_comp_ver
if [ -z "$docker_comp_ver" ]; then
	docker_comp_ver='2.2.2'
fi

# Config docker daemon
echo
echo -n "Do you want to disable iptables and ip6tables, using vyos route instead for docker?[Y]"
read -n 1 disableiptables
if [ -z "$disableiptables" ]; then
	disableiptables="y"
fi
if [ "${disableiptables,,}" == 'y' ]; then
	daemonline="\"iptables\":false,\n\"ip6tables\": false"
fi

echo
echo -n "Do you want to add docker default bridge to vyos?[Y]"
read -n 1 addbridge
if [ -z "$addbridge" ]; then
	addbridge="y"
fi
if [ "${addbridge,,}" == 'y' ]; then
	echo
	echo -n "Bridge name for docker in vyos(brN)?[br0]"
	read bridgename
	if [ -z "$bridgename" ]; then
		bridgename="br0"
	fi
	
	if [ -n "$daemonline" ]; then
		daemonline="$daemonline,"
	fi
	daemonline="$daemonline\n\"bridge\": \"$bridgename\""
fi

if [ -n "$daemonline" ]; then
	daemonline="{\n$daemonline\n}"
fi

echo
echo "Write configuration to /etc/docker/daemon.json"
mkdir -p /etc/docker
echo -e $daemonline > /etc/docker/daemon.json

# Add bridge to vyos

echo
echo "Installing docker"
apt-get install -y docker-ce docker-ce-cli containerd.io
echo
echo "Downloading docker-compose v$docker_comp_ver"
result=$(curl -L "https://github.com/docker/compose/releases/download/v$docker_comp_ver/docker-compose-$OS-$ARCH" -w %{http_code} -o /var/lib/docker/docker-compose)
echo
if [ "$result" == "200" ]; then
	echo "Installing docker-compose"
	chmod +x /var/lib/docker/docker-compose
	ln -s /var/lib/docker/docker-compose /usr/local/bin/docker-compose
	echo "docker-compose succesfully installed."
else
	echo "Download failed."
	echo "docker-compose not installed."
fis


# Check if docker service is started
systemctl status docker &>/dev/null; ret_docker="$?"
if [ "$ret_docker" == 0 ]; then
  echo -e "\nDocker succesfully installed"
else
  echo -e "\nUPS, Docker service is not running"
fi
