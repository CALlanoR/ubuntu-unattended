#!/bin/bash
set -e

spinner()
{
    local pid=$1
    local action=$2
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# set defaults
default_hostname="$(hostname)"
default_domain="local"
tmp=$(pwd)

clear

# check for root privilege
if [ "$(id -u)" != "0" ]; then
   echo " this script must be run as root" 1>&2
   echo
   exit 1
fi

# define download function
# courtesy of http://fitnr.com/showing-file-download-progress-using-wget.html
download()
{
    local url=$1
    echo -n "    "
    wget --progress=dot $url 2>&1 | grep --line-buffered "%" | \
        sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
    echo -ne "\b\b\b\b"
    echo " DONE"
}

# determine ubuntu version
ubuntu_version=$(lsb_release -cs)

# check for interactive shell
if ! grep -q "noninteractive" /proc/cmdline ; then
    stty sane

    # ask questions
    read -ep " please enter your preferred hostname: " -i "$default_hostname" hostname
    read -ep " please enter your preferred domain: " -i "$default_domain" domain
    read -ep " please enter your username: " -i "haraldvdlaan" username
fi

# print status message
echo " preparing your server; this may take a few minutes ..."

# set fqdn
fqdn="$hostname.$domain"

# update hostname
echo "$hostname" > /etc/hostname
sed -i "s@ubuntu.ubuntu@$fqdn@g" /etc/hosts
sed -i "s@ubuntu@$hostname@g" /etc/hosts
hostname "$hostname"

# update repos
(apt-get -y update > /dev/null 2>&1) & spinner $!
(apt-get -y upgrade > /dev/null 2>&1) & spinner $!
(apt-get -y dist-upgrade > /dev/null 2>&1) & spinner $!
(apt-get -y install openssh-server zsh git curl vim > /dev/null 2>&1) & spinner $!
(apt-get -y autoremove > /dev/null 2>&1) & spinner $!
(apt-get -y purge > /dev/null 2>&1) & spinner $!

# changing bash to zsh
wget -O /home/$username/.zaliasses 'https://raw.githubusercontent.com/hvanderlaan/zsh/master/.zaliasses' > /dev/null 2>&1
wget -O /home/$username/.zfunctions 'https://raw.githubusercontent.com/hvanderlaan/zsh/master/.zfunctions' > /dev/null 2>&1
wget -O /home/$username/.zcolors 'https://raw.githubusercontent.com/hvanderlaan/zsh/master/.zcolors' > /dev/null 2>&1
wget -O /home/$username/.zcompdump 'https://raw.githubusercontent.com/hvanderlaan/zsh/master/.zcompdump' > /dev/null 2>&1
wget -O /home/$username/.zprompt 'https://raw.githubusercontent.com/hvanderlaan/zsh/master/.zprompt' > /dev/null 2>&1
wget -O /home/$username/.zshrc 'https://raw.githubusercontent.com/hvanderlaan/zsh/master/.zshrc' > /dev/null 2>&1
usermod -s /usr/bin/zsh $username
chown $username:$username .z*

# remove myself to prevent any unintended changes at a later stage
rm $0

# finish
echo " DONE; rebooting ... "

# reboot
reboot
