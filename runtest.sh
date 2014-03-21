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

tmpdir=/dev/shm
all_refs=
loop_secs=
update_remotes=
mail=
force=
pythons='24 25 26 27'
databases='sqlite postgres mysql'
boundary=_BBB_OOO_UUU_NNN_DDD_AAA_RRR_YYY_

while [ $# -gt 0 ]; do
    case "$1" in
        --python=*)             pythons="${1#--python=}" ;;
        --db=*)                 databases="${1#--db=}" ;;
        --database=*)           databases="${1#--database=}" ;;
        -F|--force)             force=1 ;;
        -A|--all-refs)          all_refs=1 ;;
        -U|--update-remotes)    update_remotes=1 ;;
        --mail=*)               mail="${1#--mail=}" ;;
        --loop=*)               loop_secs="${1#--loop=}" ;;
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
    local pass=0
    local fail=0
    local body=
    local elapse="`LC_ALL=C /bin/date +%s`"
    for python in $pythons; do
        version="`sed -n "/^ *__version__ = '\\([0-9]*\\.[0-9]*\\)[^']*'*/ { s//\\1/; p; q }" "$workdir/src/trac/__init__.py"`"
        if [ $python = 24 -a "$version" != 0.12 ]; then
            continue
        fi
        pids=
        echo -n "  Running tests on python$python..."
        for db in $databases; do
            cp -rp "$workdir/src" "$workdir/src-py$python-$db"
            mkdir "$workdir/tmp-py$python-$db"
            TMP="$workdir/tmp-py$python-$db" \
                /usr/bin/make -C "$workdir/src-py$python-$db" \
                python=$python-$version db=$db \
                Trac.egg-info compile stats unit-test functional-test \
                >"$nrevdir/py$python-$db.log" 2>&1 &
            pids="$pids $!"
        done
        results=
        for pid in $pids; do
            if wait $pid; then
                echo -n " [PASS]"
                results="$results [PASS]"
                pass=$(expr $pass + 1)
            else
                echo -n " [FAIL]"
                results="$results [FAIL]"
                fail=$(expr $fail + 1)
            fi
        done
        rm -rf "$workdir/src-py$python"-* "$workdir/tmp-py$python"-*
        echo
        body="${body}Python$python$results
"
    done
    msgid="$nrev.$elapse@localhost"
    elapse=$(expr "`LC_ALL=C /bin/date +%s`" - $elapse)
    date="`date -R`"
    echo "  Passed $pass, Failed $fail in $elapse seconds at $date"
    if [ -n "$mail" ]; then
        if [ "$rev" = "$nrev" ]; then
            subject="PASS $pass, FAIL $fail in $elapse seconds on $rev"
        else
            subject="PASS $pass, FAIL $fail in $elapse seconds on $rev ($nrev)"
        fi
        {
            echo "\
From: <$mail>
Subject: $subject
To: <$mail>
Date: $date
Message-ID: <$msgid>
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary=$boundary
X-Git-Rev: $rev

--$boundary
Content-Type: text/plain; charset=utf-8

$subject

$body
";
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
    rev="$1"
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
    git archive --prefix="$nrev/src/" "$nrev" | tar xf - -C "$tmpdir" 2>/dev/null
    cp "$dir/Makefile.cfg" "$workdir/src/Makefile.cfg"
    /usr/bin/find "$tmpdir" -exec /bin/touch -- '{}' +
    echo " done."
    runtest "$workdir" "$nrevdir"
    rm -rf "$workdir"
}

main() {
    [ -n "$update_remotes" ] && git fetch --quiet --all --prune
    [ -n "$all_refs" ] && set `git for-each-ref --format='%(refname)'`
    for rev in "$@"; do
        export_and_runtest "$rev"
    done
}

main "$@"
if [ -n "$loop_secs" ]; then
    while :; do
        echo -n "`date -R`\r"
        sleep "$loop_secs"
        main "$@"
    done
fi
