#!/usr/bin/env bash

# file names & paths
tmp="/tmp"  # destination folder to store the final iso file
hostname="ubuntu"

# define spinner function for slow tasks
# courtesy of http://fitnr.com/showing-a-bash-spinner.html
spinner()
{
    local pid=$1
    local delay=0.75
    local spinstr='|/-\'
    tput civis;

    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done

    printf "    \b\b\b\b"
    tput cnorm;
}

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

# define function to check if program is installed
# courtesy of https://gist.github.com/JamieMason/4761049
function program_is_installed {
    # set to 1 initially
    local return_=1
    # set to 0 if not found
    type $1 >/dev/null 2>&1 || { local return_=0; }
    # return value
    echo $return_
}

# print a pretty header
echo 
echo " +---------------------------------------------------+"
echo " |            UNATTENDED UBUNTU ISO MAKER            |"
echo " +---------------------------------------------------+"
echo 

if [ ${UID} -ne 0 ]; then
    echo " [-] This script must be runned with root privileges."
    echo " [-] sudo ${0}"
    echo
    exit 1
fi


echo " Ubuntu release selection (please view: http://releases.ubuntu.com): "
echo
read -ep " please enter your release version: " -i "14.04.2" release_version
read -ep " please enter your release variant(server/desktop): " -i "server" release_variant
read -ep " please enter your release architecture (i386/amd64): " -i "amd64" release_architecture

release_base_url="http://releases.ubuntu.com"
release_base_name="ubuntu-$release_version-$release_variant-$release_architecture"
release_image_file="$release_base_name.iso"
download_location="$release_base_url/$release_version/$release_image_file"
new_iso_name="$release_base_name-unattended.iso"

# ask the user questions about his/her preferences
read -ep " please enter your preferred timezone: " -i "America/Bogota" timezone
read -ep " please enter your preferred username: " -i "janu" username
read -sp " please enter your preferred password: " password
printf "\n"
read -sp " confirm your preferred password: " password2
printf "\n"

# check if the passwords match to prevent headaches
if [[ "$password" != "$password2" ]]; then
    echo " your passwords do not match; please restart the script and try again"
    echo
    exit
fi

# download the ubunto iso
cd $tmp
if [[ ! -f $tmp/$release_image_file ]]; then
    echo -n " downloading $release_image_file: "
    download "$download_location"
fi

# download netson seed file
read -ep " please enter your netson preseed file : " -i "only_ssh_server.seed" seed_file
if [[ ! -f $tmp/$seed_file ]]; then
    echo -n " downloading $seed_file: "
    download "https://github.com/CALlanoR/ubuntu-unattended/raw/master/$seed_file"
fi

# install required packages
echo " installing required packages"
if [ $(program_is_installed "mkpasswd") -eq 0 ] || [ $(program_is_installed "mkisofs") -eq 0 ]; then
    (apt-get -y update > /dev/null 2>&1) &
    spinner $!
    (apt-get -y install whois genisoimage > /dev/null 2>&1) &
    spinner $!
fi

# create working folders
echo " remastering your iso file"
mkdir iso_org
mkdir iso_new

# mount the image
if grep -qs $tmp/iso_org /proc/mounts ; then
    echo " image is already mounted, continue"
else
    (mount -o loop $tmp/$release_image_file $tmp/iso_org > /dev/null 2>&1)
fi

# copy the iso contents to the working directory
(cp -rT $tmp/iso_org $tmp/iso_new > /dev/null 2>&1) &
spinner $!

# set the language for the installation menu
cd $tmp/iso_new
echo en > $tmp/iso_new/isolinux/lang

# set late command
# late_command="chroot /target wget -O /home/$username/init.sh https://github.com/hvanderlaan/ubuntu-unattended/raw/master/init.sh ;\
#     chroot /target chmod +x /home/$username/init.sh ;"

# copy the netson seed file to the iso
cp -rT $tmp/$seed_file $tmp/iso_new/preseed/$seed_file

# # include firstrun script
# echo "
# # setup firstrun script
# d-i preseed/late_command                                    string      $late_command" >> $tmp/iso_new/preseed/$seed_file

# generate the password hash
pwhash=$(echo $password | mkpasswd -s -m sha-512)

# update the seed file to reflect the users' choices
# the normal separator for sed is /, but both the password and the timezone may contain it
# so instead, I am using @
sed -i "s@{{username}}@$username@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{pwhash}}@$pwhash@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{hostname}}@$hostname@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{timezone}}@$timezone@g" $tmp/iso_new/preseed/$seed_file

# calculate checksum for seed file
seed_checksum=$(md5sum $tmp/iso_new/preseed/$seed_file)

# add autostart in isolinux/isolinux.cfg
sed -i "s/timeout 0/timeout 10/" $tmp/iso_new/isolinux/isolinux.cfg

# add the autoinstall option to the menu
sed -i "s/default install/default autoinstall\ntimeout 10/" $tmp/iso_new/isolinux/txt.cfg
sed -i "/label install/ilabel autoinstall\n\
    menu label ^Unattended Ubuntu Server Install\n\
    kernel /install/vmlinuz\n\
    append file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/$seed_file preseed/file/checksum=$seed_checksum --" $tmp/iso_new/isolinux/txt.cfg

echo " creating the remastered iso"
cd $tmp/iso_new
(mkisofs -D -r -V "Ubuntu server" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $tmp/$new_iso_name . > /dev/null 2>&1) &
spinner $!

# cleanup
umount $tmp/iso_org
rm -rf $tmp/iso_new
rm -rf $tmp/iso_org

# print info to user  
echo " -----"
echo " finished remastering your ubuntu iso file"
echo " the new file is located at: $tmp/$new_iso_name"
echo " your username is: $username"
echo " your password is: $password"
echo " your hostname is: $hostname"
echo " your timezone is: $timezone"
echo

# unset vars
unset username
unset password
unset hostname
unset timezone
unset pwhash
unset download_file
unset download_location
unset new_iso_name
unset tmp
unset seed_file
