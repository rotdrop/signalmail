#!/bin/bash

# The following causes an error, probably because of an left-over child
# exec > >(systemd-cat -t signal-gateway -p info) 2>&1
echo "sieve pipe start" 1>&2

# Keep temporary files
DEBUG=false
if "$DEBUG"; then
    set -x
fi

PYTHON=/usr/bin/python
FORMAIL=$(which formail)
# define sending account
ACCOUNT="XXXXXXXXXXXXXX"
# define recipient
RECIPIENT="XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX="

export HOME=${HOME:-$(getent passwd $(whoami)|cut -d: -f 6)}

TMPDIR="${HOME}/.cache/signalmail"
[ -d "${TMPDIR}" ] || mkdir -p "${TMPDIR}"
# create unique folder per mail, escape the systemd jail for /tmp
UUID="$(mktemp -d "${TMPDIR}/XXXXXXXXXX")"
if [ -z "${UUID}" ]; then
    exit 1
fi

function cleanup() {
    if ! $DEBUG; then
	rm -rf "${UUID}"
    fi
}

function decodeHeader() {
    ${PYTHON} -c "from email.header import decode_header;
import sys;
decodedHeader = '';
for text, encoding in decode_header(sys.stdin.read()):
    if not isinstance(text, str):
        if encoding == None:
            encoding = 'utf-8';
        text = text.decode(encoding);
    decodedHeader += text;
print(decodedHeader.strip())"
}

function extractHeader() {
    local HEADER="$1"
    ${FORMAIL} -c -x ${HEADER}:|decodeHeader
}

function base64toBytes() {
    local DECODED=$(echo -n "$1"|base64 -d)
    if [ "$?" != 0 ]; then
	return 1
    fi
    echo -n "$DECODED"|xxd -p -c1|while read i; do printf "%d " $((16#${i})); done|sed 's/ /,/g'
}

function dbusSend() {
    # sendMessage message<s>, attachments<as>, recipient<s>
    # sendGroupMessage(message<s>, attachments<as>, groupId<ay>)
    local RECIPIENT="$1"
    local MESSAGE="$2"
    local ATTACHMENTS="$3"
    local RECIPIENT_ARG
    local GROUP_ID=$(base64toBytes "$RECIPIENT")
    if [ "$?" != 0 ]; then
	METHOD=sendMessage
	RECIPIENT_ARG="string:_${RECIPIENT:1}"
    else
	METHOD=sendGroupMessage
	RECIPIENT_ARG="array:byte:${GROUP_ID}"
    fi
    local ATTACHMENT_ARG=""
    for ATTACHMENT in $ATTACHMENTS; do
	ATTACHMENT_ARG="${ATTACHMENT_ARG},${UUID}/${ATTACHMENT}"
    done
    ATTACHMENT_ARG="array:string:${ATTACHMENT_ARG:1}"
    dbus-send --system --type=method_call --print-reply --dest="org.asamk.Signal" /org/asamk/Signal/_${ACCOUNT:1} org.asamk.Signal.${METHOD} "string:${MESSAGE}" ${ATTACHMENT_ARG} ${RECIPIENT_ARG}
}

trap cleanup exit

# save mail
cat | tr -d '\r' > "${UUID}/mail"

# check if we received plain text message or multipart message
if grep -q multipart/mixed "${UUID}/mail"; then
    # Extract mail and get attachments if exist. Fixme: white-space in file-names?
    ATTACHMENTS=$(munpack -C "${UUID}" "${UUID}/mail"|awk '{ print $1; }')
    # get text message if exists
    MESSAGE="$(find "${UUID}" -name '*.desc')"
    # get rid of notriously attached X and cope with multi-attachment limitation of Signal
    FIXED_ATTACHMENTS=
    for ATTACHMENT in $ATTACHMENTS; do
	WITHOUT_X=$(echo -n ${ATTACHMENT}|sed -E 's/X$//g')
	if [ "${WITHOUT_X}" != "${ATTACHMENT}" ]; then
	    mv -f "${UUID}/${ATTACHMENT}" "${UUID}/${WITHOUT_X}"
	    ATTACHMENT="${WITHOUT_X}"
	fi
	FIXED_ATTACHMENTS="${FIXED_ATTACHMENTS} ${ATTACHMENT}"
	MIME_TYPE=$(file --mime-type "${UUID}/${ATTACHMENT}"|awk '{ print $NF; }')
	case "${MIME_TYPE}" in
	    image/jpeg|image/png)
		IMAGES="${IMAGES} ${ATTACHMENT}"
	    ;;
	    *)
		NON_IMAGES="${NON_IMAGES} ${ATTACHMENT}"		
	    ;;
	esac
    done
    ATTACHMENTS="${FIXED_ATTACHMENTS}"
    if [ -n "${NON_IMAGES}" ] && [ -n "${IMAGES}" ]; then
	ATTACHMENTS="${IMAGES}"
	SKIPPED="${NON_IMAGES}"
	NOTES="${NOTES}

