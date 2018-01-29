#! /bin/sh
# Description: To provide API to end-user to run some common methods.
# Author: Osier Yang <jyang@example.com>
# Maintainer: Alex Jia <ajia@example.com>
# Update: Jan 29, 2018


__COMMON_LIB__=1

[ -z "${__UTILS_COMMON__}" ] && source utils/common.sh

setup_ssh_tunnel() {
    [ $# -lt 1 ] && die "Usage: setup_ssh_tunnel <hostname=STRING> \
        [username=STRING] [password=STRING] [passphrase=STRING]"

    local table hostname username password passphrase
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    hostname=$(hash_get $table hostname)
    username=$(hash_get $table username)
    password=$(hash_get $table password)
    passphrase=$(hash_get $table passphrase)

    [ -z "$hostname" ] && die "$FUNCNAME: value of hostname is empty"
    [ -z "$username" ] && username=$REMOTE_USER
    [ -z "$password" ] && password=$REMOTE_PASSWD
    [ -z "$passphrase" ] && passphrase=$REMOTE_PASSWD

    info_log "check if id_rsa.pub exist"
    ls ~/.ssh/id_rsa.pub
    if [ $? -ne 0 ]; then
        info_log "generate ssh key with passphrase: $passphrase"
        _ssh_keygen $passphrase

        if [ $? -ne 0 ]; then
            err_log "Failed on generating ssh key"
            return 1
        fi
    fi

    _remote_exec_once $hostname $username $password "ls ~/.ssh"
    if [ $? -ne 0 ]; then
        info_log "create dir ~/.ssh on $hostname"
        cmd="mkdir -p ~/.ssh"
        _remote_exec_once $hostname $username $password "$cmd"

        if [ $? -ne 0 ]; then
            err_log "FAIL"
            return 1
        else
            info_log "OK"
        fi
    fi

    info_log "dispatch ssh key to $hostname ($username:$password)"
    _dispatch_ssh_key $hostname $username $password

    if [ $? -ne 0 ]; then
        err_log "Failed on dispatching ssh key"
        return 1
    fi

    info_log "add ssh agent"
    _ssh_add "$(whoami)"

    if [ $? -ne 0 ]; then
        err_log "Failed on adding ssh agent"
        return 1
    fi
}

setup_ssh_tunnel_dest_to_host() {
    [ $# -lt 1 ] && die "Usage: setup_ssh_tunnel_reverse <hostname=STRING> \
        <destname=STRING> [username=STRING] [password=STRING] \
        [passphrase=STRING]"

    local table hostname username password passphrase destname
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    hostname=$(hash_get $table hostname)
    destname=$(hash_get $table destname)
    username=$(hash_get $table username)
    password=$(hash_get $table password)
    passphrase=$(hash_get $table passphrase)

    [ -z "$hostname" ] && die "$FUNCNAME: value of hostname is empty"
    [ -z "$destname" ] && die "$FUNCNAME: value of destname is empty"
    [ -z "$username" ] && username=$REMOTE_USER
    [ -z "$password" ] && password=$REMOTE_PASSWD
    [ -z "$passphrase" ] && passphrase=$REMOTE_PASSWD

    info_log "check if id_rsa.pub exist"
    cmd="ls ~/.ssh/id_rsa.pub"
    _remote_exec_command $destname $REMOTE_USER $cmd

    if [ $? -ne 0 ]; then
        info_log "generate ssh key"
        _copy_to_remote ${UTILS_DIR}/gen-ssh-key.exp /tmp $destname $REMOTE_USER
        [ $? -eq 1 ] && return 1

        cmd="/usr/bin/expect /tmp/gen-ssh-key.exp ${REMOTE_PASSWD} > /dev/null"
        _remote_exec_command $destname $REMOTE_USER $cmd

        if [ $? -ne 0 ]; then
            err_log "Failed on generating ssh key"
            return 1
        fi
    else
        info_log "OK"
    fi

    _copy_to_remote ${UTILS_DIR}/ssh-copy-id.exp /tmp $destname $REMOTE_USER
    [ $? -eq 1 ] && return 1

    info_log "dispatch ssh key to $hostname from $destname"

    cmd="/usr/bin/expect /tmp/ssh-copy-id.exp ${hostname} ${REMOTE_PASSWD} > \
         /dev/null"

    _remote_exec_command $destname $REMOTE_USER $cmd

    if [ $? -ne 0 ]; then
        err_log "FAIL"
        return 1
    else
        info_log "OK"
        return 0
    fi
}

# Set up ssh tunnel to domain on remote host. Depends on function 
# setup_ssh_tunnel
# FIXME: only support set up the tunnel to the domain on remote host
# which is in the same subnet of the host excutes virsh-rail
setup_ssh_tunnel_to_remote_domain() {
    if [ $# -lt 2 ]; then
        die "Usage: setup_ssh_tunnel_for_remote_domain <hostname=STRING> \
            <domain_name=STRING> [username=STRING] [domain_username=STRING] \
            [domain_passwd] [domain_passphrase=STRING]"
    fi

    local table hostname username domain_name domain_ip domain_username 
    local domain_passwd domain_passphrase cmd network_xml output
    local tmpfile network netmask gateway temp_domain_xml mac temp_net_xml
    local _timeout sshd_status
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    hostname=$(hash_get $table hostname)
    username=$(hash_get $table username)
    domain_name=$(hash_get $table domain_name)
    domain_username=$(hash_get $table domain_username)
    domain_passwd=$(hash_get $table domain_passwd)
    domain_passphrase=$(hash_get $table domain_passphrase)

    [ -z "$hostname" ] && die "$FUNCNAME: value of hostname is empty"
    [ -z "$domain_name" ] && die "$FUNCNAME: value of domain_name is empty"

    [ -z "$username" ] && username=$REMOTE_USER
    [ -z "$domain_username" ] && domain_username=$REMOTE_USER
    [ -z "$domain_passwd" ] && domain_passwd=$REMOTE_PASSWD
    [ -z "$domain_passphrase" ] && domain_passphrase=$REMOTE_PASSWD

    temp_net_xml=$(mktemp)
    temp_domain_xml=$(mktemp)
    _timeout=500

    _remote_operate_net $hostname $username "dumpxml" $temp_net_xml
    [ $? -eq 1 ] && return 1

    info_log "modify $temp_net_xml - s/122/123"
    _modify_default_network_xml $temp_net_xml
    [ $? -eq 1 ] && return 1

    _copy_to_remote $temp_net_xml "/tmp" $hostname    
    [ $? -eq 1 ] && return 1

    _remote_operate_net $hostname $username "destroy"
    [ $? -eq 1 ] && return 1

    _remote_operate_net $hostname $username "undefine"
    [ $? -eq 1 ] && return 1

    _remote_operate_net $hostname $username "define" $temp_net_xml
    [ $? -eq 1 ] && return 1

    _remote_operate_net $hostname $username "start"
    [ $? -eq 1 ] && return 1

    _remote_operate_net $hostname $username "autostart"
    [ $? -eq 1 ] && return 1

    _remote_operate_domain $hostname $username "destroy" $domain_name
    [ $? -eq 1 ] && return 1

    _remote_operate_domain $hostname $username "start" $domain_name
    [ $? -eq 1 ] && return 1

    _copy_to_remote $UTILS_DIR/mac2ip.sh /tmp $hostname $username 
    [ $? -eq 1 ] && return 1

    _remote_domain_dumpxml $hostname $username $domain_name $temp_domain_xml
    
    info_log "parse mac address from $temp_domain_xml"
    mac=$(_xml_domain_parse_mac $temp_domain_xml) 
    info_log "mac: $mac"

    if [ $? -eq 1 ]; then
        info_log "domain xml:"
        info_log "$(cat $temp_domain_xml)"
        err_log "failed on getting mac address from $domain_xml"
        return 1
    fi

    info_log "parse subnet of the bridge that domain connects to"
    _remote_net_parse_subnet $hostname $username $domain_name default subnet
    [ $? -eq 1 ] && return 1

    info_log "subnet: $subnet"

    _remote_exec_command $hostname $username "chmod +x /tmp/mac2ip.sh"

    info_log "check if nmap is installed on $hostname"
    output=$(_remote_exec_command $hostname $username "rpm -q nmap")
    ret=$?

    info_log "output: $output"
    if [ $ret -ne 0 ]; then
        err_log "nmap is not installed on $hostname, can't continue"
        return 1
    fi

    info_log "get ip of domain $domain_name on $hostname, timeout = 500s"
    
    while [ $_timeout -gt 0 ]; do
        domain_ip=$(_remote_exec_command $hostname $username "sh /tmp/mac2ip.sh \
            $subnet $mac")
        ret=$?
        
        [ $ret -eq 0 ] && [ -n "$domain_ip" ] && break

        sleep 10
        _timeout=$(($_timeout - 10))
        info_log "${_timeout}s left"
    done

    if [ -z "$domain_ip" ] || [ $ret -ne 0 ]; then
        info_log "output: $domain_ip"
        err_log "can't get domain ip"
        return 1
    else
        info_log "ip: $domain_ip"
    fi

    # For the functions follow with set_up_ssh_tunnel_to_domain use.
    export DOMAIN_IP=$domain_ip

    _remote_switch_route $hostname "on" $username
    [ $? -eq 1 ] && return 1

    # FIXME: need more flexiable here.
    network="192.168.123.0" 
    netmask="255.255.255.0"
    gateway=$hostname

    _route_rule_exists $network $netmask $gateway
    if [ $? -eq  1 ]; then
        _add_route_rule $network $netmask $gateway
        [ $? -eq 1 ] && return 1
    fi

    info_log "generate ssh key with passphrase: $domain_passphrase"
    _ssh_keygen $domain_passphrase

    if [ $? -ne 0 ]; then
        err_log "FAIL"
        return 1
    else
        info_log "OK"
    fi

    info_log "flush iptables on remote host"
    _remote_exec_command $hostname $username "iptables -F"
    
    if [ $? -ne 0 ]; then
        err_log "FAIL"
        return 1
    else
        info_log "OK"
    fi

    info_log "wait till sshd is up on $domain_ip, timeout = 100s"
    _timeout=100

    while [ $_timeout -gt 0 ]; do
        sshd_status=$(_get_sshd_status $domain_ip)

        [[ "$sshd_status" = "open" ]] && break

        sleep 10
        _timeout=$(($_timeout - 10))
        info_log "${_timeout}s left"
    done

    # Selinux will block we login into the guest automatically with the tunnel
    info_log "set selinux into permissive on $domain if it's enforcing"

    if [[ "$domain_username" != "root" ]]; then
        err_log "need root priviledge"
        return 1
    fi

    output=$(_remote_exec_once $domain_ip $domain_username $domain_passwd "setenforce 0")
    ret=$?

    [ -n "$output" ] && info_log "output: $output"

    if [ $ret -eq 0 ]; then
        info_log "OK"
    else
        err_log "FAIL"
        return 1
    fi

    _remote_exec_once $domain_ip $domain_username $domain_passwd "ls ~/.ssh"
    if [ $? -ne 0 ]; then
        info_log "create dir ~/.ssh on $domain_ip"
        cmd="mkdir ~/.ssh"
        _remote_exec_once $domain_ip $domain_username $domain_passwd "$cmd"

        if [ $? -ne 0 ]; then
            err_log "FAIL"
            return 1
        else
            info_log "OK"
        fi
    fi

    info_log "create file ~/.ssh/authorized_keys on $domain_ip"
    cmd="touch ~/.ssh/authorized_keys"
    _remote_exec_once $domain_ip $domain_username $domain_passwd "$cmd"

    if [ $? -ne 0 ]; then
        err_log "FAIL"
        return 1
    else
        info_log "OK"
    fi

    info_log "dispatch ssh key to $domain_ip ($domain_username:$domain_passwd)"
    _dispatch_ssh_key $domain_ip $domain_username $domain_passwd

    if [ $? -ne 0 ]; then
        err_log "FAIL"
        return 1
    else
        info_log "OK"
    fi

    info_log "add ssh agent"
    _ssh_add "$(whoami)"

    if [ $? -ne 0 ]; then
        err_log "FAIL"
        return 1
    else
        info_log "OK"
    fi

    return 0
}

remote_exec_command() {
    if [ $# -lt 2 -o $# -gt 5 ]; then
        die "Usage: ${FUNCNAME} <hostname=STRING> [username=STRING] \
            <command=STRING> [outfile=STRING] [expect_result=SUCCESS|FAIL]"
    fi

    local table hostname username command outfile expect_result
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    hostname=$(hash_get $table hostname)
    username=$(hash_get $table username)
    outfile=$(hash_get $table outfile) 
    command="$(hash_get $table command)"
    expect_result="$(hash_get $table expect_result)"

    [ -z "$hostname" ] && die "$FUNCNAME: value of hostname is empty"
    [ -z "$command" ] && die "$FUNCNAME: value of command is empty"
    [ -z "$username" ] && username=$REMOTE_USER
    [ -z "$expect_result" ] && expect_result="SUCCESS"

    if [ "$expect_result" != "SUCCESS" ] && [ "$expect_result" != "FAIL" ]; 
    then
        err_log "value of expect_result must be one of 'SUCCESS' and 'FAIL'"
        return 1
    fi

    info_log "execute $command on $hostname"
    output=$(_remote_exec_command "$hostname" "$username" "$command")
    ret=$?

    if [ -n "$outfile" ]; then
        echo $output > $outfile
    fi

    if [ $ret -eq 0 -a "$expect_result" == "SUCCESS" ] || \
        [ $ret -ne 0 -a "$expect_result" == "FAIL" ]; then
        info_log "OK"
        return 0
    else
        err_log "fail to execute remote command: $output"
        return 1
    fi
}

remote_exec_command_bg() {
    if [ $# -lt 2 -o $# -gt 3 ]; then
        die "Usage: ${FUNCNAME} <hostname=STRING|domain_name=STRING> \
            [username=STRING] <command=STRING>"
    fi

    local table hostname domain_name username command
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    hostname=$(hash_get $table hostname)
    domain_name=$(hash_get $table domain_name)
    username=$(hash_get $table username)
    command="$(hash_get $table command)"

    if [ -z "$domain_name" ] && [ -z "$hostname" ]; then
        die "$FUNCNAME: at least one of 'domain_name' and 'hostname' should be \
             given"
    fi

    [ -z "$command" ] && die "$FUNCNAME: value of command is empty"
    [ -z "$username" ] && username=$REMOTE_USER

    if [ -n "$domain_name" ]; then
        hostname=$(_get_domain_ip $domain_name)
        debug_log "$domain_name ip address: $hostname"
    fi

    info_log "execute $command on $hostname"
    output=$(_remote_exec_command_bg "$hostname" "$username" "$command")
    ret=$?

    [ $ret -ne 0 ] && info_log "output: $output" || info_log "OK"

    return $ret
}

remote_exec_once() {
    if [ $# -lt 2 -o $# -gt 6 ]; then
        die "Usage: remote_exec_once <domain_name=STRING | hostname=STRING>  \
            <command=STRING> [outfile=FILE] [expect_result=SUCCESS/FAIL] [timeouts=NUMBER]"
    fi

    local table command hostname domain_name expect_result output ret timeouts
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    domain_name=$(hash_get $table domain_name)
    hostname=$(hash_get $table hostname)
    command=$(hash_get $table command)
    outfile=$(hash_get $table outfile)
    expect_result=$(hash_get $table expect_result)
    timeouts=$(hash_get $table timeouts)

    if [ -z "$domain_name" ] && [ -z "$hostname" ]; then
        die "$FUNCTION: at least one of 'domain_name' and 'hostname' is not empty"
    fi

    [ -z "$command" ] && die "$FUNCTION: value of 'command' is empty"
    [ -z "$expect_result" ] && expect_result="SUCCESS"

    if [ -n "$domain_name" ]; then
        hostname=$(_get_domain_ip $domain_name)
        debug_log "$domain_name ip address: $hostname"
    fi

    info_log "execute $command on $hostname , waiting.."

    output=$(_remote_exec_once $hostname ${REMOTE_USER} \
        ${REMOTE_PASSWD} "$command" $timeouts)
    ret=$?
    [ $ret -ne 0 ] && ret=1
    
    [ -n "$outfile" ] && echo "$output" > $outfile

    info_log "output: $output"

    case $ret:$expect_result in
        0:SUCCESS)  
            return 0
        ;;
        0:FAIL)     
            return 1 
        ;;
        1:SUCCESS)  
            return 1 
        ;;
        1:FAIL)     
            return 0 
        ;;
    esac
}

check_device_by_lspci() {
    [ $# -lt 2 -o $# -gt 3 ] && die "Usage: check_device_by_lspci \
        <domain_name=STRING> <device_name=STRING> [expect_result=SUCCESS|FAIL]"
   
    local table hostname domain_name device_name output expect_result cmd ret
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    domain_name=$(hash_get $table domain_name)
    device_name=$(hash_get $table device_name)
    expect_result=$(hash_get $table expect_result)

    [ -z "$domain_name" ] && die "$FUNCTION: value of 'domain_name' is empty"
    [ -z "$device_name" ] && die "$FUNCTIOn: value of 'device_name' is empty"
    [ -z "$expect_result" ] && expect_result="SUCCESS"

    device_info="$(_find_device_by_name $device_name 'pci')"
    debug_log "PCI device information: $device_info"

    hostname=$(_get_domain_ip $domain_name)
    debug_log "$domain_name ip address: $hostname"

    cmd="lspci | grep '$device_info'"
    output=$(_remote_exec_once $hostname ${REMOTE_USER} ${REMOTE_PASSWD} \
        "$cmd")
    ret=$?
    [ $ret -ne 0 ] && ret=1

    info_log "output: $output"
    case $ret:$expect_result in
        0:SUCCESS)
            return 0
        ;;
        0:FAIL)
            return 1
        ;;
        1:SUCCESS)
            return 1
        ;;
        1:FAIL)
            return 0
        ;;
    esac
}

