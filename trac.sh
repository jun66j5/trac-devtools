#! /bin/sh

if [ $# -lt 2 ]; then
    echo "\
Usage: ${0##*/} <command> tracver|venv-dir [...]

Available commands:

  admin         Start trac-admin with env
  develop       Install as an egg-link into env/plugins
  install-egg   Install as an egg into env/plugins
  modfcgid      Start apache/mod_fcgid with env
  modpython     Start apache/mod_python with env
  modwsgi       Start apache/mod_wsgi with env
  nginx-fcgi    Start nginx/fcgi with env
  nginx-tracd   Start nginx/tracd with env
  nginx-uwsgi   Start nginx/uwsgi with env
  python        Start python interpreter
  server        Start tracd server with env
  tracd         Start tracd server with env
  uwsgi         Start uwsgi server with env
  waitress      Start waitress server with env
"
    exit 1
fi

venv=
case "$2" in
/*/)
    venv="${2%/}"
    ;;
/*/*)
    venv="${2}"
    ;;
*)
    venv="$HOME/venv/trac/${2}"
    ;;
esac

python="$venv/bin/python"
if [ ! -x "$python" ]; then
    echo "$2 is invalid." 1>&2
    exit 1
fi

if ! (cd / && "$python" -c 'import trac') 2>/dev/null; then
    PYTHONPATH="$PWD"
    export PYTHONPATH
fi
if ! "$python" -c 'import trac' 2>/dev/null; then
    echo "Missing trac" 1>&2
    exit 1
fi

cmd="$1"
shift 2
if [ "$cmd" != python -a $# = 0 ]; then
    echo "Requires a directory of Trac Environment" 1>&2
    exit 1
fi

tmpdir=

_cleanup() {
    if [ "x$tmpdir" != x -a -d "$tmpdir" ]; then
        rm -rf "$tmpdir"
    fi
}

trap _cleanup 0 1 2 3 15

_dirname() {
    local progname="$0"
    if [ -h "$progname" ]; then
        progname="$(readlink -f "$progname")"
    fi
    local dir="$(dirname "$progname")"
    [ "$dir" = . ] && dir="$PWD"
    [ "$dir" != / ] && dir="$dir/"
    echo "$dir"
    return 0
}

_sitedir() {
    echo "$("$python" -c '\
        import os, sys; \
        print(os.path.join(sys.prefix, "lib", \
                           "python{0}.{1}".format(*sys.version_info), \
                           "site-packages")); \
        ')"
}

case "$cmd" in
admin)
    if [ -x "$venv/bin/tracd" ]; then
        exec "$venv/bin/trac-admin" "$@"
    else
        exec "$python" -m trac.admin.console "$@"
    fi
    ;;
server|tracd)
    passwd="`_dirname`htpasswd.txt"
    if [ -x "$venv/bin/tracd" ]; then
        exec "$venv/bin/tracd" -p 3000 --basic-auth "*,$passwd,auth" "$@"
    else
        exec "$python" -m trac.web.standalone -p 3000 --basic-auth "*,$passwd,auth" "$@"
    fi
    ;;
install-egg)
    dir="$1/plugins"
    shift
    [ $# -eq 0 ] && set .
    for i in "$@"; do
        PYTHONPATH="$dir" "$venv/bin/easy_install" -ZU -d "$dir" "$i"
    done
    ;;
develop)
    dir="$1/plugins"
    shift
    [ $# -eq 0 ] && set .
    for i in "$@"; do
        (cd "$i" && "$python" setup.py develop -mxd "$dir")
    done
    ;;
nginx-uwsgi)
    conf="`_dirname`nginx.conf"
    nginx -c "$conf"
    trap "nginx -c \"$conf\" -s stop" INT
    TRAC_ENV="$1" "$venv/bin/uwsgi" -s 127.0.0.1:3001 -w trac.web.main:dispatch_request
    ;;
nginx-tracd)
    dir="`_dirname`"
    passwd="$dir/htpasswd.txt"
    conf="$dir/nginx-tracd.conf"
    nginx -c "$conf"
    trap "nginx -c \"$conf\" -s stop" INT
    TRAC_ENV="$1" "$venv/bin/tracd" -p 3001 -s --basic-auth "*,$passwd,auth" "$@"
    ;;
