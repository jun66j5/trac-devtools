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

_dirname() {
    local progname="$0"
    if [ -h "$progname" ]; then
        progname="`readlink -f \"$progname\"`"
    fi
    echo "`dirname \"$progname\"`/"
    return 0
}

type="$1"
shift 2
case "$type" in
admin|server|nginx)
    if [ $# = 0 ]; then
        echo "Requires a directory of Trac Environment" 1>&2
        exit 1
    fi
    ;;
esac
case "$type" in
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
python)
    exec "$venv/bin/python"
    ;;
esac
