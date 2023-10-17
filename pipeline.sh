#!/bin/bash
# A helper script to get commits delta for cherry-picking to prod from dev
PRODBR=${PRODBR:-origin/prod}
DEVBR=${DEVBR:-origin/main}

DELTA="${PRODBR}..${DEVBR}"
LOGPRODMSG="git --no-pager log --no-merges --pretty=format:'%s' ${PRODBR}; echo"
LOGDEVMSG="git --no-pager log --no-merges --pretty=format:'%s' ${DELTA}; echo"
LOGDEVALL="git --no-pager log --no-merges --pretty=format:'%h - %an, %ar : %s' ${DELTA}; echo"

TMPDIR="$(mktemp -d)"
trap 'rm -f ${TMPDIR}/gitlog*; rm -d "$TMPDIR"' EXIT

eval $LOGPRODMSG > ${TMPDIR}/gitlogprod
eval $LOGDEVMSG > ${TMPDIR}/gitlog
eval $LOGDEVALL > ${TMPDIR}/gitlogall

# Omit commit messages from dev what already present in prod
while read msg; do
	[ -z "$msg" ] && break
	if grep -qF "$msg" ${TMPDIR}/gitlogprod ; then
    grep -vF "$msg" ${TMPDIR}/gitlogall > ${TMPDIR}/gitlogall_
  	mv -f ${TMPDIR}/gitlogall_ ${TMPDIR}/gitlogall
  fi
done < "${TMPDIR}/gitlog"

cat ${TMPDIR}/gitlogall
