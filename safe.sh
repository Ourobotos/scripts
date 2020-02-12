#!/bin/bash
# Script to add a user to Linux system

function prnt(){
    c_end="\033[0m"
    case $1 in
    -e) c_start="\033[31m[error] "
    ;;
    -s) c_start="\033[32m[success] "
    ;;    
    -w) c_start="\033[33m[waring] "
    ;;
    -i) c_start="\033[34m[info] "
    ;;    
    *) c_start=""; c_end=""
    ;;
    esac
    echo -e "$c_start$2$c_end"
}

function set_sshd(){
    # $1=Port $2=22
    prnt -i "before setting: "
    grep -E "${1}\s+(yes|no|[0-9]+)" /etc/ssh/sshd_config
    
    if [ "$3" == -y ]; then
        confirm=y
    else
        prnt -w "now switch ${1} to ${2} (y/n): "
        read confirm
    fi
    if [[ $confirm == y ]];then
        linenum=`grep -nE "${1}\s+(yes|no|[0-9]+)" /etc/ssh/sshd_config | cut -d ":" -f 1`
        if [[ -z $linenum ]]; then
            echo "${1} ${2}" >> /etc/ssh/sshd_config
        else
            i=0
            for num in ${linenum[@]}; do
                if [ $i -eq 0 ];then
                    sed -i "${num}c ${1} ${2}" /etc/ssh/sshd_config
                else
                    sed -i "${num}c #" /etc/ssh/sshd_config
                fi
                ((i++))
            done
        fi
        prnt -i  "after setting: "
        grep -E "${1}\s+(yes|no|[0-9]+)" /etc/ssh/sshd_config
        echo
    else
        prnt -w  "cancel!"
        echo
        exit 1
    fi
}

if [ $(id -u) -eq 0 ]; then
    # add new user
    read -p "Enter username : " username
    [ -z ${username} ] && prnt -e "Username empty, exit."  && exit 1
    read -s -p "Enter password : " password
    [ -z ${password} ] && prnt -e "Password empty, exit." && exit 1

    echo

    # user exists？
    egrep -w "^${username}" /etc/passwd >/dev/null
    if [ $? -eq 0 ]; then
        prnt -w "User ${username} exists, continue?(y/n)"
        read step1; [ "$step1" == y ] || exit 1
    else
        pass=$(perl -e 'print crypt($ARGV[0], "password")' ${password})
        useradd -m -p $pass $username
        if [ $? -eq 0 ]; then
            prnt -s "User ${username} has been added to system!"
        else
            prnt -e "Failed to add a user!"
            exit 1
        fi
    fi

    echo
    echo "1. Add user ${username} to wheel group, limit 'su' and set public key. "
    echo

    # add user to wheel
    groups ${username} | grep -w "wheel" &> /dev/null
    if [ $? -eq 0 ]; then
        prnt -w "User ${username} already in wheel group!"
    else
        usermod -G wheel ${username} 
        if [ $? -eq 0 ]; then
            prnt -s "Added user ${username} to wheel group"
        else
            prnt -e "Add ${username} to wheel group fail"
            exit 1
        fi
    fi

    # ban command su
    su_wheel_linenum=`grep -nE 'auth\s+required\s+pam_wheel.so\s+use_uid' /etc/pam.d/su | cut -d ":" -f 1`
    if [[ -z $su_wheel_linenum ]]; then
        echo "auth            required        pam_wheel.so use_uid" >> /etc/pam.d/su
    else
        sed -i "${su_wheel_linenum}c auth            required        pam_wheel.so use_uid" /etc/pam.d/su
    fi
    prnt -i "Banned command 'su' from all group except wheel."

    # if user exists now, set public key
    egrep "^$username" /etc/passwd >/dev/null
    if [ $? -eq 0 ]; then

        read -p "Enter user public key (default: mykey): " pubkey
        [ -z "$pubkey" ] && pubkey="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCaVoY7LKz1850eESViJbPnxT5GeZaRJ/ecQCyEmBNu+S+d1dlDq50m9rH6EuSMgDl4HvurxbzSYDhgofBUDky+RSXVlbChFBSzeX0v4Z6xbtnpWTlOmO+P68+u5GSOqNA1GjKL14shtgGauKYAQTlQfamJTXYMxwCVbMiTcVsPWUfpfiEEXwRxeEpqqgHuCcLsTaau8CHFJtdAk0t9QJFwgkYpxnoBYXvJEHTDmy3BgkLA6iDja0WGGmAycw1JYKT6G2wb+CZ0fvhCNFe7tnd2SoOBAgrwdO7iNTRl+bppa11Bzy910EazIhf9EetrplIWTgTe1wYegl9ytzJY7iUv"

       # pubkey login
        su &> /dev/null - ${username} <<sucode
