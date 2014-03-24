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
    local elapse="`LC_ALL=C /bin/date +%s`"
    local pass=0 fail=0 body= elapse_1= version= pids= results= db= msgid=
    local date= subject= base= commits=
    for python in $pythons; do
        elapse_1="`LC_ALL=C /bin/date +%s`"
        version="`sed -n "/^ *__version__ = '\\([0-9]*\\.[0-9]*\\)[^']*'*/ { s//\\1/; p; q }" "$workdir/src/trac/__init__.py"`"
        if [ $python = 24 -a "$version" != 0.12 ]; then
            continue
        fi
        pids=
        echo -n "  Running tests on python$python..."
        for db in $databases; do
            cp -rp "$workdir/src" "$workdir/py$python-$db"
            mkdir "$workdir/tmp-py$python-$db"
            TMP="$workdir/tmp-py$python-$db" \
                /usr/bin/make -C "$workdir/py$python-$db" \
                python="$python-$version" db="$db" \
                pip-freeze Trac.egg-info compile stats unit-test functional-test \
                >"$nrevdir/py$python-$db.log" 2>&1 &
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
        body="${body}Python$python$results in $elapse_1 seconds
"
    done
    msgid="$nrev.$elapse@localhost"
    elapse=$(expr "`LC_ALL=C /bin/date +%s`" - $elapse || :)
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
            if [ -n "$base" -a "$commits" -gt 1 ]; then
                git log --oneline --graph --decorate "$nrev" "$base^!"
                echo "--$boundary"
                echo "Content-Type: text/plain; charset=utf-8; name=\"$nrev.diff\""
                echo "Content-Transfer-Encoding: base64"
                echo "Content-Disposition: attachment; filename=\"$nrev.diff\""
                echo
                git log -p "$base..$nrev" | base64
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
    git archive --prefix="$nrev/src/" "$nrev" \
        | tar xf - -C "$tmpdir" --touch 2>/dev/null
    cp "$dir/Makefile.cfg" "$workdir/src/Makefile.cfg"
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
