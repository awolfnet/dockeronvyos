#!/bin/bash

#Reference https://brezular.com/2021/04/01/docker-installation-on-vyos/

logfile="/var/log/install.log"

echo "********************************************"
echo "This script will install docker on your vyos"
echo "********************************************"
echo "Install log file:$logfile"
echo

## check if running as root ########
echo "Checking permission"
user=$(id -u)
if [ "$user" != 0 ]; then
	echo "Run script as root, exiting"
	exit 1 
fi
####################################

## check if docker installed #######
echo "Checking docker status"
if [ -a "/var/run/docker.sock" ]; then
	echo "Docker is installed on this system, aborted." | sudo tee -a $logfile
	exit 1
fi
####################################

## check system requirement ########
VERSION_CODENAME=$(lsb_release -c --short)
OS=$(uname -s)
ARCH=$(uname -m)

if [ "$VERSION_CODENAME" == 'buster' ]; then
	debsource="deb http://deb.debian.org/debian $VERSION_CODENAME main contrib non-free"
elif [ "$VERSION_CODENAME" == 'jessie' ]; then
	debsource="deb http://deb.debian.org/debian $VERSION_CODENAME main contrib non-free"
else
	echo "***Warning***"
	echo "This install script only tested on buster, your system is $VERSION_CODENAME." | sudo tee -a $logfile
	echo -n "Are you sure want to continue?[y/N]:"
	read -n 1 continue
	if [ "${continue,,}" != 'y' ]; then
		echo "User aborted." | sudo tee -a $logfile
		exit 1
	fi
	debsource="deb http://archive.debian.org/debian $VERSION_CODENAME main"
fi

####################################

## check network ###################
echo "Checking network"
nslookup deb.debian.org >> $logfile 2>&1
if [ $? -ne 0 ]; then
	echo "Cannot resolve deb.debian.org" | sudo tee -a $logfile
	echo "Exited." | sudo tee -a $logfile
	exit 1;	
fi
####################################

## check apt source ################
echo "Checking Debian source"
aptsourcefile="/etc/apt/sources.list"
if [ $(grep -c "$debsource" $aptsourcefile) -eq 0 ]; then
	echo "Debian source not found" | sudo tee -a $logfile
	echo "Adding Debian source to apt sources list($aptsourcefile)" | sudo tee -a $logfile
	echo $debsource >> $aptsourcefile
fi
echo "Updating..."
apt-get update >> $logfile
####################################

## check docker source #############
echo "Checking docker source"
dockersourcefile="/etc/apt/sources.list.d/docker.list"
if [ ! -f $dockersourcefile ]; then
	echo "Docker source not found." | sudo tee -a $logfile
	echo "Installing apt-transport-https ca-certificates curl gnupg-agent software-properties-common"
	apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common >> $logfile
	# Add docker repo
	echo "Adding Docker gpg keyring" | sudo tee -a $logfile
	curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
	echo "Adding Docker source to apt sources list($dockersourcefile)" | sudo tee -a $logfile
	echo "deb [arch=amd64] https://download.docker.com/linux/debian $VERSION_CODENAME stable" > $dockersourcefile
fi
echo "Updating..."
apt-get update >> $logfile
####################################

echo

## Make persistent var for docker to live between vyos upgrades
echo -n "Enter a path where to store the docker libraries.[/config/user-data/docker]:"
read dockerpath
if [ -z "$dockerpath" ]; then
	dockerpath="/config/user-data/docker"
fi

echo "Creating docker directory $dockerpath" | sudo tee -a $logfile
mkdir -p $dockerpath
ln -s $dockerpath /var/lib/docker
###############################################################

echo

## Config docker  ##################
echo -n "Do you want to disable iptables and ip6tables, using vyos route instead for docker?[Y/n]:"
read -n 1 disableiptables
if [ -z "$disableiptables" ]; then
	disableiptables="y"
fi
if [ "${disableiptables,,}" == 'y' ]; then
	daemonline="\t\"iptables\":false,\n\t\"ip6tables\": false"
fi

echo
echo -n "Do you want to add docker default bridge to vyos?[Y/n]:"
read -n 1 addbridge
if [ -z "$addbridge" ]; then
	addbridge="y"
fi
if [ "${addbridge,,}" == 'y' ]; then
	echo
	echo -n "Default bridge name for docker in vyos(brN)?[br0]:"
	read bridgename
	if [ -z "$bridgename" ]; then
		bridgename="br0"
	fi
	if [ -n "$daemonline" ]; then
		daemonline="$daemonline,"
	fi
	daemonline="$daemonline\n\t\"bridge\": \"$bridgename\""
	echo
	echo -n "Enter $bridgename ip address.[172.20.0.1/24]:"
	read bridgeip
	if [ -z "$bridgeip" ]; then
		bridgeip="172.20.0.1/24"
	fi
fi

if [ -n "$daemonline" ]; then
	daemonline="{\n$daemonline\n}"
	echo
	echo "Writing configuration to /etc/docker/daemon.json"
	echo "Docker daemon configuration" >> $logfile
	echo -e $daemonline >> $logfile
	mkdir -p /etc/docker
	echo -e $daemonline > /etc/docker/daemon.json
fi
####################################

echo

## Add bridge to vyos ##############
echo "Adding bridge $bridgename $bridgeip to vyos"
echo "#!/bin/vbash" > /tmp/addbridge.sh
echo "source /opt/vyatta/etc/functions/script-template" >> /tmp/addbridge.sh
echo "configure" >> /tmp/addbridge.sh
echo "set interfaces bridge $bridgename address $bridgeip" >> /tmp/addbridge.sh
echo "set interfaces bridge $bridgename description 'Docker default bridge'" >> /tmp/addbridge.sh
echo "commit" >> /tmp/addbridge.sh
echo "exit" >> /tmp/addbridge.sh

sg vyattacfg -c "/bin/vbash /tmp/addbridge.sh"
rm /tmp/addbridge.sh
echo "!!!!Don't forget to save vyos configuration manually!!!!"
####################################

echo

## Install docker ##################
echo "Installing docker-ce docker-ce-cli containerd.io"
apt-get install -y docker-ce docker-ce-cli containerd.io >> $logfile
####################################

echo

## Install docker-compose ##########
echo -n "Which version of docker-compose to install?[2.2.2]:"
read docker_comp_ver
if [ -z "$docker_comp_ver" ]; then
	docker_comp_ver='2.2.2'
fi

echo
echo "Downloading docker-compose v$docker_comp_ver"
dockercomposefile="/var/lib/docker/docker-compose"
url="https://github.com/docker/compose/releases/download/v$docker_comp_ver/docker-compose-$OS-$ARCH"
echo "downloading $url to $dockercomposefile" >> $logfile
result=$(curl -L $url -w %{http_code} -o $dockercomposefile)
echo "download result $result" >> $logfile
if [ "$result" == "200" ]; then
	echo "Installing docker-compose"
	chmod +x $dockercomposefile
	ln -s $dockercomposefile /usr/local/bin/docker-compose
	echo "docker-compose succesfully installed." | sudo tee -a $logfile
else
	echo "Download failed." | sudo tee -a $logfile
	echo "docker-compose not installed." | sudo tee -a $logfile
fi
####################################

echo

## Check if docker service is started
echo "Checking docker service status"
systemctl status docker &>> $logfile; ret_docker="$?"
if [ "$ret_docker" == 0 ]; then
  echo -e "\nDocker succesfully installed"
else
  echo -e "\nUPS, Docker service is not running"
fi
#####################################