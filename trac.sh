#! /bin/sh

if [ $# -lt 2 ]; then
    echo "Usage: $0 admin|server|nginx|python tracver|venv-dir env [...]"
    exit 1
fi

venv=
case "$2" in
*/)
    venv="${2%/}"
    ;;
*/*)
    venv="${2}"
    ;;
*)
    venv="$HOME/venv/trac/${2}"
    ;;
esac
if [ ! -x "$venv/bin/python" ]; then
    echo "$2 is invalid." 1>&2
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

_dirname() {
    local progname="$0"
    if [ -h "$progname" ]; then
        progname="`readlink -f \"$progname\"`"
    fi
    local dir="`dirname \"$progname\"`"
    [ "$dir" = . ] && dir="$PWD"
    [ "$dir" != / ] && dir="$dir/"
    echo "$dir"
    return 0
}

case "$cmd" in
admin)
    exec "$venv/bin/trac-admin" "$@"
    ;;
server)
    passwd="`_dirname`htpasswd.txt"
    exec "$venv/bin/tracd" -p 3000 --basic-auth "*,$passwd,auth" "$@"
    ;;
nginx)
    conf="`_dirname`nginx.conf"
    nginx -c "$conf"
    trap "nginx -c \"$conf\" -s stop" INT
    TRAC_ENV="$1" "$venv/bin/uwsgi" -s 127.0.0.1:3001 -w trac.web.main:dispatch_request
    ;;
modwsgi)
    if [ ! -d "$venv/lib/python2.7" ]; then
        echo "Require python2.7, $venv is using `cd \"$venv\"/lib && echo python2.?`."
        exit 1
    fi
    tmpdir=`mktemp -d /dev/shm/modwsgi-XXXXXX`
    trap _cleanup 0 1 2 3 15
    echo 'from trac.web.main import dispatch_request as application' >$tmpdir/trac.wsgi
    _PWD="`_dirname`"
    _VENVDIR="$venv"
    _TMPDIR="$tmpdir"
    TRAC_ENV="$1"
    export _PWD _VENVDIR _TMPDIR TRAC_ENV
    /usr/sbin/apache2 -X -f "${_PWD}modwsgi.conf"
    ;;
modpython)
    if [ ! -d "$venv/lib/python2.7" ]; then
        echo "Require python2.7, $venv is using `cd \"$venv\"/lib && echo python2.?`."
        exit 1
    fi
    . "$venv/bin/activate"
    tmpdir=`mktemp -d /dev/shm/modpython-XXXXXX`
    trap _cleanup 0 1 2 3 15
    _PWD="`_dirname`"
    _VENVDIR="$venv"
    _TMPDIR="$tmpdir"
    TRAC_ENV="$1"
    export _PWD _VENVDIR _TMPDIR TRAC_ENV
    /usr/sbin/apache2 -X -f "${_PWD}modpython.conf"
    ;;
python)
    exec "$venv/bin/python"
    ;;
esac
