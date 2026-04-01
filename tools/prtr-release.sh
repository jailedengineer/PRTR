#!/bin/sh
#
# PRTR release script
# Builds all image artifacts, compresses and generates checksums
#
# Usage: prtr-release.sh [build|compress|checksum|all]
#

set -eu

die() { echo -n "EXIT: " >&2; echo "$@" >&2; exit 1; }

# Variables
# PRTR_HOME: Path to PRTR git working directory.
# Must be set when running as root/sudo since HOME becomes /root.
# Example: PRTR_HOME=/home/paulo/PRTR sudo tools/prtr-release.sh all
: ${PRTR_HOME:="${HOME}/PRTR"}

IMGDIR="/usr/local/poudriere/data/images"
JAILNAME="PRTRj"
PORTSNAME="PRTRp"
HOSTNAME="router.prtr.net"
OVERLAY="${PRTR_HOME}/BSDRP/Files"
PKGLIST="/usr/local/etc/poudriere.d/PRTR-pkglist.common"
EXCLUDES="${PRTR_HOME}/poudriere.etc/poudriere.d/excluded.files"
POSTSCRIPT="${PRTR_HOME}/poudriere.etc/poudriere.d/post-script.sh"
SIZE="3.95g"
ARCH=$(uname -p)

# Get version from PRTR
VERSION=$(cat ${PRTR_HOME}/BSDRP/Files/etc/version)
[ -z "${VERSION}" ] && die "Cannot read version from BSDRP/Files/etc/version"

# Image base name: PRTR-2.1.0-dev-full-amd64.img.xz
PREFIX="PRTR-${VERSION}"

usage() {
	echo "PRTR Release Script"
	echo "Usage: $0 [build|compress|checksum|all|clean]"
	echo ""
	echo "  build     - Build firmware and generate mtree via poudriere"
	echo "  compress  - Compress all images with xz"
	echo "  checksum  - Generate sha256 checksums"
	echo "  all       - Run build + compress + checksum"
	echo "  clean     - Remove compressed images and checksums"
	echo ""
	echo "Version: ${VERSION}"
	echo "Arch:    ${ARCH}"
	exit 0
}

build() {
	echo ">>> Building PRTR ${VERSION} images for ${ARCH}"

	# Full firmware image
	echo ">>> Building full image..."
	sudo poudriere image -t firmware -s ${SIZE} \
		-j ${JAILNAME} -p ${PORTSNAME} \
		-n PRTR -h ${HOSTNAME} \
		-c ${OVERLAY} \
		-f ${PKGLIST} \
		-X ${EXCLUDES} \
		-A ${POSTSCRIPT}

	# Rename to versioned names
	echo ">>> Renaming images to versioned names..."
	sudo cp ${IMGDIR}/PRTR.img \
		${IMGDIR}/${PREFIX}-full-${ARCH}.img
	sudo cp ${IMGDIR}/PRTR-upgrade.img \
		${IMGDIR}/${PREFIX}-upgrade-${ARCH}.img
	sudo cp ${IMGDIR}/PRTR.mtree \
		${IMGDIR}/${PREFIX}-mtree-${ARCH}.mtree

	echo ">>> Build complete:"
	ls -lh ${IMGDIR}/${PREFIX}-*
}

compress() {
	echo ">>> Compressing images with xz..."

	for f in \
		${IMGDIR}/${PREFIX}-full-${ARCH}.img \
		${IMGDIR}/${PREFIX}-upgrade-${ARCH}.img \
		${IMGDIR}/${PREFIX}-mtree-${ARCH}.mtree; do
		if [ -f "${f}" ]; then
			echo "    Compressing $(basename ${f})..."
			sudo xz -kv --threads=0 "${f}"
		else
			echo "    WARNING: ${f} not found, skipping"
		fi
	done

	echo ">>> Compression complete:"
	ls -lh ${IMGDIR}/${PREFIX}-*.xz
}

checksum() {
	echo ">>> Generating sha256 checksums..."

	for f in ${IMGDIR}/${PREFIX}-*.xz; do
		[ -f "${f}" ] || continue
		sudo sha256 "${f}" | sudo tee "${f}.sha256" > /dev/null
		echo "    $(basename ${f}).sha256"
	done

	echo ">>> Checksums:"
	cat ${IMGDIR}/${PREFIX}-*.sha256
}

clean() {
	echo ">>> Cleaning compressed images and checksums..."
	rm -fv ${IMGDIR}/${PREFIX}-*.xz
	rm -fv ${IMGDIR}/${PREFIX}-*.sha256
	rm -fv ${IMGDIR}/${PREFIX}-*.img
	rm -fv ${IMGDIR}/${PREFIX}-*.mtree
}

# Main
[ $# -eq 0 ] && usage

case "$1" in
	build)
		build
		;;
	compress)
		compress
		;;
	checksum)
		checksum
		;;
	all)
		build
		compress
		checksum
		echo ""
		echo ">>> PRTR ${VERSION} release artifacts ready in ${IMGDIR}:"
		ls -lh ${IMGDIR}/${PREFIX}-*
		;;
	clean)
		clean
		;;
	*)
		usage
		;;
esac
