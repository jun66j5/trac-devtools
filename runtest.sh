#! /bin/sh
set -e

usage() {
    echo "Usage: $0 [OPTIONS] GIT-DIR [REVs...]"
    exit 127
}
git() {
    LC_ALL=en_US.UTF8 /usr/bin/git --git-dir "$gitdir" "$@"
}
cp() {
    LC_ALL=C /bin/cp "$@"
}
rm() {
    LC_ALL=C /bin/rm "$@"
}
ln() {
    LC_ALL=C /bin/ln "$@"
}
ls() {
    LC_ALL=C /bin/ls "$@"
}
tar() {
    LC_ALL=C /bin/tar "$@"
}
sendmail() {
    LC_ALL=C /usr/lib/sendmail "$@"
}
qprint() {
    LC_ALL=C /usr/bin/qprint "$@"
}

tmpdir=/dev/shm
all_refs=
loop_secs=
pidfile=
update_remotes=
mail=
force=
pythons='24 25 26 27'
databases='sqlite sqlite-file postgres mysql'
timezone=Europe/London
lang=de_DE.UTF8

while [ $# -gt 0 ]; do
    case "$1" in
        --python=*)             pythons="${1#--python=}" ;;
        --db=*)                 databases="${1#--db=}" ;;
        --database=*)           databases="${1#--database=}" ;;
        --lang=*)               lang="${1#--lang=}" ;;
        --tz=*)                 timezone="${1#--tz=}" ;;
        --timezone=*)           timezone="${1#--timezone=}" ;;
        -F|--force)             force=1 ;;
        -A|--all-refs)          all_refs=1 ;;
        -U|--update-remotes)    update_remotes=1 ;;
        --mail=*)               mail="${1#--mail=}" ;;
        --loop=*)               loop_secs="${1#--loop=}" ;;
        --pidfile=*)            pidfile="${1#--pidfile=}" ;;
        --*)                    usage ;;
        *)                      break ;;
    esac
    shift
