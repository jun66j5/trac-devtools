#! /bin/sh

set -e
arcdir="$HOME/arc"
venvroot="$HOME/venv"

LC_ALL=en_US.UTF8
TMP=/dev/shm/tmp
export TMP LC_ALL

cd "$HOME"

if [ $# -eq 0 ]; then
    set 0.11 0.11.1 0.11.2 0.11.3 0.11.4 0.11.5 0.11.6 0.11.7 \
        0.12 0.12.1 0.12.2 0.12.3 0.12.4 0.12.5 \
        1.0 1.0.1 \
        1.1.1
fi

for i in "$@"; do
    repos=
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
    *)
        echo "Skipped '$i'"
        continue
        ;;
    esac
    tracver=`expr "$i" : "\\([0-9]*[.][0-9]*\\)"`
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
    "$venvdir/bin/pip" install -q --download-cache="$HOME/arc/pip" "http://download.edgewall.org/trac/Trac-$i.tar.gz"
    "$venvdir/bin/python" -c 'from trac import __version__'
    echo " done."
done
