#! /bin/bash
# Description: Simulated hash table implementation.
# Author: Osier Yang <jyang@example.com>
# Maintainer: Alex Jia <ajia@example.com>
# Update: Jan 29, 2018


__UTILS_HASH__=1

# Add an entry into hash table
# @table_name: name of the hash table you want to add the entry into
# @key:        hash key
# @value:      hash value
# Return Value: 0 on SUCCESS or -1 on FAILURE
hash_add() {
    if [ $# -lt 3 ]; then
        die "Usage: hash_add <table_name> <key> <value>"
    fi

    table=$1
    key=$2
    shift 2

    eval "$table""$key"="'$(echo "$@" | sed -e "s/ /~space~/g" -e 's/NULL//g' \
        -e "s/'/\\'/g")'"
}

# Lookup hash table with specified key, and return value
# @table_name: name of the hash table where get the hash value from
# @key:        hash key
# Return value: a string on SUCCESS, or empty on FAILURE.
hash_get() {
    if [ $# -ne 2 ]; then
        die "Usage: hash_get <table> <key>"
    fi

    local table key

    table=$1
    key=$2

    eval echo '${'"$table$key"'#hash}' | sed -e 's/~space~/ /g' 
}


# NOTE: because the @table_name will be finnaly used as variable name.
# by 'eval' in function "hash_get", so you should follow the variable 
# naming RULE: 
# Variable names must begin with an alphabetic character or underscore, 
# and can also contain numeric characters.
hash_new() {
    if [ $# -lt 2 ]; then
        die "Usage: hash_new <table_name> <key/value> <key/value> <...>"
    fi

    local table key value

    table=$1; shift

    for i in "$@"; do
        key=$(echo $i | awk -F'=' '{print $1}')
        value=$(echo $i | awk -F'=' '{ str=$2; for(i = 3; i <= NF; i++) { \
            str = (str "=" $i) } {print str} }')

	[[ "X" = "X$value" ]] && value="NULL"
	hash_add $table ${key} "${value}"
    done
}

# Actually what this function does is to unset all the global variables
# that created by hash_add. 
hash_free() {
    if [ $# -lt 2 ]; then
        die "Usage: hash_new <table_name> <key/value> <key/value> <...>"
    fi

    local table key

    table=$1; shift

    for i in "$@"; do
        key=$(echo $i | awk -F'=' '{print $1}')
	unset $table$key
    done
}

# __UTILS_HASH__
