#!/bin/bash
# Copyright (c) 2017, Medicine Yeh

SCRIPT_PATH="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")"
IMAGE_DIR="$SCRIPT_PATH/guest-images"
#Use PATH to automatically solve the binary path problem.
export PATH=$(pwd)/arm-softmmu/:$SCRIPT_PATH/../qemu-vpmu/build/arm-softmmu/:$PATH
export PATH=$(pwd)/x86_64-softmmu/:$SCRIPT_PATH/../qemu-vpmu/build/x86_64-softmmu/:$PATH
export PATH=$(pwd)/i386-softmmu/:$SCRIPT_PATH/../qemu-vpmu/build/i386-softmmu/:$PATH
export QEMU_ARM=qemu-system-arm
export QEMU_X86=qemu-system-x86_64
QEMU_ARGS=()

QEMU_ARGS+=(-m 1024)
QEMU_ARGS+=(--nographic)
# QEMU_ARGS+=(-vpmu-kernel-symbol $IMAGE_DIR/vmlinux)
# QEMU_ARGS+=(-drive if=sd,driver=raw,cache=writeback,file=$IMAGE_DIR/data.ext3)

# Debug traces
#QEMU_ARGS+=(-trace enable=true,events=/tmp/events-vfio)
#QEMU_ARGS+=(-mem-path /dev/hugepages)


function get_run_script() {
    local image_path="$1"
    # No path specified
    [[ -z "$image_path" ]] && return 1
    # If target is a file and also an executable, use it!!!!
    [[ -f "$image_path" ]] && [[ -x "$image_path" ]] && echo "$image_path" && return 0
    # If target is an file, set var to its directory instead
    [[ -f "$image_path" ]] && image_path="$(dirname "$image_path")"
    # If target is not a directory, return with fail
    [[ ! -d "$image_path" ]] && return 1
    # Everything has been checked to get to this step
    # $image_path is now set to an existing path of where image/runscript resides
    local run_script="${image_path}/runQEMU.sh"
    [[ -r "$run_script" ]] && echo "$run_script" && return 0
    # return 1 when the $run_script is not readable/existing
    return 1
}

function print_help() {
    echo "Usage:"
    echo "       $0 <IMAGE NAME> [OPTIONS]..."
    echo "  Execute QEMU with preset arguments for execution."
    echo ""
    echo "Options:"
    echo "       -net                : Enable networks"
    echo "       -g                  : Use gdb to run QEMU"
    echo "       -gg                 : Run QEMU with remote gdb mode to debug guest program"
    echo "                             Default port: 1234"
    echo "       -o <OUTPUT PATH>    : Specify the output 'directory' for emulation"
    echo "                             OUTPUT PATH is the path to a directory for logs and files."
    echo "                             default: /tmp/snippit"
    echo "       -vpmu-console <PATH>: Specify the output file for VPMU console output (default stderr)"
    echo ""
    echo "Options to QEMU:"
    echo "       -smp <N>            : Number of cores (default: 1)"
    echo "       -m <N>              : Size of memory (default: 1024)"
    echo "       -snapshot           : Read only guest image"
    echo "       -enable-kvm         : Enable KVM"
    echo "       -drive <PATH>       : Hook another disk image to guest"
    echo "       -mem-path <PATH>    : Use file to allocate guest memory"
    echo "                             ex: -mem-path /dev/hugepages"
    echo "       -trace <....>       : Use QEMU trace API with specified events"
    echo "                             ex: -trace enable=true,events=/tmp/events-vfio"
    echo ""
    echo "Image List:"
    local image_list=( $(cd "${IMAGE_DIR}" && find -type f -name "runQEMU.sh" | xargs dirname) )
    for img in "${image_list[@]}"; do
        echo "${img##*./}"
    done
}

function open_tap() {
    if [[ $(sudo -n ip 2>&1|grep "Usage"|wc -l) == 0 ]] \
        || [[ $(sudo -n brctl 2>&1|grep "Usage"|wc -l) == 0 ]]; then
        echo -e "\033[1;37m#You can add the following line into sudoer to save your time\033[0;00m"
        echo -e "\033[1;32m$(whoami) ALL=NOPASSWD: /usr/bin/ip, /usr/bin/brctl\033[0;00m"
    fi
    sudo ip tuntap add tap0 mode tap user $(whoami)
}