done
if [ $# -eq 1 ]; then
    [ -z "$all_refs" ] && usage
else
    [ $# -lt 2 ] && usage
fi

dir="`dirname $0`"
[ -z "$dir" ] && exit 127
gitdir="$1"
shift

runtest() {
    local workdir="$1"
    local nrevdir="$2"
    local rev="$3"
    local nrev="$4"
    local startts="`LC_ALL=C /bin/date +%s`"
    local pass=0 fail=0 body= elapse_1= require= version= pids= results= db= msgid=
    local date= subject= base= commits=
    for python in $pythons; do
        require="`sed -n "/^min_python = (\\([2-9]\\), \\([4-9]\\))$/ { s//\\1\\2/; p; q }" "$workdir/src/setup.py"`"
        if [ $python '<' "$require" ]; then
            continue
        fi
        elapse_1="`LC_ALL=C /bin/date +%s`"
        dbname="trac_$elapse_1"
        version="`sed -n "/^ *__version__ = '\\([0-9]*\\.[0-9]*\\)[^']*'*/ { s//\\1/; p; q }" "$workdir/src/trac/__init__.py"`"
        pids=
        echo -n "  Running tests on python$python..."
        for db in $databases; do
            case "$db" in
            sqlite)
                uri=
                ;;
            sqlite-file)
                uri=sqlite:test.db
                ;;
            postgres)
                uri="postgres://tracuser:password@127.0.0.1/trac?schema=$dbname"
                ;;
            mysql)
                uri="mysql://tracuser:password@127.0.0.1/$dbname"
                mysql -utracuser -ppassword mysql \
                    -e "CREATE DATABASE $dbname DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin"
                ;;
            esac
            cp -al "$workdir/src" "$workdir/py$python-$db"
            rm "$workdir/py$python-$db/Makefile.cfg"
            sed -e "s|^\\.uri *=.*|.uri = $uri|" "$workdir/src/Makefile.cfg" \
                >"$workdir/py$python-$db/Makefile.cfg"
            mkdir "$workdir/tmp-py$python-$db"
            TMP="$workdir/tmp-py$python-$db" LANG="$lang" TZ="$timezone" LC_ALL= \
                /bin/sh -c "
                    set -ex
                    cd $workdir/py$python-$db
                    /usr/bin/make \
                        python=$python-$version \
                        pip-freeze Trac.egg-info compile stats unit-test functional-test
                    for i in babel configobj docutils pytz pygments svn pysqlite2; do
                        echo 'raise ImportError(\"No module named \" + __name__)' >\$i.py
                    done
                    /usr/bin/make python=$python-$version unit-test
                " >"$nrevdir/py$python-$db.log" 2>&1 &
            pids="$pids $!"
        done
        results=
        for pid in $pids; do
            if wait $pid; then
                echo -n " [PASS]"
                results="$results [PASS]"
                pass=`expr $pass + 1 || :`
            else
                echo -n " [FAIL]"
                results="$results [FAIL]"
                fail=`expr $fail + 1 || :`
            fi
        done
        for db in $databases; do
            (cd "$workdir" \
                && tar cf - "py$python-$db"/*.log \
                            "py$python-$db"/testenv/trac/log/*.html 2>/dev/null) \
                | tar xf - -C "$nrevdir"
        done
        rm -rf "$workdir/py$python"-* "$workdir/tmp-py$python"-*
        elapse_1=$(expr "`LC_ALL=C /bin/date +%s`" - $elapse_1 || :)
        echo " in $elapse_1 seconds"
        for db in $databases; do
            case "$db" in
            postgres)
                PGPASSWORD=password psql -h 127.0.0.1 -U tracuser trac \
                    -c "DROP SCHEMA $dbname CASCADE" >/dev/null || :
                ;;
            mysql)
                mysql -h127.0.0.1 -utracuser -ppassword mysql \
                    -e "DROP DATABASE $dbname" || :
                ;;
            esac
        done
        body="${body}Python$python$results in $elapse_1 seconds
"
    done
    msgid="$nrev.$startts@localhost"
    elapse=$(expr "`LC_ALL=C /bin/date +%s`" - $startts || :)
    date="`date -R`"
    echo "  Passed $pass, Failed $fail in $elapse seconds at $date"
    if [ -n "$mail" ]; then
        rev="${rev#refs/remotes/}"
        if [ "$fail" = 0 ]; then
            subject="PASS $pass in $elapse seconds on $rev"
        else
            subject="FAIL $fail, PASS $pass in $elapse seconds on $rev"
        fi
        if [ "$rev" != "$nrev" ]; then
            subject="$subject ($nrev)"
        fi
        boundary="__${nrev}_${startts}__"
        {
            echo "\
From: <$mail>
Subject: $subject
To: <$mail>
Date: $date
Message-ID: <$msgid>
MIME-Version: 1.0
Content-Type: multipart/mixed;
	boundary=$boundary
X-Git-Rev: $nrev

--$boundary
Content-Type: text/plain; charset=utf-8

$subject

$body";
            base=
            commits=0
            for branch in mirror/0.12-stable mirror/1.0-stable mirror/trunk; do
                n="`git rev-list $nrev $branch^! | wc -l`"
                if [ "$commits" -eq 0 -o "$n" -lt "$commits" ]; then
                    commits="$n"
                    base="$branch"
                fi
            done
            if [ -n "$base" ]; then
                git log --oneline --left-right --decorate "$nrev" "$base^!"
                echo "--$boundary"
                echo "Content-Type: text/plain; charset=utf-8; name=\"$nrev.diff\""
                echo "Content-Transfer-Encoding: base64"
                echo "Content-Disposition: attachment; filename=\"$nrev.diff\""
                echo
                if [ "$commits" -gt 1 ]; then
                    git log -p --left-only "$nrev...$base" | base64
                else
                    git show "$nrev" | base64
                fi
            fi
            echo "--$boundary"
            echo "Content-Type: application/x-xz; name=\"$nrev.tar.xz\""
            echo "Content-Transfer-Encoding: base64"
            echo "Content-Disposition: attachment; filename=\"$nrev.tar.xz\""
            echo
            tar cf - -C "$nrevdir" . | /usr/bin/xz -9c | base64
            echo "--$boundary--"
        } | sendmail "$mail"
    fi
}

export_and_runtest() {
    local rev="$1" nrevdir="$dir/tests/$rev" nrev=
    [ -d "$nrevdir" ] && return 0
    nrev="`git rev-list "$rev^!" --`"
    nrevdir="$dir/tests/$nrev"
    [ -z "$nrev" ] && return 0
    if [ -d "$nrevdir" ]; then
        [ -z "$force" ] && return 0
        echo -n "Removing $rev..."
        rm -rf "$nrevdir"
        echo " done."
    fi
    if [ "$rev" = "$nrev" ]; then
        echo -n "Exporting $rev..."
    else
        echo -n "Exporting $rev ($nrev)..."
    fi
    mkdir -p "$nrevdir" || :
    workdir="$tmpdir/$nrev"
    [ -d "$workdir" ] && rm -rf "$workdir"
    mkdir "$workdir" "$workdir/src" || :
    git archive --prefix="$nrev/src/" "$nrev" \
        | tar xf - -C "$tmpdir" --touch 2>/dev/null
    cp "$dir/Makefile.cfg" "$workdir/src/Makefile.cfg"
    echo " done."
    runtest "$workdir" "$nrevdir" "$rev" "$nrev"
    rm -rf "$workdir"
}

main() {
    [ -n "$update_remotes" ] && git fetch --all --prune
    [ -n "$all_refs" ] && set `git for-each-ref --format='%(refname)'`
    for rev in "$@"; do
        export_and_runtest "$rev"
    done
}

if [ -n "$pidfile" ]; then
    [ -f "$pidfile" ] && kill -0 "`cat "$pidfile"`" 2>/dev/null && exit 0
    echo -n $$ >"$pidfile"
fi
main "$@"
if [ -n "$loop_secs" ]; then
    while :; do
        echo -n "`date -R`\r"
        sleep "$loop_secs"
        main "$@"
    done
fi
