#!/bin/sh -e

# 1. Nap cau hinh neu co truyen tham so
CONFIG="$1"
[ -n "$CONFIG" ] && [ -f "$CONFIG" ] && . "$CONFIG"

CHROOT=${CHROOT=$(pwd)/rootfs}
# Khoa mac dinh sang bookworm (Debian 12) de tranh loi libconfig9 tren Debian 13
RELEASE=${ROOTFS_RELEASE:-${RELEASE:-bookworm}}
HOST_NAME=${HOST_NAME=openstick-debian}

rm -rf ${CHROOT}

debootstrap --foreign --arch arm64 \
    --keyring /usr/share/keyrings/debian-archive-keyring.gpg ${RELEASE} ${CHROOT}

cp $(which qemu-aarch64-static) ${CHROOT}/usr/bin

chroot ${CHROOT} qemu-aarch64-static /bin/bash /debootstrap/debootstrap --second-stage

cat << EOF > ${CHROOT}/etc/apt/sources.list
deb http://deb.debian.org/debian ${RELEASE} main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security/ ${RELEASE}-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${RELEASE}-updates main contrib non-free-firmware
EOF

mount -t proc proc ${CHROOT}/proc/
mount -t sysfs sys ${CHROOT}/sys/
mount -o bind /dev/ ${CHROOT}/dev/
mount -o bind /dev/pts/ ${CHROOT}/dev/pts/
mount -o bind /run ${CHROOT}/run/

cp scripts/setup.sh ${CHROOT}
chroot ${CHROOT} qemu-aarch64-static /bin/sh -c /setup.sh

# cleanup
for a in proc sys dev/pts dev run; do
    umount ${CHROOT}/${a}
done;

rm -f ${CHROOT}/setup.sh
echo -n > ${CHROOT}/root/.bash_history

echo ${HOST_NAME} > ${CHROOT}/etc/hostname
sed -i "/localhost/ s/$/ ${HOST_NAME}/" ${CHROOT}/etc/hosts

# setup systemd services
cp -a configs/system/* ${CHROOT}/etc/systemd/system

cp -a scripts/msm-firmware-loader.sh ${CHROOT}/usr/sbin

# setup NetworkManager (nap tat ca cac profile mang da tao)
mkdir -p ${CHROOT}/etc/NetworkManager/system-connections
cp configs/*.nmconnection ${CHROOT}/etc/NetworkManager/system-connections/ 2>/dev/null || true
chmod 0600 ${CHROOT}/etc/NetworkManager/system-connections/* 2>/dev/null || true
sed -i '/\[main\]/a dns=dnsmasq' ${CHROOT}/etc/NetworkManager/NetworkManager.conf

# enable autoconnect for usb0
cat << EOF > ${CHROOT}/etc/udev/rules.d/99-nm-usb0.rules
SUBSYSTEM=="net", ACTION=="add|change|move", ENV{DEVTYPE}=="gadget", ENV{NM_UNMANAGED}="0"
EOF

# install kernel
wget -O - http://mirror.postmarketos.org/postmarketos/v24.06/aarch64/linux-postmarketos-qcom-msm8916-6.6-r5.apk \
    | tar xkzf - -C ${CHROOT} --exclude=.PKGINFO --exclude=.SIGN* 2>/dev/null

mkdir -p ${CHROOT}/boot/extlinux
cp configs/extlinux.conf ${CHROOT}/boot/extlinux

# Bien dich tu dong cac file dts sang dtb neu co
for dts_file in dtbs/*.dts; do
    if [ -f "$dts_file" ]; then
        dtb_out="dtbs/$(basename "$dts_file" .dts).dtb"
        echo "Compiling $dts_file -> $dtb_out"
        dtc -I dts -O dtb -o "$dtb_out" "$dts_file" 2>/dev/null || true
    fi
done

# copy custom dtb's vao kernel
mkdir -p ${CHROOT}/boot/dtbs/qcom
cp dtbs/*.dtb ${CHROOT}/boot/dtbs/qcom 2>/dev/null || cp dtbs/* ${CHROOT}/boot/dtbs/qcom

# create missing directory
mkdir -p ${CHROOT}/lib/firmware/msm-firmware-loader

# update fstab
echo "PARTUUID=80780b1d-0fe1-27d3-23e4-9244e62f8c46\t/boot\text2\tdefaults\t0 2" > ${CHROOT}/etc/fstab

# backup rootfs
tar cpzf rootfs.tgz --exclude="usr/bin/qemu-aarch64-static" -C rootfs .
