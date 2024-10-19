#!/bin/bash

# Author: Marek Hric xhricma00

# createrepo and httpd are needed for the script to work
if ! command -v createrepo &> /dev/null; then
    echo "Installing createrepo"
    yum install createrepo -y &> /dev/null
fi

if ! command -v httpd &> /dev/null; then
    echo -e "Installing httpd\n"
    yum install httpd -y &> /dev/null
fi

LOOP_DEV="/dev/loop0"
REPO_NAME="ukol"
IMG_PATH="/var/tmp/$REPO_NAME.img"
REPO_CONF="/etc/yum.repos.d/$REPO_NAME.repo"
REPO_DIR="/var/www/html/$REPO_NAME"
HTTPD_CONF="/etc/httpd/conf/httpd.conf"

# Check if the image file is already mounted
if ! df -h | grep -q "$REPO_DIR"; then
    echo "Creating file $IMG_PATH" 
    dd if=/dev/zero of=$IMG_PATH bs=1M count=200 &> /dev/null # 1

    echo "Creating loop device"
    losetup $LOOP_DEV $IMG_PATH # 2

    echo "Creating filesystem"
    mkfs.ext4 $LOOP_DEV &> /dev/null # 3

    echo "Creating directory $REPO_DIR"
    mkdir -p $REPO_DIR

    echo "Adding automount of the image file to the loop"
    echo "$IMG_PATH $REPO_DIR ext4 loop 0 0" >> /etc/fstab # 4
    systemctl daemon-reload

    echo -e "Mounting $REPO_DIR\n"
    mount -a # 5
fi

for PACKAGE in "$@"; do # 6
    if ! ls "$REPO_DIR" | grep -q "^${PACKAGE}.*\.rpm$"; then
        echo -e "Downloading $PACKAGE\n"
        yum install --downloadonly --downloaddir=$REPO_DIR $PACKAGE -y &> /dev/null
    fi
done

if ! ls $REPO_DIR | grep -q "repodata" ; then
    echo -e "Generating repodata\n"
    createrepo $REPO_DIR &> /dev/null # 7
    restorecon -Rv $REPO_DIR
    yum clean all &> /dev/null
elif [ $# -gt 0 ]; then
    echo -e "Renerating repodata\n"
    createrepo --update $REPO_DIR &> /dev/null # 7
    restorecon -Rv $REPO_DIR
    yum clean all &> /dev/null
fi

# Check if the repository is already configured in yum
if ! ls /etc/yum.repos.d/ | grep -q "$REPO_NAME"; then # 8
    echo -e "Creating Yum repository configuration\n"
    echo "[$REPO_NAME]
name=$REPO_NAME
baseurl=http://localhost/$REPO_NAME/
enabled=1
gpgcheck=0" > $REPO_CONF
    yum clean all &> /dev/null
fi

# Check if httpd is running
if ! systemctl is-active httpd &> /dev/null; then
    echo -e "Starting httpd\n"df -h | grep "$REPO_DIR"
    systemctl start httpd # 9
fi

# Check if the repository is already configured in httpd
if ! grep -q "$REPO_DIR" $HTTPD_CONF; then
    echo -e "Configuring HTTPD to serve the repository\n"
    echo "<Directory \"$REPO_DIR\">
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>" >> $HTTPD_CONF

    systemctl restart httpd
fi

echo "yum repositories:"
yum repolist # 10

echo -e "\nUnmounting $REPO_DIR\n"
umount $REPO_DIR # 11

echo "Checking automount"
mount -a # 12
df -h | grep "$REPO_DIR"

echo

yum --disablerepo="*" --enablerepo="$REPO_NAME" list available # 13
