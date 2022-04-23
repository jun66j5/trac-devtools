#! /bin/sh

set -e
arcdir="$HOME/arc"
venvroot="$HOME/venv"
repos_root=http://svn.edgewall.org/repos/trac

LC_ALL=en_US.UTF8
TMP=/dev/shm

_cleanup() {
    if [ -n "$tmpdir" -a -d "$tmpdir" ]; then
        rm -rf "$tmpdir"
    fi
}

_init_tmpdir() {
    if [ -n "$tmpdir" -a -d "$tmpdir" ]; then
        rm -rf -- "$tmpdir"
    fi
    tmpdir="$(mktemp -d --tmpdir="$TMP" init-XXXXXXXXX)"
}

trap _cleanup 0 1 2 3 15
export TMP LC_ALL

cd "$HOME"

if [ $# -eq 0 ]; then
    set 0.11 0.11.1 0.11.2 0.11.3 0.11.4 0.11.5 0.11.6 0.11.7 \
        0.12 0.12.1 0.12.2 0.12.3 0.12.4 0.12.5 0.12.6 0.12.7 \
        1.0 1.0.1 1.0.2 1.0.3 1.0.4 1.0.5 1.0.6 1.0.7 1.0.8 1.0.9 \
        1.0.10 1.0.11 1.0.12 1.0.13 1.0.14 1.0.15 1.0.17 1.0.18 1.0.19 \
        1.1.1 1.1.2 1.1.3 1.1.4 1.1.5 1.1.6 \
        1.2 1.2.1 1.2.2 1.2.3 1.2.4 1.2.5 \
        1.3.1 1.3.2 1.3.3 1.3.4 1.3.5 1.3.6 \
        1.4 1.4.1 1.4.2 \
        1.5.2 1.5.3
fi

for ver in "$@"; do
    venvdir="$venvroot/trac/$ver"
    repos=
    pymajor=
    pyminor=
    case "$ver" in
    py[23][0-9]*/*)
        pymajor="$(expr "$ver" : 'py\([23]\)')"
        pyminor="$(expr "$ver" : 'py[23]\([0-9]*\)')"
        ver="${ver#py[23]*/}"
        ;;
    py*)
        echo "Skipped '$ver'"
        continue
        ;;
    esac
    case "$ver" in
    0.11|0.11.*)
        [ -z "$pymajor" ] && pymajor=2
        [ -z "$pyminor" ] && pyminor=4
        ;;
    0.12|0.12.*)
        [ -z "$pymajor" ] && pymajor=2
        [ -z "$pyminor" ] && pyminor=4
        ;;
    1.[0124]|1.[0-4].*|1.5.1)
        [ -z "$pymajor" ] && pymajor=2
        [ -z "$pyminor" ] && pyminor=7
        ;;
    1.5.[2-9])
        [ -z "$pymajor" ] && pymajor=3
        [ -z "$pyminor" ] && pyminor=9
        ;;
    0.11-stable)
        [ -z "$pymajor" ] && pymajor=2
        [ -z "$pyminor" ] && pyminor=4
        repos=$repos_root/branches/0.11-stable
        ;;
    0.12-stable)
        [ -z "$pymajor" ] && pymajor=2
        [ -z "$pyminor" ] && pyminor=4
        repos=$repos_root/branches/0.12-stable
        ;;
    1.[024]-stable)
        [ -z "$pymajor" ] && pymajor=2
        [ -z "$pyminor" ] && pyminor=7
        repos="$repos_root/branches/$ver"
        ;;
    trunk)
        [ -z "$pymajor" ] && pymajor=3
        [ -z "$pyminor" ] && pyminor=9
        repos="$repos_root/trunk"
        ;;
    *)
        echo "Skipped '$ver'"
        continue
        ;;
    esac
    pyver=py$pymajor$pyminor
    pyname=python$pymajor.$pyminor
    python=/usr/bin/$pyname
    echo -n "Creating $venvdir..."
    rm -rf -- "$venvdir"
    case "$pyver" in
        py24)   venvlib=1.7.2 ;;
        py25)   venvlib=1.9.1 ;;
        py26)   venvlib=15.2.0 ;;
        py27|py3[45])
                venvlib="virtualenv-16.7.9-py2.py3-none-any.whl" ;;
        py3[6-9]|py3[1-9][0-9]|py4[0-9])
                venvlib=venv ;;
        *)      venvlib= ;;
    esac
    case "$venvlib" in
    venv)
        _init_tmpdir
        "$python" -m venv --without-pip "$venvdir"
        ;;
    *.whl)
        PYTHONPATH="$arcdir/$venvlib" \
            "$python" -m virtualenv -q --unzip-setuptools --never-download \
            "$venvdir"
        ;;
    *)
        _init_tmpdir
        tar xzf "$arcdir/virtualenv-$venvlib.tar.gz" -C "$tmpdir"
        PYTHONPATH="$tmpdir/virtualenv-$venvlib" "$python" -m virtualenv \
            -q --unzip-setuptools --never-download "$venvdir"
        ;;
    esac
    rm -rf "$venvdir/lib/$pyname/site-packages"
    mkdir "$venvdir/lib/$pyname/site-packages"
    echo "$venvroot/$pyver/lib/$pyname/site-packages" >"$venvdir/lib/$pyname/site-packages/.pth"
    case "$ver" in
    1.5.[23])
        "$venvdir/bin/python" -m pip install -q -t "$venvdir/lib/$pyname/site-packages" 'Jinja2<3'
        ;;
    esac
    if [ -n "$repos" ]; then
        "$venvdir/bin/python" -m pip install -q "svn+$repos" || :
    else
        case "$ver" in
            1.0.6) ver="$ver.post2" ;;
        esac
        "$venvdir/bin/python" -m pip install -q "https://download.edgewall.org/trac/Trac-$ver.tar.gz"
    fi
    "$venvdir/bin/python" -c 'from trac import __version__; print(" Trac %s is installed." % __version__)'
done
