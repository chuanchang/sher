#! /bin/bash
# Description: Write log in d general format.
# Author: Osier Yang <jyang@example.com>
# Maintainer: Alex Jia <ajia@example.com>
# Update: Jan 29, 2018

__UTILS_LOG__=1

[ -z "${__UTILS_COMMON__}" ] && source utils/common.sh

SCRIPT_NAME=$(basename $0)
[ -z "${LOG}" ] && LOG=
[ -z "${EXECUTER}" ] && EXECUTER=

FAILED=0  # count failed test cases
PASSED=0  # count passed test cases
SKIPPED=0 # count skipped test cases
TOTAL=0   # total test cases
CASENAME= # current casename
CASEID=   # current case id
declare -a FAILED_CASES  # store failed cases in "caseid~casename~error" format
declare -a PASSED_CASES  # store passed cases in "caseid~casename" format
declare -a SKIPPED_CASES # store skipped cases in "caseid~casename~msg" format

get_date() {
    local date
    date=$(date +"%Y-%m-%d %T")
    echo "$date"
}

# get file last access time
atime() {
    local file atime

    file="${1}"
    
    if [ ! -f "$file" ]; then
        die "ERROR: $file doesn't exist"
    fi

    atime=$(stat -c %x "${file}")
    atime=${atime%.*}
    atime=${atime/ /-}
    atime=${atime:5}
 
    echo "${atime}"
}