The following attachments have not been forwarded due to technical limitations of Signal:

${SKIPPED}
********************
"
    elif [ $(echo "${NON_IMAGES}"|wc -w) -gt 1 ]; then
	SKIPPED=$(echo -n "${NON_IMAGES}"|awk '{ $1= ""; print $0; }')
	ATTACHMENTS=$(echo -n "${NON_IMAGES}"|awk 'print $1; }')
	NOTES="${NOTES}

********************
The following attachments have not been forwarded due to technical limitations of Signal:

${SKIPPED}
********************
"
    fi
    
    echo $ATTACHMENTS 1>&2   
else
    MESSAGE="${UUID}/message"
    if grep -E -qs '^Content-Transfer-Encoding:.*base64' "${UUID}/mail"; then
	FILTER="base64 -d"
    else
	FILTER=cat
    fi
    sed '1,/^$/d' "${UUID}/mail" | ${FILTER} | tr -d '\r' > "${MESSAGE}"
fi

# Ok, polish a bit and add From: and Subject: lines from the
# Email. Also remove any signatures, Signal is rather a chat service
# and it really blows up the messages

FROM=$(extractHeader From < "${UUID}/mail")
SUBJECT=$(extractHeader Subject < "${UUID}/mail")

MESSAGE_TEXT="$(sed '/^-- $/,$d' "${MESSAGE}")"
# cope with mailing list footer, assume many underscores and only up
# to 6 lines, cope with accumulating footers.
MAILING_LIST_FOOTER="$(echo "${MESSAGE_TEXT}"|sed -E '1,/^_{40}_*$/d')"
NUMBER_OF_FOOTERS="$(echo "${MESSAGE_TEXT}"|grep 'To unsubscribe send an email to'|wc -l)"
MAX_LINES_TO_IGNORE=$(( ${NUMBER_OF_FOOTERS} * 5 ))
if [ "$(echo "${MAILING_LIST_FOOTER}"|wc -l)" -le ${MAX_LINES_TO_IGNORE} ]; then
    MESSAGE_TEXT="$(echo "${MESSAGE_TEXT}"|sed -E '/^_{40}_*$/,$d')"
fi

MESSAGE="From: ${FROM}
${SUBJECT}

${MESSAGE_TEXT}${NOTES}"

# trigger webhook
echo "sending signal message for "${UUID}"" 1>&2
if [ ! "${MESSAGE}" == "" ] || [ ! "${ATTACHMENTS}" == "" ]; then
    RESPONSE=$(dbusSend ${RECIPIENT} "${MESSAGE}" "${ATTACHMENTS}")
    if [ "$?" != 0 ]; then
	exit 1
    fi;
fi	 

TIMESTAMP=$(echo -n ${RESPONSE}|awk '{ print $NF; }')
echo ${TIMESTAMP}

exit 0
