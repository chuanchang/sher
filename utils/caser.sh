#! /bin/bash
# Description: The tcs under directory "cases" couldn't be executed directly.
# To work around it, at first, we need tell shell where to find the 
# functions that will be used. We have a file named "headers" under 
# the source code root, it includes the needed scripts.
# Second, we need initialize the log instance for every case, and to
# execute the cases on local, we need add some log statements for
# every case step.
# 
# The functions in this script is to resolve the upper two problems, 
# so you can call this script as "case reprocesser". :-)

# Author: Osier Yang <jyang@example.com>
# Maintainer: Alex Jia <ajia@example.com>
# Update: Jan 29, 2018


__UTILS_CASER__=1

[ -z "${__UTILS_COMMON__}" ] && source ./utils/common.sh
[ -z "${__UTILS_HASH__}" ] && source ./utils/hash.sh

# Count the step numbers a case has.
# @case: file path of case
count_case_steps() {
    [ $# -ne 1 ] && die "Usage: count_case_steps <case>"
    
    local _case re

    _case=$1
    re="summary|pre_test|post_test|EXECUTER|^#|__VAR__"

    grep '^\w' $_case | grep -E -v $re | wc -l
}

# Construct and insert "init_log" statement at the top of case.
# @case: file path of case
insert_init_log() {
    [ $# -ne 2 ] && die "Usage: insert_init_Log <case> <orginal_case>"

    local _case orig_case base_name case_steps feature_name log_dir init_log

    _case=$1
    orig_case=$2

    feature_name=$(dirname $orig_case | sed -e 's/features\///g' \
        -e 's/cases\///g' -e 's/cases//g')
    base_name=$(basename $orig_case)
    case_steps=$(count_case_steps $orig_case)

    log_dir="$LOG_DIR/$feature_name"
    ! [ -d "$log_dir" ] && mkdir -p $log_dir
    init_log="init_log $log_dir/${base_name%.*}.log \
        $case_steps"
    sed -i -e "/summary/ a $init_log" $_case
}

# Insert a statement like following into $case
# EXECUTER=@casename
insert_casename() {
    [ $# -ne 2 ] && die "Usage: insert_casename <case> <casename>"

    local _case casename

    _case="$1"
    casename="$2"

    sed -i -e "/summary/ a EXECUTER=$casename" "$_case"
}

# Get the all the key/value pairs of a function. Format them into
# [key=value][key1=value1][key2=value2]..."
# @case: file path of case
# @from: function name passed to sed as the start RE of range
# @to:   function name passed to sed as the end RE of range
get_kv_pairs() {
    [ $# -ne 5 ] && die "Usage: get_kv_pairs <case> <from> <to> \
        <from_line> <to_line>" 

    local _case from to str kv_pairs

    _case=$1
    from=$2
    to=$3 

    str=

    kv_pairs=$(sed -n -e "$from_line,$to_line p" $_case | \
        grep -Ev "$from|$to|^$| *#" | sed -e 's/\\//g') 

    for p in $kv_pairs; do
       str="$str[$p]"
    done

    echo $str
}

# Construct and insert "pretest" and "postest" statements before and after 
# every function name of the case seperately.
# @case: file path of case
insert_pretest_postest() {
    [ $# -ne 1 ] && die "Usage: insert_pretest_postest <case>"

    local _case arr versions re function_names i j k l m n i_next driver \
        from from_line to to_line pre_test post_test label  \
        lp_line_num lp_times arr_lp_times arr_lp_line_num adjust \
        lp_func_name lp_start_line_num lp_end_line_num times mid_tmp \
        table option_name option_value args args_line id id_tmp id_start \
        id_end lp_start_from lp_end_to 

    _case=$1
    declare -a arr arr_lp_line_num arr_lp_times arr_lp_pair arr_lp_ids \
        arr_args arr_args_len

    versions="[tc_name=$(cat $tc_name_tmp)]"

    # The function_names will contain the line number. e.g. 10:domain_start
    re="summary|pre_test|post_test|__VAR__|^#"
    function_names=$(grep -n '^\w' $_case | grep -Ev $re | sed 's/\\//g') 

    i=0
    j=0
    l=0
    n=0
    for f in ${function_names}; do
        # Get line number & function name of loop_start and loop_end, and
        # get times of loop, meanwhile, push them into corresponding array.
        lp_line_num=$(echo $f | awk -F':' '{print $1}')
        lp_func_name=$(echo $f | awk -F':' '{print $2}')
        # Filter non-loop_start and non-loop_end lines
        if [[ $lp_func_name =~ loop_start ]] || \
            [[ $lp_func_name =~ loop_end ]]; then
            # Exact match loop_start and loop_end strings
            if [[ $lp_func_name =~ ^loop_start$ ]] || \
                [[ $lp_func_name =~ ^loop_end$ ]]; then
                if [[ $lp_func_name =~ ^loop_start$ ]]; then
                    k=1
                    # Get loop_start argument lines
                    args_line=$(sed -n $(($lp_line_num + $k))p $_case)
                    # Get the first loop_start argument
                    args=$(echo $args_line | sed -e 's/\\//' -e "s/\t//" \
                        -e 's/ //')
                    # Times argument is necessary
                    [ -z "'$args'" ] && die "Require a argument followed by \
                        loop_start line at least"

                    # Define a loop_start hash table, and will use it later
                    table="loop_start_$i"

                    # Push all of loop_start key/value arguments pair into 
                    # array of argument
                    while [ X"$args" != X ]; do
                        arr_args[$l]=$args
                        l=$(($l + 1))

                        # Parse key/value pair and push them into loop_start
                        # hash table
                        option_name=$(echo ${args}|cut -d= -f1)
                        option_value=$(echo ${args}|cut -d= -f2-)
                        hash_add $table $option_name $option_value

                        # Get the next loop_start key/value argument
                        k=$(($k + 1))
                        args_line=$(sed -n $(($lp_line_num + $k))p $_case)
                        args=$(echo $args_line | sed -e 's/\\//' -e "s/\t//" \
                            -e 's/ //')
                    done

                    # Push length of arguments into array
                    arr_args_len[$i]=${#arr_args[@]} 

                    # Recovery original variable environment due to arr_args and
                    # l are common variables
                    unset arr_args
                    l=0

                    # Get loop times and id and push them into corresponding
                    # array
                    id=$(hash_get $table "id")
                    times=$(hash_get $table "times")
                    [ -z "$times" ] && die "Times argument is necessary:\
                        times=[[:digit:]]"

                    # Push loop times into array
                    arr_lp_times[$i]=$times
                    i=$(($i + 1))

                    # Push id range into array, note that, although id may be null,
                    # still push it into array in order to hold a bit
                    arr_lp_ids[$n]=$id
                    n=$(($n + 1))

                    # Judge id if matches [0-9]+..[0-9]+ or [a-z]..[a-z] or
                    # [A-Z]..[A-Z] if id exists
                    if [ -n "$id" ]; then
                        if ! [[ $id =~ [0-9]+(\.){2}[0-9]+$ ]] && \
                            ! [[ $id =~ [a-z](\.){2}[a-z] ]] && \
                            ! [[ $id =~ [A-Z](\.){2}[A-Z] ]]; then
                            die "id should be a digit or character list such \
                                as id=[0-9]+..[0-9]+ or id=[a-z]..[a-z] or
                                id=[A-Z]..[A-Z]"
                        fi
                    fi
                fi
                # Push loop_start and loop_end number into array
                # arr_lp_line_num, and function name into array
                # arr_lp_pair
                arr_lp_line_num[$j]=$lp_line_num
                arr_lp_pair[$j]=$lp_func_name
                j=$(($j + 1))
            else
                die "please use loop_start and loop_end surround with \
                    test steps"
            fi
        fi
    done

    # judge odd/even of loop_start and loop_end number
    if [ $((${#arr_lp_line_num[@]} % 2)) -ne 0 ]; then
        die "missing loop_start or loop_end action in tc file"
    fi

    i=0
    while [ $i -lt ${#arr_lp_pair[@]} ]; do
        # Doesn't support loop_start and loop_end nest action, it means
        # loop_start and loop_end must be a atomic operation
        i_next=$(($i + 1))
        if ! [[ ${arr_lp_pair[$i]} =~ ^loop_start$ ]] || \
            ! [[ ${arr_lp_pair[$i_next]} =~ ^loop_end$ ]]; then
            die "doesn't support <loop_start, loop_end> nest"
        fi
        i=$(($i + 2))
    done

    i=0
    j=0
    l=0
    n=0
    adjust=0
    while [ $j -lt ${#arr_lp_times[@]} ]; do
        # Get contents from loopp start line to loop end line in $_case file
        # and then inserting them into a temp file many times, which is
        # determined by times variable, finally, looply inserting the temp
        # file into specified loop start line line from $_case.
        i_next=$(($i + 1))
        # Get a pair of loop_start and loop_end number
        lp_start_line_num=${arr_lp_line_num[$i]}
        lp_end_line_num=${arr_lp_line_num[$i_next]}

        # Get loop times
        times=${arr_lp_times[$j]}

        # Line number will change after inserting $mid_tmp into $_case,
        # adjust variable helps adapt the change, finally, programming
        # can get correct line number and insertion position.
        mid_tmp=$(mktemp)
        lp_start_line_num=$(($lp_start_line_num + $adjust))
        lp_end_line_num=$(($lp_end_line_num + $adjust))

        # Array length of arguments
        args_len=${arr_args_len[$j]}

        # Get id list and check if id_end reduces id_start is equal to
        # loop times
        if [ $n -lt ${#arr_lp_ids[@]} ]; then
            id_tmp=$(eval echo {${arr_lp_ids[$n]}})
            if [ "$id_tmp" != "{}" ]; then
                id_start=$(echo ${id_tmp%%' '*})
                id_end=$(echo ${id_tmp##*' '})
                # if id is a character, covert it to ASCII code
                if [[ $id_start =~ [a-zA-Z] ]] && [[ $id_end =~ [a-zA-Z] ]]; then
                    id_start=$(printf "%d\n" \'$id_start)
                    id_end=$(printf "%d\n" \'$id_end)
                fi
                if [ $(($id_end - $id_start + 1)) -ne $times ]; then
                    die "id_end($id_end) reduces id_start($id_start) should \
                        be equal to times($times) reduces 1 ($(($times - 1)))"
                fi
            fi
        fi

        # Count loop line number
        lp_start_from=$(($lp_start_line_num + $args_len + 1))
        lp_end_to=$(($lp_end_line_num - 1))

        # Insert specified contents into temp file many times
        for k in $(seq $times); do
            # Just loop useful steps except for loop_start arguments
            sed -n "$lp_start_from,${lp_end_to}p" $_case >> $mid_tmp

            # Substitute #id# with specific id number
            if [ "$id_tmp" != "{}" ]; then
                id=$(echo $id_tmp | cut -d' ' -f$k)
                sed -i -e "s/#id#/${id}/" $mid_tmp
            fi
        done

        # counter for array of arr_lp_ids
        n=$(($n + 1))

        # Insert final $mid_tmp iteration file into $_case
        sed -i "$lp_end_line_num r $mid_tmp" $_case

        # Clean up original lines between loop_start and loop_end from $_case
        sed -i "$lp_start_line_num,${lp_end_line_num}d" $_case 

        # Get adjusted factor
        adjust=$(($adjust + $(cat $mid_tmp | wc -l) - $(($lp_end_line_num - \
            $lp_start_line_num + 1))))

        # Need to move <loop_start, loop_end> 2 positions from array
        # arr_lp_line_num each time, so i add 2
        i=$(($i + 2))
        j=$(($j + 1))
    done

    # Get latest function names
    function_names=$(grep -n '^\w' $_case | grep -Ev $re | sed 's/\\//g')

    # Push them into an array
    i=0
    for f in ${function_names}; do
        arr[$i]=$f
        i=$(($i + 1))
    done

    # Loop till the end of file to insert the "pre_test" and "post_test"
    i=0
    while [ $i -lt ${#arr[@]} ]; do
        i_next=$(($i + 1))

        from=$(echo ${arr[$i]} | awk -F':' '{print $2}')

	# We just want SED matches the lines in a range, but not the whole
        # file. That's why we use "from_line" and "to_line".	
        from_line=$(echo ${arr[$i]} | awk -F':' '{print $1}')

        if [ $i_next -lt ${#arr[@]} ]; then
            to=$(echo ${arr[$i_next]} | awk -F':' '{print $2}')
            to_line=$(echo ${arr[$i_next]} | awk -F':' '{print $1}')
        else 
            to='EOF' 
            to_line=$(wc -l $_case | awk '{print $1}')
        fi

        kv_pairs=$(get_kv_pairs $_case $from $to $from_line $to_line)

        pre_test="pre_test $from $(($i + 1)) [$from]$versions$kv_pairs"
        post_test='post_test $? ""'

        # We can't use command like "/f/,/t/ /re/i bla" in sed to just
        # insert "bla" before the line "re" matches in a address range 
        # "/f/,/t/". Simply insert(/re/i bla) will cause "bla" inserted 
        # before all the matches. However, it's not what we want.
        # To work around, we generate a random string, make use of 
        # "/f/,/t/ s/re/bla" to replace the line before which we want to
        # insert something with the random string, which will be uniq in
        # the whole file, then we can insert simply using "/re/i bla".
        # Trick is not a smart trick. :-)
        # FIXME: We need a more reliable random string.
        label="XXXXXX-label-$RANDOM"

        if [ $from_line -lt $to_line ]; then
            sed -i -e "$from_line,$((to_line - 1)) s/^$from/$label/" $_case
            sed -i -e "/^$label/ i $pre_test" $_case
            sed -i -e "s/^$label/$from/g" $_case
        else
            sed -i -e "$from_line i $pre_test" $_case
        fi

        from_line=$(($from_line + 1))
        to_line=$(($to_line + 1))

        if  [[ $to != 'EOF' ]]; then
            sed -i -e "$((from_line + 1)),$to_line s/^$to/$label/" $_case
            sed -i -e "/^$label/ i $post_test" $_case
            sed -i -e "s/^$label/$to/g" $_case
        else
            sed -i -e "$ a $post_test" $_case
            break
        fi

        # Re-init the function names, because the line numbers are changed 
        # caused by inserted "pre_test" and "post_test".
        function_names=$(grep -n '^\w' $_case | grep -Ev $re | sed 's/\\//g') 

        # Never use 'i' here, u known. :-)
        j=0
        for f in ${function_names}; do
             arr[$j]=$f
            j=$(($j + 1))
        done

        i=$(($i + 1))
    done
}

# Get the value of "summary" specified in case
# @case: file path of case
get_case_summary() {
    [ $# -ne 1 ] && die "Usage: get_case_summary <case>"

    local _case

    _case=$1

    grep '^summary=' $_case | awk -F'=' '{print $2}'
}
    
# Construct and insert "add_summary" statement at the bottom of case.
# @case: file path of case
insert_add_summary() {
    [ $# -ne 1 ] && die "Usage: insert_add_summary <case>"
     
    local _case summary add_summary

    _case=$1
    summary=$(get_case_summary $_case)
    add_summary="add_summary $summary"

    lines=$(wc -l $_case | awk -F'=' '{print $2}')

    sed -i -e "$ a $add_summary" $_case 
}

# Reprocess the case, in order to make no harm on the case, we don't modify
# on the original case directly, but create a tempory case for use.
# Mainly action of reprocessing:
# 1. insert the contents of @headers 
# 2. insert statement for initializing log instance
# @headers: file defines the global viariables, and include other scripts that
#           needed by case
# @case   : file path of the case
# Return: the filename of tempory case.
reprocess_case() {
    [ $# -ne 2 ] && die "Usage: reprocess_case <headers> <case>"

    local headers orig_case mid_tmp_case final_tmp_case feature tc_name

    headers=$1
    orig_case=$2
    mid_tmp_case=$(mktemp)
    final_tmp_case=$(mktemp)
    tc_name_tmp=$(mktemp)
    tc_name=$(basename $orig_case)
    feature=$(basename $(dirname $orig_case))

    echo "$feature/$tc_name" > $tc_name_tmp

    cp $orig_case $mid_tmp_case

    insert_pretest_postest $mid_tmp_case 
    insert_casename $mid_tmp_case $orig_case
    insert_init_log $mid_tmp_case $orig_case
    insert_add_summary $mid_tmp_case

    cat $headers $mid_tmp_case >> $final_tmp_case

    echo $final_tmp_case
}

# __UTILS_CASER__
