#! /bin/sh

set -e

tmpdir=
arcdir="$HOME/arc"
venvroot="$HOME/venv"
py3c_version='1.1'
svn_repos_root='https://svn.apache.org/repos/asf/subversion'

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

LC_ALL=en_US.UTF8
TMP=/dev/shm
export TMP LC_ALL
[ -d "$TMP" ] || mkdir -m 1777 "$TMP"

if [ $# -eq 0 ]; then
    echo "Usage: $0 pyver ..." 1>&2
    exit 1
fi

system_svnver="$(/usr/bin/svn --version --quiet)"
n_jobs="$(expr $(nproc) + 1)"

for i in "$@"; do
    case "$i" in
    py2*-svn110)
        svnver=1.10.7
        pyver="${i%-svn110}"
        ;;
    py[23]*-svn11[4-9])
        svnver=1.14.1
        pyver="${i%-svn11[4-9]}"
        ;;
    py[23]*)
        svnver=1.14.1
        pyver="$i"
        ;;
    *)
        svnver="$system_svnver"
        pyver="$i"
        ;;
    esac
    python=
    case "$pyver" in
    py2[4-7]|py3[4-9]|py3[1-9][0-9]|py[4-9][0-9])
        python="/usr/bin/python$(echo "$pyver" | sed -e 's/^py//; s/^[23]/&./')"
        ;;
    *)
        echo "Skipped $i" 1>&2;
        continue
        ;;
    esac
    venvdir="$venvroot/$i"
    rm -rf "$venvdir"
    venvver=
    venvlib=
    case "$pyver" in
    py24)
        venvver=1.7.2 ;;
    py25)
        venvver=1.9.1 ;;
    py26)
        venvlib="virtualenv-15.2.0-py2.py3-none-any.whl" ;;
    py27|py3[45])
        venvlib="virtualenv-16.7.9-py2.py3-none-any.whl" ;;
    py3[6-9]|py3[1-9][0-9]|py4[0-9])
        venvlib=venv ;;
    esac
    if [ "$venvlib" = venv ]; then
        "$python" -m venv --without-pip "$venvdir"
        _init_tmpdir
        tar xaf "$arcdir/setuptools-53.1.0.tar.gz" -C "$tmpdir"
        (
            cd "$tmpdir"/setuptools-*
            "$venvdir/bin/python" setup.py -q install
        )
        tar xaf "$arcdir/pip-21.0.1.tar.gz" -C "$tmpdir"
        (
            cd "$tmpdir"/pip-*
            "$venvdir/bin/python" setup.py -q install
        )
        "$venvdir/bin/python" -m pip install \
            --no-cache-dir --no-python-version-warning -U pip setuptools
        "$venvdir/bin/python" -m pip install \
            --no-cache-dir --no-python-version-warning wheel
    elif [ -n "$venvlib" ]; then
        _init_tmpdir
        unzip -xq "$arcdir/$venvlib" -d "$tmpdir/libs"
        PYTHONPATH="$tmpdir/libs" "$python" -m virtualenv \
            -q --unzip-setuptools --never-download "$venvdir"
        "$venvdir/bin/python" -m pip install \
            --no-cache-dir -U pip setuptools wheel
    elif [ -n "$venvver" ]; then
        _init_tmpdir
        tar xaf "$arcdir/virtualenv-$venvver.tar.gz" -C "$tmpdir"
        PYTHONPATH="$tmpdir/virtualenv-$venvver" "$python" -m virtualenv \
            -q --unzip-setuptools --never-download "$venvdir"
        "$venvdir/bin/python" -m pip install \
            --no-cache-dir -U pip setuptools wheel
    else
        echo 'Unable to create virtualenv' 1>&2
        exit 1
    fi
    python="$venvdir/bin/python"
    print_sitelib='import distutils.sysconfig as c; print(c.get_python_lib())'
    sitedir="$("$python" -c "$print_sitelib")"

    case "$pyver" in
    py2[45])
        ssl_version=1.16
        "$venvdir/bin/pip" install \
            --no-cache-dir "$arcdir/ssl-${ssl_version}.tar.gz"
        ;;
    esac

    requires='pytz uWSGI mod-wsgi'
    pysqlite_version=
    pysqlite3_version=
    sqlite_version=3350500
    case "$pyver" in
        py2*) requires="$requires MySQL-python twill==0.9.1" ;;
        py3*) requires="$requires pymysql" ;;
    esac
    case "$pyver" in
    py24)
        requires="$requires \
            psycopg2==2.4.6 Genshi<0.7dev Babel==0.9.6 configobj==4.7.2
            coverage==3.7.1 mercurial==3.4.2 lxml<3.4.0dev Pygments<2.0dev
            textile==2.1.5 docutils"
        pysqlite_version=2.5.6
        ;;
    py25)
        requires="$requires \
            psycopg2==2.5.2 Genshi<0.7dev Babel==0.9.6 configobj==4.7.2
            coverage==3.7.1 mercurial==3.4.2 lxml<3.4.0dev Pygments<2.0dev
            textile==2.1.5 psutil<2.2.0 docutils"
        pysqlite_version=2.7.0
        ;;
    py26)
        requires="$requires \
            psycopg2 Genshi Babel configobj coverage lxml<4.3.0 Pygments
            mercurial==4.2.2 textile<3dev memory_profiler psutil docutils"
        pysqlite_version=2.7.0
        ;;
    py27)
        requires="$requires \
            psycopg2 Genshi Babel Jinja2<3 configobj pytidylib selenium
            coverage lxml Pygments mercurial textile<4dev html2rest sphinx<2dev
            pymysql memory_profiler psutil docutils pytest"
        pysqlite_version=2.8.3
        ;;
    py34)
        requires="$requires \
            psycopg2 Babel Jinja2<3 configobj pytidylib selenium coverage
            lxml<4.4.0 Pygments mercurial textile sphinx memory_profiler
            psutil docutils<0.17 pytest"
        pysqlite3_version=0.4.6
        ;;
    py35)
        requires="$requires \
            psycopg2 Babel Jinja2<3 configobj pytidylib selenium coverage
            lxml Pygments mercurial textile sphinx memory_profiler psutil
            docutils<0.17 pytest"
        pysqlite3_version=0.4.6
        ;;
    py3*)
        requires="$requires \
            psycopg2 Babel Jinja2<3 configobj pytidylib selenium coverage lxml
            Pygments mercurial textile sphinx memory_profiler psutil docutils
            pytest"
        pysqlite3_version=0.4.6
        ;;
    esac
    "$venvdir/bin/python" -m pip install \
        --no-cache-dir --no-python-version-warning $requires

    if [ -n "$pysqlite3_version" ]; then
        pysqlite_tarball="$arcdir/pysqlite3-${pysqlite3_version}.tar.gz"
    elif [ -n "$pysqlite_version" ]; then
        pysqlite_tarball="$arcdir/pysqlite-${pysqlite_version}.tar.gz"
    else
        pysqlite_tarball=
    fi
    if [ -n "$pysqlite_tarball" ]; then
        _init_tmpdir
        tar xaf "$pysqlite_tarball" -C "$tmpdir"
        (
            set -e
            cd "$tmpdir"/pysqlite*
            tar xaf "$arcdir/sqlite-autoconf-${sqlite_version}.tar.gz"
            mv -v "sqlite-autoconf-${sqlite_version}/sqlite3".[ch] .
            CFLAGS="-DSQLITE_ENABLE_FTS5" "$venvdir/bin/python" setup.py build_static
            if [ -n "$pysqlite3_version" ]; then
                "$venvdir/bin/python" setup.py install --single-version-externally-managed --root=/
            else
                "$venvdir/bin/python" setup.py install
            fi
        )
    fi

    case "$pyver" in
    py2*)
        _init_tmpdir
        swig_version='3.0.12'
        tar xaf "$arcdir/swig-${swig_version}.tar.gz" -C "$tmpdir"
        (
            set -e
            . "$venvdir/bin/activate"
            cd "$tmpdir/swig-${swig_version}"
            ./configure --prefix="$venvdir"
            make "-j${n_jobs}"
            make install
        )
        case "$svnver" in
        1.14.*)
            tar xavf "$arcdir/py3c-${py3c_version}.tar.gz" -C "$tmpdir"
            tar xaf "$arcdir/subversion-$svnver.tar.bz2" -C "$tmpdir"
            (
                set -e
                cd "$tmpdir/subversion-$svnver"
                . "$venvdir/bin/activate"
                ./autogen.sh
                ./configure --prefix="$venvdir" \
                            --with-swig="$venvdir/bin/swig" \
                            --with-py3c="$tmpdir/py3c-${py3c_version}" \
                            PYTHON="$python" PERL=none RUBY=none
                make "-j${n_jobs}" \
                    swig_pydir="${sitedir}/libsvn" \
                    swig_pydir_extra="${sitedir}/svn" \
                    all swig-py
                make \
                    swig_pydir="${sitedir}/libsvn" \
                    swig_pydir_extra="${sitedir}/svn" \
                    install install-swig-py
            )
            ;;
        1.10.*)
            tar xaf "$arcdir/subversion-$svnver.tar.bz2" -C "$tmpdir"
            (
                set -e
                cd "$tmpdir/subversion-$svnver"
                . "$venvdir/bin/activate"
                ./autogen.sh
                ./configure --prefix="$venvdir" \
                            --with-swig="$venvdir/bin/swig" \
                            PYTHON="$python" PERL=none RUBY=none
                make "-j${n_jobs}" \
                    swig_pydir="${sitedir}/libsvn" \
                    swig_pydir_extra="${sitedir}/svn" \
                    all swig-py
                make \
                    swig_pydir="${sitedir}/libsvn" \
                    swig_pydir_extra="${sitedir}/svn" \
                    install install-swig-py
            )
            ;;
        trunk|1.*.x)
            if [ "$svnver" = trunk ]; then
                repos_url="$svn_repos_root/trunk/"
            else
                repos_url="$svn_repos_root/branches/$svnver/"
            fi
            _init_tmpdir
            (
                set -e
                . "$venvdir/bin/activate"
                tar xavf "$arcdir/py3c-${py3c_version}.tar.gz" -C "$tmpdir"
                svn export "$repos_url" "$tmpdir/subversion"
                cd "$tmpdir/subversion"
                ./autogen.sh
                ./configure --prefix="$venvdir" \
                            --with-swig="$venvdir/bin/swig" \
                            --with-py3c="$tmpdir/py3c-${py3c_version}" \
                            PYTHON="$python" PERL=none RUBY=none
                make "-j${n_jobs}" \
                     swig_pydir="${sitedir}/libsvn" \
                     swig_pydir_extra="${sitedir}/svn" \
                     all swig-py
                make swig_pydir="${sitedir}/libsvn" \
                     swig_pydir_extra="${sitedir}/svn" \
                     install install-swig-py
            )
            ;;
        "$system_svnver")
            tar xaf "$arcdir/subversion-$svnver.tar.bz2" -C "$tmpdir"
            (
                set -e
                cd "$tmpdir/subversion-$svnver"
                sed -i -e 's/-0x20[567]0000}$/-0x2040000}/' build/find_python.sh
                /usr/bin/python2.7 gen-make.py \
                    --installed-libs $(cd /usr/lib/x86_64-linux-gnu &&
                                       echo libsvn_*.la | sed -e 's/-[^-]*\.la//g; s/ /,/g')
                ./configure --prefix="$venvdir" \
                            --with-swig="/usr/bin/swig2.0" \
                            PYTHON="$python" PERL=none RUBY=none
                make "-j${n_jobs}" \
                     swig_pydir="${sitedir}/libsvn" \
                     swig_pydir_extra="${sitedir}/svn" \
                     swig-py
                make swig_pydir="${sitedir}/libsvn" \
                     swig_pydir_extra="${sitedir}/svn" \
                     install-swig-py
            )
            ;;
        *)
            ;;
        esac
        ;;
    py3*)
        swig_version='4.0.2'
        _init_tmpdir
        tar xaf "$arcdir/swig-${swig_version}.tar.gz" -C "$tmpdir"
        (
            set -e
            . "$venvdir/bin/activate"
            cd "$tmpdir/swig-$swig_version"
            ./configure --prefix="$venvdir"
            make "-j${n_jobs}"
            make install
        )
        (
            set -e
            . "$venvdir/bin/activate"
            tar xaf "$arcdir/py3c-${py3c_version}.tar.gz" -C "$tmpdir"
            tar xaf "$arcdir/subversion-$svnver.tar.bz2" -C "$tmpdir"
            cd "$tmpdir/subversion-$svnver"
            ./autogen.sh
            ./configure --prefix="$venvdir" \
                        --with-swig="$venvdir/bin/swig" \
                        --with-py3c="$tmpdir/py3c-${py3c_version}" \
                        PYTHON="$python" PERL=none RUBY=none
            rm -f subversion/bindings/swig/proxy/swig_*_external_runtime.swg
            make "-j${n_jobs}" \
                 swig_pydir="${sitedir}/libsvn" \
                 swig_pydir_extra="${sitedir}/svn" \
                 all swig-py
            make swig_pydir="${sitedir}/libsvn" \
                 swig_pydir_extra="${sitedir}/svn" \
                 install install-swig-py
        )
        ;;
    esac
    "$python" -c 'from svn import core'
    echo "Created $venvdir"
done
