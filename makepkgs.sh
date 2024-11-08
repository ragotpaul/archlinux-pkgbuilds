#!/bin/bash

for dir in $@; do
    if [ ! -d $dir ]; then
        echo "Directory $dir does not exist"
        exit 1
    fi
    if [ ! -f $dir/PKGBUILD ]; then
        echo "Directory $dir does not contain a PKGBUILD file"
        exit 1
    fi
done

CHROOTS="/mnt/chroots"
GPGKEY="BDA67DDBBBE34C80"
REPONAME="mypkgs"
REPOARCH="$(uname -m)"
REPODIR="$REPONAME/$REPOARCH"

export BUILDDIR="$(pwd)/build"
export PKGDEST="$BUILDDIR/pkg"
export SRCDEST="$BUILDDIR/src"
export LOGDEST="$BUILDDIR/log"
rm -rfv $BUILDDIR
mkdir -p $BUILDDIR $PKGDEST $SRCDEST $LOGDEST

if [ -z "$(mount | grep $CHROOTS)" ]; then
    sudo mount --mkdir -t tmpfs -o defaults,size=4G,uid=$(id -u),gid=$(id -g) tmpfs $CHROOTS
fi

sudo rm -rfv $CHROOTS/*
mkarchroot $CHROOTS/root base-devel
arch-nspawn $CHROOTS/root pacman -Syyu --noconfirm

pkgs_deps() {
    pkgs=""
    for pkg in $(find $PKGDEST -type f -name "*.pkg.tar.zst"); do
        if [[ $pkg == *"debug"* ]]; then
            continue
        fi
        pkgs+="-I $(realpath $pkg) "
    done
    echo $pkgs
}

for dir in $@; do
    pushd $dir
    makechrootpkg -c -u -r $CHROOTS -n $(pkgs_deps)
    popd
done

if [ ! -d $REPODIR ]; then
    mkdir -p $REPODIR
fi

for pkg in $(find $PKGDEST -type f -name "*.pkg.tar.zst"); do
    if [[ $pkg == *"debug"* ]]; then
        continue
    fi
    echo "Signing and adding $pkg to $REPODIR"
    if [ ! -f $pkg.sig ]; then
        gpg --detach-sign --use-agent --local-user $GPGKEY $pkg
    fi
    cp -f $pkg{,.sig} $REPODIR
    repo-add --verify --sign --key $GPGKEY $REPODIR/$REPONAME.db.tar.zst $REPODIR/$(basename $pkg)
done