check_device_by_lsusb() {
    [ $# -ne 2 -o $# -gt 3 ] && die "Usage: check_device_by_lsusb \
        <domain_name=STRING> <device_name=STRING> [expect_result=SUCCESS|FAIL]"

    local table hostname domain_name device_name output expect_result cmd ret
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    domain_name=$(hash_get $table domain_name)
    device_name=$(hash_get $table device_name)
    expect_result=$(hash_get $table expect_result)

    [ -z "$domain_name" ] && die "$FUNCTION: value of 'domain_name' is empty"
    [ -z "$device_name" ] && die "$FUNCTION: value of 'device_name' is empty"
    [ -z "$expect_result" ] && expect_result="SUCCESS"

    device_info="$(_find_device_by_name $device_name 'usb')"
    debug_log "USB device information: $device_info"

    hostname=$(_get_domain_ip $domain_name)
    debug_log "$domain_name ip address: $hostname"

    cmd="lsusb|grep '$device_info'"
    output=$(_remote_exec_once $hostname ${REMOTE_USER} ${REMOTE_PASSWD} \
        "$cmd")
    ret=$?
    [ $ret -ne 0 ] && ret=1

    info_log "output: $output"
    case $ret:$expect_result in
        0:SUCCESS)
            return 0
        ;;
        0:FAIL)
            return 1
        ;;
        1:SUCCESS)
            return 1
        ;;
        1:FAIL)
            return 0
        ;;
    esac
}

