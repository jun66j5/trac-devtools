#! /bin/sh

set -e
arcdir="$HOME/arc"
venvroot="$HOME/venv"
svnver=1.8.8

LC_ALL=en_US.UTF8
TMP=/dev/shm
export TMP LC_ALL
[ -d "$TMP" ] || mkdir -m 1777 "$TMP"

if [ $# -eq 0 ]; then
    set py27      py26      py25      py24 \
        py27-0.11 py26-0.11 py25-0.11 py24-0.11 \
        py27-0.12 py26-0.12 py25-0.12 py24-0.12 \
        py27-1.0  py26-1.0  py25-1.0 \
        py27-1.1  py26-1.1
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
    case "$i" in
    py2[45]*)
        rm -rf "$TMP/virtualenv-1.7.2"
        tar xzf "$arcdir/virtualenv-1.7.2.tar.gz" -C "$TMP"
        PYTHONPATH="$TMP/virtualenv-1.7.2" "$python" -m virtualenv \
            -p "$python" --unzip-setuptools --never-download "$venvdir"
        rm -rf "$TMP/virtualenv-1.7.2"
        ;;
    *)
        /usr/bin/virtualenv \
            -p "$python" --unzip-setuptools --never-download "$venvdir"
        ;;
    esac
    python="$venvdir/bin/python"

    case "$i" in
    py2?)
        "$venvdir/bin/pip" install -q --download-cache="$HOME/arc/pip" \
            MySQL-python docutils pytz twill==0.9.1 uWSGI
        case "$i" in
        py24)
            "$venvdir/bin/pip" install -q --download-cache="$HOME/arc/pip" \
                psycopg2==2.4.6 Babel==0.9.6 configobj==4.7.2 coverage==3.7.1 \
                mercurial==3.4.2 'lxml<3.4.0dev' 'Pygments<2.0dev'
            pysqlite_version=2.5.6
            sqlite_version=3071501
            tar xzf "$HOME/arc/pysqlite-${pysqlite_version}.tar.gz" -C "$TMP"
            unzip -x "$HOME/arc/sqlite-amalgamation-${sqlite_version}.zip" -d "$TMP/pysqlite-2.5.6"
            (
                cd "$TMP/pysqlite-${pysqlite_version}"
                mv "sqlite-amalgamation-${sqlite_version}" amalgamation
                "$venvdir/bin/python" setup.py build_static install
            )
            ;;
        py25)
            "$venvdir/bin/pip" install -q --download-cache="$HOME/arc/pip" \
                psycopg2==2.5.2 Babel==0.9.6 configobj==4.7.2 coverage==3.7.1 \
                mercurial==3.4.2 'pysqlite<2.8.0' 'lxml<3.4.0dev' \
                'Pygments<2.0dev'
            ;;
        py26)
            "$venvdir/bin/pip" install -q --download-cache="$HOME/arc/pip" \
                psycopg2 Babel Jinja2 configobj coverage lxml Pygments \
                mercurial 'pysqlite<2.8.0' memory_profiler psutil
            ;;
        py27)
            "$venvdir/bin/pip" install -q --download-cache="$HOME/arc/pip" \
                psycopg2 Babel Jinja2 configobj coverage lxml Pygments \
                mercurial pysqlite html2rest sphinx memory_profiler psutil
            ;;
        esac

        rm -rf "$TMP/subversion-$svnver"
        tar xjf "$arcdir/subversion-$svnver.tar.bz2" -C "$TMP"
        (
            cd "$TMP/subversion-$svnver"
            sed -i -e 's/-0x2050000}$/-0x2040000}/' build/find_python.sh
            /usr/bin/python2.7 gen-make.py \
                --installed-libs $(cd /usr/lib/x86_64-linux-gnu &&
                                   echo libsvn_*.la | sed -e 's/-[^-]*\.la//g; s/ /,/g')
            PYTHON="$python" ./configure --prefix="$venvdir" --with-swig="/usr/bin/swig"
            make swig-py install-swig-py
            mv -v "$venvdir"/lib/svn-python/* "$venvdir"/lib/python2.?/site-packages/
        )
        "$python" -c 'from svn import core'
        rm -rf "$TMP/subversion-$svnver"
        ;;

    py2?-*.*)
        pyminor=`expr "$i" : "py2\\([4-7]\\)"`
        pyver=py2$pyminor
        pyname=python2.$pyminor
        rm -rf "$venvdir/lib/$pyname/site-packages"
        cp -al "$venvroot/$pyver/lib/$pyname/site-packages" "$venvdir/lib/$pyname/site-packages"
        for f in "$venvroot/$pyver"/bin/*; do
            t="$venvdir/bin/`basename \"$f\"`"
            if [ "`head -1 \"$f\"`" = "#!$venvroot/$pyver/bin/$pyname" ]; then
                { echo "#!$venvdir/bin/$pyname"; tail -n +2 "$f"; } >"$t"
                chmod --reference="$f" "$t"
            elif [ ! -f "$t" ]; then
                ln "$f" "$t"
            fi
        done
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