nginx-fcgi)
    dir="`_dirname`"
    passwd="$dir/htpasswd.txt"
    conf="$dir/nginx-fcgi.conf"
    nginx -c "$conf"
    trap "nginx -c \"$conf\" -s stop" INT
    TRAC_ENV="$1" "$python" trac.fcgi /dev/shm/nginx.fastcgi.sock
    ;;
modwsgi)
    _WSGI_MODULE="$("$python" -c "\
from mod_wsgi import server
import os.path, glob
filename = os.path.join(os.path.dirname(server.__file__), 'mod_wsgi-*.so')
for p in glob.glob(filename):
    print(p)
    break
")"
    if [ -z "$_WSGI_MODULE" ]; then
        echo "Missing mod_wsgi-*.so in $venv" 1>&2
        exit 1
    fi
    tmpdir="$(mktemp -d /dev/shm/modwsgi-XXXXXX)"
    cat <<__EOS__ >$tmpdir/trac.wsgi
from trac.web.main import dispatch_request
def application(environ, start_response):
    environ['trac.env_paths'] = ['$1']
    return dispatch_request(environ, start_response)
__EOS__
    svnadmin create "$tmpdir/svn"
    svn mkdir -m initial "file://$tmpdir/svn/trunk" \
        "file://$tmpdir/svn/branches" "file://$tmpdir/svn/tags"
    _PWD="$(_dirname)"
    _SITEDIR="$(_sitedir)"
    _TMPDIR="$tmpdir"
    export _PWD _SITEDIR _TMPDIR _WSGI_MODULE
    /usr/sbin/apache2 -DFOREGROUND -f "${_PWD}modwsgi.conf"
    ;;
uwsgi)
    TRAC_ENV="$1" "$venv/bin/uwsgi" --http 0.0.0.0:3000 --master -w trac.web.main:dispatch_request
    ;;
waitress)
    TRAC_ENV="$1" "$venv/bin/waitress-serve" --port=3000 trac.web.main:dispatch_request
    ;;
modfcgid)
    tmpdir="$(mktemp -d /dev/shm/modfcgid-XXXXXX)"
    mkdir "$tmpdir/modfcgid" "$tmpdir/tracenv"
    ln -s "$1" "$tmpdir/tracenv"
    cat <<__EOS__ >$tmpdir/trac.fcgi
#! $python
try:
    from trac.web.fcgi_frontend import run
    run()
except SystemExit:
    raise
except Exception as e:
    import io, sys, traceback
    with io.StringIO() as out:
        out.write("Oops...\n"
                  "\n"
                  "Trac detected an internal error:\n"
                  "\n"
                  "{0}"
                  "\n".format(e))
        traceback.print_exc(file=out)
        stdout = sys.stdout.buffer
        stdout.write(b"Content-Type: text/plain\r\n\r\n")
        stdout.write(out.getvalue().encode('utf-8'))
        stdout.flush()
__EOS__
    chmod a+x $tmpdir/trac.fcgi
    svnadmin create "$tmpdir/svn"
    _PWD="`_dirname`"
    _VENVDIR="$venv"
    _TMPDIR="$tmpdir"
    TRAC_ENV_PARENT_DIR="$tmpdir/tracenv"
    export _PWD _VENVDIR _TMPDIR TRAC_ENV_PARENT_DIR
    /usr/sbin/apache2 -DFOREGROUND -f "${_PWD}modfcgid.conf"
    ;;
modpython)
    _MOD_PYTHON="$venv/libexec/mod_python.so"
    if [ ! -f "$_MOD_PYTHON" ]; then
        echo "Missing $_MOD_PYTHON"
        exit 1
    fi
    . "$venv/bin/activate"
    tmpdir="$(mktemp -d /dev/shm/modpython-XXXXXX)"
    _PWD="`_dirname`"
    _VENVDIR="$venv"
    _TMPDIR="$tmpdir"
    TRAC_ENV="$1"
    export _PWD _VENVDIR _TMPDIR _MOD_PYTHON TRAC_ENV
    if [ -z "$PYTHONPATH" ]; then
        /usr/sbin/apache2 -DFOREGROUND -f "${_PWD}modpython.conf"
    else
        /usr/sbin/apache2 -DFOREGROUND -DPYTHONPATH -f "${_PWD}modpython.conf"
    fi
    ;;
python)
    exec "$python" "$@"
    ;;
*)
    echo "Unrecognized command '$cmd'" 1>&2
    exit 1
    ;;
esac
