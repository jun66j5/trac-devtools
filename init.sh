#! /bin/sh

set -ex
arcdir="$HOME/arc"
venvroot="$HOME/venv"

LC_ALL=en_US.UTF8
TMP=/dev/shm/tmp
export TMP LC_ALL
[ -d "$TMP" ] || mkdir -m 1777 "$TMP"

if [ $# -eq 0 ]; then
    set py24 py25 py26 py27 \
        py24-0.11 py25-0.11 py26-0.11 py27-0.11 \
        py24-0.12 py25-0.12 py26-0.12 py27-0.12 \
        py25-1.0  py26-1.0  py27-1.0 \
        py25-1.1  py26-1.1  py27-1.1
fi

for i in "$@"; do
    python=
    case "$i" in
        py24*) python=/usr/bin/python2.4 ;;
        py25*) python=/usr/bin/python2.5 ;;
        py26*) python=/usr/bin/python2.6 ;;
        py27*) python=/usr/bin/python2.7 ;;
    esac
    venvdir="$venvroot/$i"
    rm -rf "$venvdir"
    /usr/bin/virtualenv -p "$python" --no-site-packages --unzip-setuptools \
        --never-download "$venvdir"
    python="$venvdir/bin/python"

    case "$i" in
    py2?)
        "$venvdir/bin/pip" install -q --download-cache="$HOME/arc/pip" \
            MySQL-python Pygments docutils lxml pytz twill==0.9.1
        case "$i" in
        py24*)
            "$venvdir/bin/pip" install -q --download-cache="$HOME/arc/pip" \
                pysqlite psycopg2==2.4.6 Babel==0.9.6 configobj==4.7.2
            ;;
        py25*)
            "$venvdir/bin/pip" install -q --download-cache="$HOME/arc/pip" \
                psycopg2==2.5.2 Babel==0.9.6 configobj==4.7.2
            ;;
        *)
            "$venvdir/bin/pip" install -q --download-cache="$HOME/arc/pip" \
                psycopg2 Babel configobj sphinx
            "$venvdir/bin/pip" uninstall -q -y sphinx
        esac

        rm -rf "$TMP/swig-1.3.40"
        tar xzf "$arcdir/swig-1.3.40.tar.gz" -C "$TMP"
        (cd "$TMP/swig-1.3.40" &&
            PYTHON="$python" ./configure --with-python="$python" &&
            make)
        rm -rf "$TMP/subversion-1.6.23"
        tar xjf "$arcdir/subversion-1.6.23.tar.bz2" -C "$TMP"
        (cd "$TMP/subversion-1.6.23" &&
            PYTHON="$python" "$python" gen-make.py --installed-libs \
                libsvn_client,libsvn_delta,libsvn_diff,libsvn_fs,libsvn_fs_base,libsvn_fs_fs,libsvn_fs_util,libsvn_ra,libsvn_ra_local,libsvn_ra_serf,libsvn_ra_svn,libsvn_repos,libsvn_subr,libsvn_wc,libsvn_ra_neon &&
            PYTHON="$python" ./configure --prefix="$venvdir" --with-swig="$TMP/swig-1.3.40/swig" &&
            make swig-py &&
            make install-swig-py &&
            mv "$venvdir"/lib/svn-python/* "$venvdir"/lib/python2.?/site-packages/)
        "$python" -c 'from svn import core'
        rm -rf "$TMP/swig-1.3.40" "$TMP/subversion-1.6.23"
        ;;

    py2?-*.*)
        pyminor=`expr "$i" : "py2\\([4-7]\\)"`
        pyver=py2$pyminor
        pyname=python2.$pyminor
        rm -rf "$venvdir/lib/$pyname/site-packages"
        cp -al "$venvroot/$pyver/lib/$pyname/site-packages" "$venvdir/lib/$pyname/site-packages"
        case "$i" in
        py2[67]-*.*)
            "$venvdir/bin/pip" install -q --download-cache="$HOME/arc/pip" sphinx
        esac
        ;;
    esac

    case $i in
    *-0.11|*-0.12)
        (cd "$HOME/src/genshi-0.6.x" &&
            rm -rf build &&
            "$python" setup.py -q clean -a egg_info -r &&
            "$python" setup.py -q --with-speedup install --root=/)
        ;;
    *-1.0)
        (cd "$HOME/src/genshi-0.7.x" &&
            rm -rf build &&
            "$python" setup.py -q clean -a egg_info -r &&
            "$python" setup.py -q --with-speedup install --root=/)
        ;;
    *-1.1)
        (cd "$HOME/src/genshi-0.8.x" &&
            rm -rf build &&
            "$python" setup.py -q clean -a egg_info &&
            "$python" setup.py -q --with-speedup install --root=/)
        ;;
    esac
done