if [ ! -d ~/.ssh ]; then
    mkdir ~/.ssh
fi
chmod 700 ~/.ssh
cd ~/.ssh
touch authorized_keys
echo ${pubkey} > authorized_keys
chmod 600 authorized_keys
sucode
        prnt -s "Set pubkey to [${username}] ~/.ssh/authorized_keys."


        echo
        echo "2. Set new ssh port"
        echo

        # get port 
        read -p "Enter port (default: 22): " newport
        [ -z "$newport" ] && newport=22

        # check if SElinux
        if command -v getenforce > /dev/null; then
            prnt -i "SElinux is installed."
            
            if [ `getenforce` == "Disabled"]; then
                prnt -i "SElinux is disabled"
            else
                setenforce 0
                [ $? -ne 0 ] && prnt -e "Close Selinux Fail, exit." && exit 1
            fi
            # # enforce selinux
            # if [ getenforce != Enforcing ]; then
            #     setenforce 1
            #     [ $? -ne 0 ] && prnt -e "Enforce Selinux Fail, exit." && exit 1
            # fi
            # prnt -i "SElinux is running."

            # # install selinux manager
            # if ! command -v semanage > /dev/null; then
            #     echo " Install SElinux manager. "
            #     yum -y install policycoreutils-python
            #     [ $? -ne 0 ] && prnt -e "Install Selinux manger fail, exit." && exit 1
            # fi
            # prnt -i "SElinux manager is installed."

            # #  add new port
            # if echo "(`semanage port -l | grep ssh_port_t`)[@]" | grep -w ${newport} &>/dev/null; then
            #     prnt -i "SElinux already open ssh port ${newport}${c_end}"
            # else
            #     semanage port -a -t ssh_port_t -p tcp $newport &> /dev/null
            #     if [ $? -eq 0 ];then
            #         prnt -i "SElinux add ssh port ${newport}"
            #     else
            #         prnt -e "SElinux add ssh port ${newport} fail"
            #         exit
            #     fi
            # fi
        fi

        # check if Firewall
        if command -v firewall-cmd > /dev/null; then
            prnt -i "Firewalld is installed."
            # run firewalld
            if [[ `firewall-cmd --state` != running ]]; then
                systemctl start firewalld
                if [[ `firewall-cmd --state` != running ]]; then
                    prnt -e "start Firewalld fail"
                    exit 1
                fi
            fi
            prnt -i "Firewalld is running"

            # check ssh service
            if echo "(`firewall-cmd --zone=public --list-services`)[@]" | grep -w ssh &>/dev/null; then
                prnt -w "Firewalld ssh sevice is added to public already."
            else
                firewall-cmd > /dev/null --permanent --zone=public --add-service=ssh
                if [ $? -eq 0 ];then
                    prnt -i "Firewalld add ssh service success"
                    firewall-cmd --reload
                else
                    prnt --e "Firewalld add ssh service fail"
                    exit
                fi        
            fi

            # check ssh port
            if echo "(`firewall-cmd --permanent --service=ssh --get-ports`)[@]" | grep -w ${newport}/tcp &>/dev/null; then
                prnt -w "Firewalld ${newport}/tcp is added to ssh service already."
            else
                firewall-cmd > /dev/null --permanent --service=ssh --add-port=${newport}/tcp
                if [ $? -eq 0 ];then
                    prnt -i "Firewalld add ${newport}/tcp success"
                    firewall-cmd --reload &> /dev/null 
                else
                    prnt -i "Firewalld add ${newport}/tcp fail"
                    exit
                fi    
            fi
        fi

 

        # set ssh login configs
        echo
        echo "3. Change sshd_config and restart shhd. "
        echo

        set_sshd Port $newport
        set_sshd PermitRootLogin no -y
        set_sshd PubkeyAuthentication yes -y
        set_sshd PasswordAuthentication no -y
        set_sshd AllowUsers ${username} -y

        echo
        prnt -i "SSHD status:"
        systemctl restart sshd
        systemctl status sshd

        echo
        echo "done!"
        echo
    else
        prnt -e "User not exists!"
        exit 1
    fi

else
    prnt -e "Only root may add a user to the system"
    exit 2
fi