# initialize value of the two variables stands for
# detailed log, if it's already exists, do backup
#  will use 'result.log' by default
#@ detailed_log: filename of the detailed log file
init_log() {
    if [ $# -ne 2 ]; then
        die "Usage: $FUNCNAME <detailed log> <total case>."
    fi

    if [ -z "$1" -o -z "$2" ]; then
        die "ERROR: Please make sure don't input empty strings as log name \
            or total case number"
    fi

    local atime

    LOG="$1"
    TOTAL="$2"

    if [ -f "$LOG" ]; then
        atime=$(atime "${LOG}")
        echo "Backup ${LOG} to ${LOG%.*}-${atime}.log"
        mv ${LOG} "${LOG%.*}-${atime}.log"
    fi
}

# output log msg to both stdout and log file
write_log() {
    local _type log msg date caller sep

    _type="$1"; shift 
    log="$1"; shift
    msg="$*"
    date=$(get_date)
    #local caller="${SCRIPT_NAME}"
    caller="${EXECUTER}"
    sep=${BASH_LINENO[1]}

    msg=$(echo "$msg" | sed -e "s/%/%%/g" -e "s/  */ /g")

    if [ -z "$log" ]; then
        die "ERROR: please make sure the logs were initialized properly"
    fi

    if [ 'RAW' = "$_type" ]; then
        printf " ${msg}\n"
        printf " ${msg}\n" >> ${LOG}
        return
    fi

    if [ 'DEBUG' != "$_type" ]; then
        printf "(%s:%s) | %-7s |" "${caller}" "${sep}" "${_type}" 
        printf " ${msg}\n"
    fi

    printf "[%s] %-7s (%s:%s)" "${date}" "${_type}" "${caller}" \
           "${sep}" >> ${LOG}
    printf " ${msg}\n" >> ${LOG}
}

info_log() {
    [ $# -lt 1 ] && die "Usage: $FUNCNAME <msg>"
    write_log "INFO" "{$LOG}" "${*}"
}

debug_log() {
    [ $# -lt 1 ] && die "Usage: $FUNCNAME <msg>"
    write_log "DEBUG" "{$LOG}" "${*}"
}

warn_log() {
    [ $# -lt 1 ] && die "Usage: $FUNCNAME <msg>"
    write_log "WARNING" "{$LOG}" "${*}"
}

err_log() {
    [ $# -lt 1 ] && die "Usage: $FUNCNAME <msg>"
    write_log "ERROR" "{$LOG}" "${*}"
}

# Just output msg to both stdout and detailed log
raw_log() {
    [ $# -lt 1 ] && die "Usage: $FUNCNAME <msg>"
    write_log "RAW" "{$LOG}" "${*}"
}
   
separator() {
    local width char

    width="$1"
    char="$2"

    for i in $(seq 1 ${width}); do
        echo -en ${char}
    done
}

print_title() {
    local title len sep

    title="${1}"
    len=${#title}
    sep=$(separator $(($len + 4)) '-')

    printf "%s\n" "${sep}" | tee -a ${LOG}
    printf "%s\n" " ${title} " | tee -a ${LOG}
    printf "%s\n" "${sep}" | tee -a ${LOG}
}

print_sec() {
    local flag long_sep short_sep result casename

    flag="${1}"; shift
    long_sep=$(separator 58 '-')
    short_sep=$(separator 40 '-')
    
    if [ "end" = "$flag" ]; then
        result="${1}"

        if [ "0" = $result ]; then
            raw_log  "${short_sep}[ PASS ]${long_sep}" 
        elif [ "1" = $result ]; then
            raw_log  "${short_sep}[ FAIL ]${long_sep}" 
        elif [ "2" = $result ]; then
            raw_log  "${short_sep}[ SKIP ]${long_sep}" 
        fi
    else
        casename="${1}"; shift
        raw_log "${short_sep}[ ${casename} ]${short_sep}"
    fi
}

# write log before test case running
pre_test() {
    if [ $# -lt 3 ]; then 
        die "Usage: $FUNCNAME <casename> <case id> <summary>"
    fi

    local casename case_id summary start_time

    casename="$1"; shift
    case_id="$1"; shift
    summary="$@" 
    start_time=$(date +"%Y-%m-%d %T")

    CASENAME="${casename}"
    CASEID="${case_id}"

    print_sec "begin" "step${case_id}: ${casename}" 

    exec 6>&1

    separator 128 '-'
    echo
    printf "START\t[%s]%s[test_process=%s/%s]\t%s\n" "${casename}" \
           "${summary}" "${case_id}" "${TOTAL}" "${start_time}"

    exec 1>&6 6>&-
}

# write log after test case running
post_test() {
    [ $# -lt 2 ] && die "Usage: $FUNCNAME <0/1/2> <msg>"

    local result msg end_time

    result="$1"; shift
    msg="$@"; shift
    end_time=$(date +"%Y-%m-%d %T")

    exec 6>&1

    if [ 0 -eq $result ]; then
        PASSED=$(($PASSED + 1))
        echo -ne "GOOD\t"

        len=${#PASSED_CASES[@]}
        PASSED_CASES[$len]="${CASEID}~${CASENAME}"
    elif [ 1 -eq $result ]; then
        FAILED=$(($FAILED + 1))
        echo -ne "FAIL\t"

        len=${#FAILED_CASES[@]}
        FAILED_CASES[$len]="${CASEID}~${CASENAME}~${msg}"
    elif [ 2 -eq $result ]; then
        SKIPPED=$(($SKIPPED + 1))
        echo -ne "FAIL\t"
 
        len=${#SKIPPED_CASES[@]}
        SKIPPED_CASES[$len]="${CASEID}~${CASENAME}~${msg}"
    fi

    echo "${msg}"
    echo -ne "END\t${end_time}"
    echo

    exec 1>&6 6>&-
   
    print_sec "end" "$result"
}

# summary result of test cases execution, and prepend it to detailed log
add_summary() {
    local summary tmpfile sep case_id casename error tmpfile2

    summary="${1}"
    tmpfile=$(mktemp)
    sep=$(separator 100 '#')
    tmpfile2=$(mktemp)

    exec 6>&1
    exec >> $tmpfile

    echo "${sep}" 
    echo "Test Summary: ${summary}" 
    echo "${sep}" 
    printf "%-5s: %s\n" "PASS" "${PASSED}" 
    printf "%-5s: %s\n" "FAIL" "${FAILED}" 
    # printf "%-5s: %s\n" "SKIP" "${SKIPPED}" 
    echo "------------"
    printf "%-5s: %s\n" "Total" "${TOTAL}" 

    # Failed cases
    echo "${sep}" 
    printf "Failed cases:\n"
    for i in `seq 0 $((${#FAILED_CASES[@]}- 1))`; do
        local element=${FAILED_CASES[$i]}
        case_id=$(echo ${element} | awk -F'~' '{print $1}')
        casename=$(echo ${element} | awk -F'~' '{print $2}')
        error=$(echo ${element} | awk -F'~' '{print $3}')
        
        printf "%s: %s\t%s\n" "case${case_id}" "${casename}" "${error}"
    done

    # Passed cases
    echo "${sep}" 
    printf "Passed cases:\n"
    for i in `seq 0 $((${#PASSED_CASES[@]} - 1))`; do
        local element=${PASSED_CASES[$i]}
        case_id=$(echo ${element} | awk -F'~' '{print $1}')
        casename=$(echo ${element} | awk -F'~' '{print $2}')

        printf "%s: %s\n" "case${case_id}" "${casename}" 
    done

    # Skipped cases
    echo "${sep}" 
    # printf "Skipped cases:\n"
    # for i in `seq 0 $((${#SKIPPED_CASES[@]} - 1))`; do
    #    local element=${SKIPPED_CASES[$i]}
    #    case_id=$(echo ${element} | awk -F'~' '{print $1}')
    #    casename=$(echo ${element} | awk -F'~' '{print $2}')
    #    local msg=$(echo ${element} | awk -F'~' '{print $3}')

    #    printf "%s: %s\t%s\n" "case${case_id}" "${casename}" "${msg}"
    # done

    echo "${sep}"

    exec 1>&6 6>&-

    cat $tmpfile "${LOG}" >> $tmpfile2
    mv $tmpfile2 "${LOG}"

    rm -f $tmpfile

    echo "Test completed!" | tee -a "${LOG}"
}

# __UTILS_LOG__    
