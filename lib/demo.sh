#! /bin/bash
# Description: To provide functions to do demo testing.
# Author: Osier Yang <jyang@example.com>
# Maintainer: Alex Jia <ajia@example.com>
# Update: Jan 29, 2018


demo_one() {
    [ $# -lt 1 ] && die "Usage: demo_one <Emily=STRING>"

    table="${FUNCNAME}_${RANDOM}"

    hash_new $table "$@"

    info_log "Emily: $(hash_get $table Emily)"

    return 0
}

demo_two() {
    [ $# -ne 2 ] && die "Usage: demo_two <Osier=STRING> <Alex=STRING>"

    table="${FUNCNAME}_${RANDOM}"

    hash_new $table "$@"

    info_log "Osier: $(hash_get $table Osier)"
    info_log "Alex: $(hash_get $table Alex)"

    return 1
}

demo_all() {
    echo "$@"
}
