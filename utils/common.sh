#! /bin/bash
# Description: Common utilities.
# Author: Osier Yang <jyang@example.com>
# Maintainer: Alex Jia <ajia@example.com>
# Update: Jan 29, 2018


__UTILS_COMMON__=1

[ -z "${__UTILS_LOG__}" ] && source utils/log.sh

die() {
    err_log "$*, Exit."
    exit 1
}

# Check if a file exists.
# Return 0 if exists, 1 if not
_file_exists() {
    if [ $# -ne 1 ]; then
        die "Usage: _file_exists <filepath>"
    fi

    if [ -f "$1" ]; then
        echo 0
    else
        echo 1
    fi
}


# Return the home directory path of the user.
_get_home() {
    [ $# -ne 1 ] && die "Usage: $FUNCNAME <username>"
   
    local username home

    username=$1

    if [ ${username} = "root" ]; then
        home="/root"
    else
        home="/home/${username}"
    fi

    echo ${home}
}

# Return the uppercase of a string
_uppercase() {
    if [ $# -ne 1 ]; then
        die "Usage: _uppercase <var>"
    fi

    echo $1 | tr '[:lower:]' '[:upper:]'
}

_lowercase() {
    if [ $# -ne 1 ]; then
        die "Usage: _lowercase <var>"
    fi
  
    echo $1 | tr '[:upper:]' '[:lower:]'
}

# Return the value of the variable, of which the name is the value of 
# @variable.
# e.g. 
# foo="bar"
# coo="foo"
# "_refer $coo" will return "bar"
_refer() {
    if [ $# -ne 1 ]; then
        die "Usage: _refer <variable>"
    fi

    eval echo \$$1
}