remote_support_virtio_blk() {
    [ $# -lt 2 -o $# -gt 3 ] && die "Usage: remote_support_virtio_disk <domain_name=STRING> \
        <device_type=STRING> [timeouts=NUMBER]"

    local table hostname command device_type domain_name cmd_output timeouts
    local cmd_ret target_file
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    domain_name=$(hash_get $table domain_name)
    device_type=$(hash_get $table device_type)
    timeouts=$(hash_get $table timeouts)
    [ -z "$domain_name" ] && die "$FUNCTION: value of 'domain_name' is empty"
    [ -z "$device_type" ] && die "$FUNCTION: value of 'device_type' is empty"

    hostname=$(_get_domain_ip $domain_name)
    info_log "$domain_name ip address: $hostname"

    target_file=$(_remote_exec_once $hostname ${REMOTE_USER} ${REMOTE_PASSWD} \
                      "find /boot | grep init | grep -v kdump | grep \$(uname -r)")
    info_log "$domain_name initrd file: $target_file"

    command="mkinitrd --with virtio_pci --with virtio_${device_type} -f \
            $target_file \$(uname -r)"
    cmd_output=$(_remote_exec_once $hostname ${REMOTE_USER} ${REMOTE_PASSWD} \
              "${command}" $timeouts)

    cmd_ret=$?
    info_log "$cmd_output"

    return "$cmd_ret"
}

remote_support_virtio_nic() {
    [ $# -ne 1 ] && die "Usage: remote_support_virtio_nic <domain_name=STRING>"

    local table hostname command domain_name cmd_output cmd_ret
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    domain_name=$(hash_get $table domain_name)
    [ -z "$domain_name" ] && die "$FUNCTION: value of 'domain_name' is empty"

    hostname=$(_get_domain_ip $domain_name)
    info_log "$domain_name ip address: $hostname"

    command="sed -i -e '/^alias eth0/c alias eth0 virtio_net' /etc/modprobe.conf"
    cmd_output=$(_remote_exec_once $hostname ${REMOTE_USER} ${REMOTE_PASSWD} \
              "${command}")
    cmd_ret=$?
    info_log "Editing /etc/modprobe.conf: \n $cmd_output"

    nics=0
    ifcfg_file="/etc/sysconfig/network-scripts/ifcfg-eth${nics}"
    command="echo -e \"DEVICE=eth${nics} \nBOOTPROTO=dhcp \nONBOOT=yes\" \
            > $ifcfg_file|cat $ifcfg_file"
    cmd_output=$(_remote_exec_once $hostname ${REMOTE_USER} ${REMOTE_PASSWD} \
              "${command}")
    cmd_ret=$?
    info_log "Generating ifcfg file: \n $cmd_output"

    return "$cmd_ret"
}

remote_inspect_nics() {
    [ $# -ne 1 ] && die "Usage: remote_inspect_nics <domain_name=STRING>"

    local table domain_name hostname nic_nums
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    domain_name=$(hash_get $table domain_name)
    [ -z "$domain_name" ] && die "$FUNCTION: value of 'domain_name' is empty"

    hostname=$(_get_domain_ip $domain_name)
    debug_log "$domain_name ip address: $hostname"

    nic_nums=$(_remote_inspect_nics $hostname ${REMOTE_USER} ${REMOTE_PASSWD})

    echo "$nic_nums"
}

remote_create_ifcfg() {
    [ $# -ne 1 ] && die "Usage: remote_create_ifcfg <domain_name=STRING>"

    local table domain_name hostname output ret
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    domain_name=$(hash_get $table domain_name)
    [ -z "$domain_name" ] && die "$FUNCTION: value of 'domain_name' is empty"

    hostname=$(_get_domain_ip $domain_name)
    debug_log "$domain_name ip address: $hostname"

    output=$(_remote_create_ifcfg $hostname ${REMOTE_USER} ${REMOTE_PASSWD})
    ret=$?

    [ $ret -ne 0 ] && info_log "output: $output" || info_log "OK"
    return $ret
}

remote_set_serial_to_kernel() {
    if [ $# -ne 1 ]; then 
        die "Usage: remote_set_serial_to_kernel <domain_name=STRING>"
    fi

    local table hostname domain_name output ret
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    domain_name=$(hash_get $table domain_name)
    [ -z "$domain_name" ] && die "$FUNCTION: value of 'domain_name' is empty"

    hostname=$(_get_domain_ip $domain_name)
    debug_log "$domain_name ip address: $hostname"

    output=$(_remote_set_serial_to_kernel $hostname ${REMOTE_USER} \
        ${REMOTE_PASSWD})
    ret=$?

    [ $ret -ne 0 ] && info_log "output: $output" || info_log "OK"
    return $ret
}

remote_create_image() {
    if [ $# -ne 3 ]; then 
        die "Usage: remote_create_image <domain_name=STRING> \
            <image_file=FILENAME> <image_size=NUMBER>"
    fi

    local domain_name image_file image_size output ret
    debug_log "Received parameters: $@"

    local table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    domain_name=$(hash_get $table domain_name)
    image_file=$(hash_get $table image_file)
    image_size=$(hash_get $table image_size)

    [ -z "$domain_name" ] && die "$FUNCTION: value of 'domain_name' is empty"
    [ -z "$image_file" ] && die "$FUNCTION: value of 'image_file' is empty"
    [ -z "$image_size" ] && die "$FUNCTION: value of 'image_size' is empty"

    hostname=$(_get_domain_ip $domain_name)
    debug_log "$domain_name ip address: $hostname"

    command="dd if=/dev/zero of=$image_file bs=1 count=1 seek=$image_size \
             && ls -lh $image_file"

    output=$(remote_exec_once $hostname ${REMOTE_USER} ${REMOTE_PASSWD} \
        '${command}')
    ret=$?

    [ $ret -ne 0 ] && info_log "output: $output" || info_log "OK"
    return $ret
}

find_string_from_file() {
    [ $# -ne 2 ] && die "Usage: find_string_from_file <string=STRING> \
        <file_name=FILENAME>"

    local string file_name output ret
    debug_log "Received parameters: $@"

    local table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    string=$(hash_get $table string)
    file_name=$(hash_get $table file_name)

    [ -z "$string" ] && die "$FUNCTION: value of 'string' is empty"
    [ -z "$file_name" ] && die "$FUNCTION: value of 'file_name' is empty"

    output=$(_find_string_from_file "$string" $file_name)
    ret=$?

    [ $ret -ne 0 ] && info_log "output: $output" || info_log "OK"
    return $ret
}

create_image() {
    [ $# -lt 3 -o $# -gt 4 ] && die "Usage: create_image <format=STRING> \
        <image_path=FILENAME> <image_size=NUMBER> [other_options=STRING]"
    
    local format image_path image_size other_options
    debug_log "Received parameters: $@"

    local table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"
    format=$(hash_get $table format)
    image_path=$(hash_get $table image_path)
    image_size=$(hash_get $table image_size)
    other_options=$(hash_get $table other_options)

    [ -z "$format" ] && die "$FUNCTION: value of 'format' is empty"
    [ -z "$image_path" ] && die "$FUNCTION: value of 'image_path' is empty"
    [ -z "$image_size" ] && die "$FUNCTION: value of 'image_size' is empty"

    ret=$(_create_image $format "$image_path" $image_size "$other_options")
    
    if [ $? -eq 0 ]; then
        info_log "The image is created successfully.\n $ret"
        return 0
    else
        err_log "The image is created failed.\n $ret"
        return 1
    fi
}

format_image() {
    [ $# -ne 2 ] && die "Usage: format_image <image_path=FILENAME> \
        <fs_type=STRING>"

    local table image_path fs_type
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    image_path=$(hash_get $table image_path)
    fs_type=$(hash_get $table fs_type)

    [ -z "$image_path" ] && die "$FUNCTION: value of 'image_path' is empty"
    [ -z "$fs_type" ] && die "$FUNCTION: value of 'fs_type' is empty"

    ret=$(_format_image $image_path $fs_type)

    if [ $? -eq 0 ]; then
        info_log "The image is formated successfully.\n $ret"
        return 0
    else
        err_log "The image is formated failed.\n $ret"
        return 1
    fi
}

chkconfig_service() {
    [ $# -ne 2 ] && die "Usage: chkconfig_service <service_name=STRING> \
        <op=STRING>"

    local table service_name op
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    service_name=$(hash_get $table service_name)
    op=$(hash_get $table op)

    [ -z "$service_name" ] && die "$FUNCTION: value of 'service_name' is empty"
    [ -z "$op" ] && die "$FUNCTION: value of 'op' is empty"

    debug_log "$(chkconfig_service $service_name $op)"
}

manage_libvirtd() {
    [ $# -ne 1 ] && die "Usage: manage_libvirtd <op=STRING>"

    local table op
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    op=$(hash_get $table op)
    [ -z "$op" ] && die "$FUNCTION: value of 'op' is empty"

    debug_log "$(manage_libvirtd $op)"
}

# FIXME: need to deal with a domain with multiple interfaces
get_domain_mac() {
    [ $# -ne 2 ] && die "Usage: get_domain_mac <domain_name=STRING> \
        <domain_mac=EMPTY>"

    local table domain_name
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    domain_name=$(hash_get $table domain_name)
    [ -z "$domain_name" ] && die "$FUNCNAME: value of domain_name is empty"

    info_log "get mac address of domain: $domain_name"
    domain_mac=$(_get_domain_mac $domain_name)
    ret=$?

    info_log "$domain_mac"
    return $ret
}

do_ping() {
    [ $# -ne 1 ] && die "Usage: do_ping <hostname=STRING>"

    local table hostname
    debug_log "Received parameters: $@"
    
    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"
    hostname=$(hash_get $table hostname)
    
    [ -z "$hostname" ] && die "$FUNCTION: value of hostname is empty"

    info_log "ping $hostname"
    _do_ping $hostname
}

exec_command() {
    if [ $# -lt 1 -o $# -gt 3 ]; then 
        die "Usage: exec_command <command=STRING> [expect_result=SUCCESS|FAIL] 
            [expect_value=STRING/NUMBER]"
    fi

    local table command expect_result ret
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"
    
    command=$(hash_get $table command)
    expect_result=$(hash_get $table expect_result)
    expect_value=$(hash_get $table expect_value)

    [ -z "$command" ] && die "$FUNCNAME: value of command is empty"
    [ -z "$expect_result" ] && expect_result="SUCCESS"

    info_log "execute command: $command"
    output=$(eval "$command" 2>&1)
    #eval $command
    ret=$?

    [ -n "$output" ] && info_log "output: $output"
    [ $ret -ne 0 ] && ret=1

    if [ $ret -eq 0 ] && [ -n "$expect_value" ]; then
        info_log "expect_value=$expect_value"
        if [ "$output" = "$expect_value" ]; then
            ret=0
        else
            ret=1
        fi
    fi 

    case $ret:$expect_result in
        0:SUCCESS)  
            return 0 
        ;;
        0:FAIL)     
            return 1 
        ;;
        1:SUCCESS)  
            return 1 
        ;;
        1:FAIL)     
            return 0 
        ;;
    esac
}

config_nfs_service() {
    if [ $# -lt 2 -o $# -gt 4 ]; then
        die "Usage: setup_nfs_service <path=STRING> <client=STRING> \
             [nfs_option=STRING] [op=add|del]"
    fi

    local table path client nfs_option op ret
    debug_log "Received parameters: $@"
    
    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    path=$(hash_get $table path)
    client=$(hash_get $table client)
    nfs_option=$(hash_get $table nfs_option)
    op=$(hash_get $table op)

    [ -z "$path" ] && die "$FUNCNAME: value of path is empty"
    [ -z "$client" ] && die "$FUNCNAME: value of client is empty"
    [ -z "$nfs_option" ] && nfs_option="rw,no_root_squash,async"
    [ -z "$op" ] && op="add"

    case $op in
        "add")
            cat >> /etc/exports <<STR
$path $client($nfs_option) 127.0.0.1($nfs_option) \
localhost($nfs_option)
STR
            info_log "add nfs sharing dirs for $path"
        ;;
        "del")
            sed -i ":^${path}\s: d" /etc/exports
            info_log "cancel sharing dirs for $path"
        ;;
        *)
            err_log "unknown operation type"
            return 1
        ;;
        esac

    ret=$?
    info_log "$(cat /etc/exports)"

    [ $ret -ne 0 ] && return 1 || return 0
}

manage_service_nfs() {
    [ $# -ne 1 ] && die "Usage: manage_service_nfs <op=STRING>"

    local table op
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"
 
    op=$(hash_get $table op)
    [ -z "$op" ] && die "$FUNCNAME: value of op is empty"

    if [ "$op" != "start" ] && [ "$op" != "restart" ] && [ "$op" != "stop" ];
    then
        err_log "unknown operation: $op"
        return 1
    fi

    info_log "$op service nfs"
    os_ver=$(uname -r|awk -F. '{print $(NF-1)}')
    echo "os_ver=$os_ver"
    if [ "$os_ver" = "el7" ]; then
        systemctl $op nfs-server.service
    else 
        service nfs $op
    fi

    [ $? -ne 0 ] && return 1 || return 0
}

# Modify gateway address and dhcp range of libvirt network xml.
# Subtitue 122 with 123 in network xml.
# Return 1 on SUCCESS, or 0 on FAILURE.
remote_modify_default_network_xml() {
    [ $# -ne 1 ] && die "Usage: $FUNCNAME <hostname> <username> <network xml>"

    local hostname username netxml
    debug_log "Received parameters: $@"
    
    hostname=$1
    username=$2
    netxml="$@"

    new_netxml=$(echo "${netxml}" | sed -i 's/122/123/g')

    is_active=$(remote_is_default_network_active ${hostname} ${username})
    if [[ $is_active -eq 1 ]]; then
       remote_destroy_default_network ${hostname} ${username}
       [[ $? -ne 1 ]] && die "Failed on destroy default network on ${hostname}"
    fi

    is_defined=$(remote_default_network_defined ${hostname} ${username})
    if [[ $is_defined -eq 1 ]]; then
       remote_undefine_default_network ${hostname} ${username}
       [[ $? -ne 1 ]] && die "Failed on undefine default network on ${hostname}"
    fi
     
    command="virsh net-define ${new_xml}"
    ret=$(remote_exec ${hostname} ${username} ${command})
    
    if echo "${ret}" | grep -q 'defined from'; then
        echo 1
    else
        echo 0
    fi
}

# Validate libvirt XML files against a schema,see (virt-xml-validate(1)
validate_xml() {
    [ $# -lt 1 ] && die "Usage: validate_xml <xml=STRING> [schema=STRING] \
        [expect_result=SUCCESS/FAIL]"
  
    if ! $(which virt-xml-validate > /dev/null); then
        die "$FUNCNAME: command virt-xml-validate can't be found"
    fi

    local table xml schema expect_result
    debug_log "Received parameters: $@"
  
    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    xml=$(hash_get $table xml)
    schema=$(hash_get $table schema)
    expect_result=$(hash_get $table expect_result)

    ! [ -f "$xml" ] && die "$FUNCNAME: $xml is not a file"
    [ -z "$expect_result" ] && expect_result="SUCCESS"

    if [ "$expect_result" != "SUCCESS" ] && [ "$expect_result" != "FAIL" ]; 
    then
        die "$FUNCNAME: value of expect_result must be one of 'SUCCESS' and \
            'FAIL'"
    fi

    case "$schema" in
        "domain" | "network" | "storagepool" | "storagevol" | "nodedev" | \
            "capability")
            break
        ;;
        "")
            warn_log "value of scheme is empty"
            warn_log "virt-xml-validate will recongnize it from root element \
                of the xml"
            break
        ;;
        *)
            err_log "unknown schema: $schema"
        ;;
    esac

    info_log "validate $xml using virt-xml-validate"
    output=$(virt-xml-validate "$xml" "$schema" 2>&1)
    ret=$?
  
    info_log "output: $output"

    if [ $ret -eq 0 ] && [ "$expect_result" = "SUCCESS" ]; then
        return 0
    elif [ $ret -eq 0 ] && [ "$expect_result" = "FAIL" ]; then
        err_log "expect FAIL, but SUCCESS actually"
        return 1
    elif [ $ret -ne 0 ] && [ "$expect_result" = "FAIL" ]; then
        err_log "expected FAIL"
        return 0
    elif [ $ret -ne 0 ] && [ "$expect_result" = "SUCCESS" ]; then
        return 1
    fi
}

# Copy file/directory from local to remote. 
# Return 1 on SUCCESS, or 0 on FAILURE.
copy_to_remote() {
    [ $# -lt 3 -o $# -gt 5 ] && die "Usage: copy_to_remote <hostname=STRING> \
        <srcfile=FILENAME> <dstfile=FILENAME> [username=STRING] \
        [password=STRING]"

    local table hostname username srcfile dstfile output
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    hostname=$(hash_get $table hostname)
    username=$(hash_get $table username)
    password=$(hash_get $table password)
    srcfile=$(hash_get $table srcfile)
    dstfile=$(hash_get $table dstfile)
 
    [ -z "$username" ] && username=$REMOTE_USER
    [ -z "$password" ] && password=$REMOTE_PASSWD
    [ -z "$hostname" ] && die "$FUNCNAME: value of hostname is empty"
    [ -z "$srcfile" ] && die "$FUNCNAME: value of srcfile is empty"
    [ -z "$dstfile" ] && die "$FUNCNAME: value of dstfile is empty"

    _copy_to_remote ${srcfile} ${dstfile} ${hostname} \
        ${username} ${password}
    ret=$?

    [ $ret -ne 0 ] && return 1 || return 0
}

# Modify libvirt default network xml, substitute 122 with 123.
modify_default_network_xml() {
    [ $# -ne 1 ] && die "modify_default_network_xml <network_xml=FILENAME>"

    local table network_xml output
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"
  
    network_xml=$(hash_get $table network_xml)
    [ -z "$network_xml" ] && die "$FUNCNAME: value of network_xml is emtpy"

    info_log "substitute 122 with 123"
    output=$(sed -i -e 's/122/123/g' $network_xml)
    ret=$?

    [ -n "$output" ] && info_log "output: $output"

    [ $ret -ne 0 ] && return 1 || return 0
}
   
remote_operate_domain() {
    [ $# -ne 4 ] && die "Usage: remote_operate_domain <hostname=STRING> \
                         <username=STRING> <operation=STRING> \
                         <domain_name=STRING>"

    local table hostname username operation domain_name ret
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    hostname=$(hash_get $table hostname)
    username=$(hash_get $table username)
    operation=$(hash_get $table operation)
    domain_name=$(hash_get $table domain_name)

    [ -z "$hostname" ] && die "$FUNCTION: value of 'hostname' is empty"
    [ -z "$username" ] && die "$FUNCTION: value of 'username' is empty"
    [ -z "$operation" ] && die "$FUNCTION: value of 'operation' is empty"
    [ -z "$domain_name" ] && die "$FUNCTION: value of 'domain_name' is empty"

    ret=$(_remote_operate_domain $hostname $username $operation $domain_name)

    if [ $ret -eq 1 ]; then
        err_log "Failed to execute virsh command '$operation' on remote domain."
        return 1
    elif [ $ret -eq 0 ]; then
        return 0
    fi
}

# wait_and_return()
# waits for a process id and returns the return code of the waited process.
# This is to be used for jobs that're put in background .
wait_and_return() {
    if [[ $# != 1 ]]; then
        die "Usage: ${FUNCNAME} pid=<INTEGER>"
    fi

    local table pid
    table="${FUNCNAME}_${RANDOM}"

    hash_new $table "$@"
    pid=$(hash_get $table "pid")

    [ -z "$pid" ] && die "pid must be given"

    wait ${pid}
    return $?

}

# Get host ip address by hostname
# return host ip address
get_host_ip_by_hostname() {
    local host_ip ret

    host_ip="$(_get_host_ip_by_hostname)"
    ret=$?

    if [ $ret -eq 0  ]; then
        printf "$host_ip"
        return 0
    else
        printf "ip address is [$host_ip]"
        return 1
    fi
}

# Get target ip address by source hostname
# return target machine ip address
get_twins_ip_by_hostname() {
    local target_ip ret

    target_ip="$(_get_twins_ip_by_hostname)"
    ret=$?

    if [ $ret -eq 0  ]; then
        printf "$target_ip"
        return 0
    else
        printf "ip address is [$target_ip]"
        return 1
    fi
}

mac_generate() {
    local generate_mac 

    generate_mac=$(_mac_generator)
    ret=$?

    if [ $ret -eq 0 ];then
        echo "$generate_mac"
        return 0
    else
        echo "mac generate failed"
        return 1
    fi
}

# Remotely modprobe acpiphp module according to
# different os, except rhel6

is_remote_modprobe_acpiphp() {
    [ $# -ne 1 ] && die "Usage: is_remote_modprobe_acpiphp <domain_name=STRING>"    

    local domain_name ret table command
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"
    
    domain_name=$(hash_get $table domain_name)

    if [ -z "$domain_name" ]; then
        die "$FUNCTION: 'domain_name' is empty"
    fi

    remote_exec_once domain_name="$domain_name" \
         command="uname -r |grep el6"
 
    if [ $? -ne 0 ]; then
           remote_exec_once domain_name="$domain_name" \
               command="modprobe acpiphp"
           return $?
    else
         return 0
    fi    
}

# Calc the time difference between host and guest, and write the result
# to $result_file
calc_time_diff() {
    if [ $# -lt 2 ];then
        die "Usage; $FUNCNAME <hostname=STRING> <result_file=STRING>"
    fi
    [ -z "$DOMAIN_IP" ] && die "environment variable DOMAIN_IP is not exported"

    local table cmd ret time_diff result_file hostname source_host
    source_host=$(get_host_ip_by_hostname)

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    result_file=$(hash_get $table "result_file")
    hostname=$(hash_get $table "hostname")

    [ -z "$hostname" ] && die "$FUNCTION: value of 'hostname' is empty"
    [ -z "$result_file" ] && die "$FUNCTION: value of 'result_file' is empty"

    info_log "dispatch ssh key to $hostname ($REMOTE_USER:$REMOTE_PASSWD)"
    ret=$($EXPECT ${UTILS_DIR}/ssh-copy-id.exp ${hostname} ${REMOTE_PASSWD})
    if [ $? -ne 0 ]; then
        err_log "Failed on dispatching ssh key"
        return 1
    fi
    
    info_log "check if id_rsa.pub exist"
    cmd="ls ~/.ssh/id_rsa.pub"
    _remote_exec_command $hostname $REMOTE_USER $cmd

    if [ $? -ne 0 ]; then
        info_log "generate ssh key"
        _copy_to_remote ${UTILS_DIR}/gen-ssh-key.exp /tmp $hostname $REMOTE_USER
        [ $? -eq 1 ] && return 1

        cmd="/usr/bin/expect /tmp/gen-ssh-key.exp ${REMOTE_PASSWD} > /dev/null"
        _remote_exec_command $hostname $REMOTE_USER $cmd

        if [ $? -ne 0 ]; then
            err_log "Failed on generating ssh key"
            return 1
        fi
    else
        info_log "OK"
    fi

    _copy_to_remote ${UTILS_DIR}/ssh-copy-id.exp /tmp $hostname $REMOTE_USER
    [ $? -eq 1 ] && return 1

    info_log "dispatch ssh key to $DOMAIN_IP from $hostname"
    cmd="/usr/bin/expect /tmp/ssh-copy-id.exp ${DOMAIN_IP} ${REMOTE_PASSWD} > \
         /dev/null"

    _remote_exec_command $hostname $REMOTE_USER $cmd

    if [ $? -ne 0 ]; then
        err_log "FAIL"
        return 1
    else
        info_log "OK"
    fi

    info_log "dispatch ssh key to $source_host from $hostname"

    cmd="/usr/bin/expect /tmp/ssh-copy-id.exp ${source_host} ${REMOTE_PASSWD} > \
         /dev/null"

    _remote_exec_command $hostname $REMOTE_USER $cmd

    if [ $? -ne 0 ]; then
        err_log "FAIL"
        return 1
    else
        info_log "OK"
    fi

    info_log "write calc sh file to $hostname"

    echo '#!/bin/sh
time1=$(ssh root@'$DOMAIN_IP' date +%s); \
time2=$(ssh root@'$source_host' date +%s); \
time_diff=$(($time1-$time2))
echo "$time_diff"' > /tmp/calc.sh
    
    info_log  $(cat /tmp/calc.sh)

    _copy_to_remote /tmp/calc.sh /tmp $hostname $REMOTE_USER
    [ $? -eq 1 ] && return 1

    cmd="sh /tmp/calc.sh"

    time_diff=$(_remote_exec_command $hostname $REMOTE_USER $cmd)

    if [ $? -ne 0 ]; then
        err_log "Failed to get time diff"
        return 1
    else
        info_log "result of time diff is $time_diff"
        echo "$time_diff" >> "$result_file"
        return 0
    fi
}

#Compare the value in $result_file, the difference which is less
#than 1 is acceptable
compare_num_result() {
    if [ $# -lt 1 ];then
        die "Usage; $FUNCNAME <result_file=STRING>"
    fi
    local table num1 num2 ret

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    result_file=$(hash_get $table "result_file")

    count=$(cat $result_file |wc -l)
    if [ $count -ne 2 ]; then
        err_log "get wrong result number, num=$count"
        return 1
    fi

    num1=$(cat $result_file |head -1)
    num2=$(cat $result_file |tail -1)

    ret=$(($num1-$num2))
    if [ $ret -gt 1 -o $ret -lt -1 ]; then
        err_log "diff is $ret, in unacceptable scope"
        return 1
    else
        info_log "diff is $ret in acceptable scope"
        return 0
    fi
}

get_domain_ip() {
    if [ $# -lt 1 ];then
        die "Usage; $FUNCNAME <domain_name=STRING> [timeout=STRING]"
    fi

    local table domain_name timeout
    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    domain_name=$(hash_get $table "domain_name")
    timeout=$(hash_get $table "timeout")

    [ -z "$domain_name" ] && die "$FUNCTION: value of 'domain_name' is empty"
    [ -z "$timeout" ] && timeout=90

    domain_ip=$(_get_domain_ip $domain_name $timeout)
    ret=$?

    if [ $ret -eq 0 ];then
        echo "$domain_ip"
        export DOMAIN_IP="$domain_ip"
        return 0
    else
        echo "domain_ip get failed"
        return 1
    fi
}

# run spicec command on background
open_spice_background() {
    if [ $# -lt 2 ];then
        die "Usage; $FUNCNAME <hostname=STRING> <port_num=STRING>"
    fi

    local table hostname port_num ret cmd
    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    hostname=$(hash_get $table "hostname")
    port_num=$(hash_get $table "port_num")

    info_log "begin to open spice monitor"
    cmd="/usr/libexec/spicec -h $hostname -p $port_num"
    info_log "$cmd"
    $cmd &

    ret=$(ps aux |grep spicec|grep -v grep)

    if [ $? -ne 0 ]; then
        err_log "Failed to open the spice monitor"
        return 1
    else
        info_log "OK"
        return 0
    fi
}

# execute multiple commands concurrently
concurrent_exec_handling() {
    local table num ret i result command_name var fail_flag
    local expect_result

    num=$#
    if [ $num -lt 2 ]; then
        die "Usage: $FUNCTION <command1=STRING> <command2=STRING> ... \
            [commandn=STRING>] [expect_result=SUCCESS/FAIL]"
    fi

    echo 0 > /tmp/fail_flag

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    expect_result=$(hash_get $table "expect_result")
    if [ -n "$expect_result" ]; then
        if [ "$expect_result" != "SUCCESS" -a "$expect_result" != "FAIL"]; then
            die "The expect_result value must be SUCCESS/FAIL"
        fi
    fi

    for i in $(seq 1 $num); do
    (
        var="command$i"
        command_name=$(hash_get $table "$var")

        info_log "$command_name execute started"
        result=$(eval "$command_name" 2>&1)
        ret=$?
        if [ $ret -ne 0 ]; then
            err_log "Error: execute the $command_name error: $result"
            echo 1 > /tmp/fail_flag
            return 1
        else
            info_log "Command $command_name completed, result: $result"
        fi
    )&
    done
    wait

    fail_flag=$(cat /tmp/fail_flag)
    rm -rf /tmp/fail_flag
    if [ "$fail_flag" -eq 0 ]; then
        if [ "$expect_result" == "FAIL" ]; then
            err_log "Exec all commands successfully, but not as expected"
            return 1
        else
            info_log "Completed with all commands exec concurrently"
            return 0
        fi
    else
        if [ "$expect_result" == "FAIL" ]; then
            info_log "Fail to execute all commands concurrently as expected"
            return 0
        else
            err_log "Fail to execute all commands concurrently"
            return 1
        fi 
    fi
}

get_pci_device_addr() {
    if [ $# -lt 1 ];then
        die "Usage: get_device_pci_bus <keywords>"
    fi

    local table pci_bus keywords device_key device_info
    
    keywords=$@

    device_info=$(lspci |grep -i "$keywords")
    if [ $? -ne 0 ]; then
        err_log "Can not find the device with $keywords"
        return 1
    fi

    pci_bus=$(lspci -D|grep -i "$keywords"|head -1|cut -f1 -d' ')

    device_key="pci_${pci_bus:0:4}_${pci_bus:5:2}_${pci_bus:8:2}_${pci_bus:11:1}"

    echo "$device_key"
    return 0    
}

create_remote_repo(){
    if [ $# -lt 1 -o $# -gt 5 ]; then
        die "Usage: create_remote_repo <domain_name> [username] [password] \
             [repo_name=STRING] [base_url=STRING]"
    fi
    
    local domain_name domain_ip username password repo_name base_url 
    local get_url_cmd cat_repo_cmd cat_output ret
    debug_log "Received parameters: $@"

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"
    domain_name=$(hash_get $table "domain_name")
    username=$(hash_get $table "username")
    password=$(hash_get $table "password")
    repo_name=$(hash_get $table "repo_name")
    base_url=$(hash_get $table "base_url")
    
    if ! virsh list --all |grep $domain_name > /dev/null; then
        err_log "the guest $domain_name not find"
        return 1
    elif ! virsh list |grep $domain_name > /dev/null; then
        err_log "the guest $domain_name is not running"
        return 1
    fi
    domain_ip=$(_get_domain_ip $domain_name)
    debug_log "$domain_name ip address is: $domain_ip"

    [ -z "$username" ] && username=$REMOTE_USER
    [ -z "$password" ] && password=$REMOTE_PASSWD
    if [ -z "$repo_name" ]; then 
        repo_name="rhel-tree"
        info_log "Use the default repo name: $repo_name"
    fi
    if [ -z "$base_url" ]; then
        get_url_cmd="echo \$(grep ^url /root/anaconda-ks.cfg) | cut -d'=' -f2"
        info_log $get_url_cmd
        base_url=$(_remote_exec_once $domain_ip $username $password "$get_url_cmd")
        ret=$?
        if [ $ret -eq 0 ]; then
            info_log "Use the default base URL: $base_url"
        else
            err_log "Fail to get default base URL"
            return 1
        fi
    fi
    _create_remote_repo $domain_ip $username $password $repo_name $base_url
    ret=$?
    if [ $ret -ne 0 ]; then
        err_log "Fail to generate ${repo_name}.repo for ${domain_name}."
        return 1
    else
        cat_repo_cmd="cat /etc/yum.repos.d/${repo_name}.repo"
        info_log "$cat_repo_cmd in $domain_name"
        cat_output=$(_remote_exec_once $domain_ip $username $password "$cat_repo_cmd")
        if [ $? -ne 0 ];then
            err_log "No such repo find."
            return 1
        else
            info_log "$cat_repo_cmd output: $cat_output"
            return 0
        fi
    fi
}

wait_for_sshd(){
    if [ $# -lt 1 -o $# -gt 2 ]; then
        die "Usage: wait_for_sshd <ip_address> [timeout]"
    fi

    local ip_addr timeout

    table="${FUNCNAME}_${RANDOM}"
    hash_new $table "$@"

    ip_addr=$(hash_get $table ip_addr)
    timeout=$(hash_get $table timeout)

    [ -z "$timeout" ] && timeout="60"

    while [ $timeout -gt 0 ]; do
        _remote_exec_once $ip_addr ${REMOTE_USER} ${REMOTE_PASSWD} "pwd"
        if [ $? -ne 0 ]; then
            info_log "$timeout second left to wait"
            sleep 5
            let timeout=$timeout-5
        else
            info_log "Domain/host sshd started"
            return 0
        fi
    done
    err_log "TIMEOUT when waiting for domain/host sshd started"
    return 1
}

#__COMMON_LIB__

