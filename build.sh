#!/bin/sh -e

CONFIG="${1:-configs/ufi103s-v5.conf}"

echo "Install dependencies\n"
scripts/install_deps.sh

echo "\nBuild hyp and aboot firmware\n"
scripts/build_hyp_aboot.sh

echo "\nExtract MSM8916 firmware\n"
scripts/extract_fw.sh

echo "\nCreate rootfs\n"
scripts/debootstrap.sh "$CONFIG"

echo "\nInstall 4G LTE NetworkManager profiles\n"
for rootfs_dir in rootfs build/rootfs; do
    if [ -d "$rootfs_dir/etc/NetworkManager/system-connections" ]; then
        install -m 600 configs/*.nmconnection "$rootfs_dir/etc/NetworkManager/system-connections/"
        echo "Installed all NM connection profiles into $rootfs_dir"
    fi
done

echo "\nBuild gadget-tools\n"
scripts/build_gt.sh

echo "\nCreate images\n"
scripts/build_images.sh "$CONFIG"