function generate_random_mac_addr() {
    if [ ! -f $SCRIPT_PATH/.macaddr ]; then
        printf -v macaddr \
            "52:54:%02x:%02x:%02x:%02x" \
            $(( $RANDOM & 0xff)) $(( $RANDOM & 0xff )) $(( $RANDOM & 0xff)) $(( $RANDOM & 0xff ))
        echo $macaddr > $SCRIPT_PATH/.macaddr
    fi
    MAC_ADDR=$(cat $SCRIPT_PATH/.macaddr)
}

while [[ "$1" != "" ]]; do
    # Parse arguments
    case "$1" in
        "-net" )
            generate_random_mac_addr
            open_tap
            #QEMU_ARGS+=(-net nic,model=virtio,macaddr=$MAC_ADDR -net tap,vlan=0,ifname=tap0)
            QEMU_ARGS+=(-netdev type=tap,id=net0,ifname=tap0,vhost=on)
            QEMU_ARGS+=(-device virtio-net-pci,netdev=net0,mac=$MAC_ADDR)
            shift 1
            ;;
        "-g" )
            # Disable file buffering to get the latest results from output
            # One could also use command 'call fflush({file descriptor})' in gdb
            export LD_PRELOAD=${SCRIPT_PATH}/nobuffering.so
            export SNIPPITS_GDB="gdb --args "
            shift 1
            ;;
        "-gg" )
            QEMU_ARGS+=(-S -gdb tcp::1234)
            shift 1
            ;;
        "-o" )
            QEMU_ARGS+=(-vpmu-output "$(readlink -f "$2")")
            shift 2
            ;;
        "-smp" )
            QEMU_ARGS+=(-smp $2)
            shift 2
            ;;
        "-m" )
            QEMU_ARGS+=(-m $2)
            shift 2
            ;;
        "-snapshot" )
            QEMU_ARGS+=(-snapshot)
            shift 1
            ;;
        "-enable-kvm" )
            QEMU_ARGS+=(-enable-kvm)
            shift 1
            ;;
        "-drive" )
            QEMU_ARGS+=(-drive if=sd,driver=raw,cache=writeback,file=$2)
            shift 2
            ;;
        "-vpmu-console" )
            QEMU_ARGS+=(-vpmu-console "$2")
            shift 2
            ;;
        "-mem-path" )
            QEMU_ARGS+=(-mem-path "$2")
            shift 2
            ;;
        "-trace" )
            QEMU_ARGS+=(-trace "$2")
            shift 2
            ;;
        "-h" )
            print_help
            exit 0
            ;;
        "--help" )
            print_help
            exit 0
            ;;
        * )
            image_path="$1"
            shift 1
            ;;
    esac
done

# No device/image name in options
[[ -z "$image_path" ]] && print_help && exit 1
# Try relative path first
QEMU=$(get_run_script "$image_path")
# Try absolute path
[[ -z "$QEMU" ]] && QEMU=$(get_run_script "${IMAGE_DIR}/${image_path}")
[[ -z "$QEMU" ]] && echo "Cannot find script runQEMU.sh in '$image_path'" && exit 1

# Execute QEMU
COLOR_GREEN='\033[1;32m'
NC='\033[0;00m'
echo -e "Running '${COLOR_GREEN}${QEMU} ${QEMU_ARGS[@]}${NC}'"
$QEMU "${QEMU_ARGS[@]}"

#Leave some time to clean up the forked processes
sleep 0.2
remaining_sims=$(ps -a | grep "cache-simulator" | wc -l)
if [ "$remaining_sims" != 0 ]; then
    echo "Cleaning remaining vpmu sims and reset terminal"
    sleep 1
    killall -9 cache-simulator
    #This would reset the terminal input echo policy
    reset
    echo "Terminal Rest"
fi

exit 0
