#! /bin/sh

set -e
arcdir="$HOME/arc"
venvroot="$HOME/venv"
repos_root=http://svn.edgewall.org/repos/trac

LC_ALL=en_US.UTF8
TMP=/dev/shm/tmp
export TMP LC_ALL

cd "$HOME"

if [ $# -eq 0 ]; then
    set 0.11 0.11.1 0.11.2 0.11.3 0.11.4 0.11.5 0.11.6 0.11.7 \
        0.12 0.12.1 0.12.2 0.12.3 0.12.4 0.12.5 0.12.6 \
        1.0 1.0.1 1.0.2 1.0.3 \
        1.1.1 1.1.2 1.1.3
fi

for i in "$@"; do
    repos=
    tracver=
    case "$i" in
    0.11|0.11.*)
        pyminor=4
        ;;
    0.12|0.12.*)
        pyminor=4
        ;;
    1.0|1.0.*)
        pyminor=5
        ;;
    1.1|1.1.*)
        pyminor=6
        ;;
    0.11-stable)
        pyminor=4
        tracver=0.11
        repos=$repos_root/branches/0.11-stable
        ;;
    0.12-stable)
        pyminor=4
        tracver=0.12
        repos=$repos_root/branches/0.12-stable
        ;;
    1.0-stable)
        pyminor=5
        tracver=1.0
        repos=$repos_root/branches/1.0-stable
        ;;
    trunk)
        pyminor=6
        tracver=1.1
        repos=$repos_root/trunk
        ;;
    *)
        echo "Skipped '$i'"
        continue
        ;;
    esac
    if [ -z "$tracver" ]; then
        tracver=`expr "$i" : "\\([0-9]*[.][0-9]*\\)"`
    fi
    pyver=py2$pyminor
    pyname=python2.$pyminor
    venvdir="$venvroot/trac/$i"
    echo -n "Creating $venvdir..."
    rm -rf "$venvdir"
    /usr/bin/virtualenv -q -p /usr/bin/$pyname --unzip-setuptools \
        --never-download "$venvdir"
    rm -rf "$venvdir/lib/$pyname/site-packages"/*
    test -d "$venvroot/$pyver-$tracver/lib/$pyname/site-packages"
    (
        cd "$venvdir/lib/$pyname/site-packages"
        ln -s ../../../../../$pyver/lib/$pyname/site-packages/* .
        ln -s ../../../../../$pyver-$tracver/lib/$pyname/site-packages/genshi .
        ln -s ../../../../../$pyver-$tracver/lib/$pyname/site-packages/Genshi-*.egg-info .
    )
    if [ -n "$repos" ]; then
        tmpdir="`mktemp -d -p $TMP`"
        svn co -q "$repos" "$tmpdir" || :
        "$venvdir/bin/pip" install -q --download-cache="$HOME/arc/pip" "$tmpdir" || :
        rm -rf "$tmpdir"
    else
        "$venvdir/bin/pip" install -q --download-cache="$HOME/arc/pip" "http://download.edgewall.org/trac/Trac-$i.tar.gz"
    fi
    "$venvdir/bin/python" -c 'from trac import __version__'
    echo " done."
done
