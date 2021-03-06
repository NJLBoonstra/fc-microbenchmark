#!/bin/bash

#Enable job control
set -m

#Get the location of this script
myLocation=${0%${0##*/}}

kernelLocation="${1:?"Need first argument, kernel location"}"
fsLocation="${2:?"Need second argument, filesystem location"}"
writefsLocation="${myLocation}/../resources/writedisk.ext4"
fcID=${3:-1}
workLoad=${4:-"default"}
workLoadArg=${5:-"0"}
cpuCount=1
memSize=128
fcSock="/tmp/firecracker-$fcID.socket"
fcOutput="/tmp/firecracker-$fcID.output"

#Assert that 'time' always outputs 3-decimal precision
TIMEFORMAT="%3R"

#Import issue_commands
source $myLocation/commands.sh

check_file_exists $kernelLocation || exit_with_message "Cannot locate the kernel!" 1
check_file_exists $fsLocation ||exit_with_message "Cannot locate the filesystem!" 1

check_file_exists $writefsLocation || echo "Cannot locate the writedisk, some functions may not work!" 1>&2

#For debugging purposes
asDeamon=0
verbose=0
timeOutput=0

if [[ "$6" == "d" ]]; then
    #Run as daemon
    asDeamon=1
    verbose=0
elif [[ "$6" == "dv" ]]; then
    #Run as daemon put print to terminal
    asDeamon=1
    verbose=1
elif [[ "$6" == "c" ]]; then
    #Only issue commands (i.e. when other terminal waits for commands)
    #In this case, fcIDs of both terminals must match
    asDeamon=0
    verbose=1
    echo "Issueing commands only"
    issue_commands
    exit 0
elif [[ "$6" == "v" ]]; then
    #Do not daemonize and print to terminal
    #Used when parallelizing executions but VM outputs are needed
    asDeamon=0
    verbose=1
elif [[ "$6" == "t" ]]; then
    #Measure execution time of the microVM and return this value in ms
    #Print the execution time of the workload in the microVM to stdout
    asDeamon=0
    verbose=1
    timeOutput=1
fi

#Check firecracker installation
which firecracker > /dev/null

if [[ $? -eq 1 ]]; then
    echo "Firecracker not found, exiting..."
    exit 1
fi


rm -rf "$fcSock"

if [[ $timeOutput -ne 1 ]]; then
    echo "Launching Firecracker..."
fi

pidIssuer=0

if [[ $asDeamon -eq 0 ]]; then
    (
        # wait for the apisock to come up
        while [[ ! -e "$fcSock" ]]; do
            sleep 0.1s
        done
        issue_commands $verbose
    )&
    #Capture the pid of the command issuer
    pidIssuer=$!

    #Launch the firecracker instance and time its runtime
    if [[ $timeOutput -eq 1 ]]; then
        #Had to redirect firecracker output to null, as it sometimes throws a warning,
        #which messes up the processing of results
        fctime=$( { time (firecracker --api-sock "$fcSock" 2>/dev/null); } 2>&1 > $fcOutput  )
        #Remove the dot
        fctime=${fctime//./}
        echo "fc: $fctime"

        vmtime="$(cat $fcOutput | grep WORKLOADRUNTIME)"
        vmtime=${vmtime##* }
        echo "mVM: $vmtime"
        rm -rf $fcOutput
    else
        firecracker --api-sock "$fcSock"
    fi
elif [[ $asDeamon -ne 0 ]]; then
    firecracker --api-sock "$fcSock" &

    issue_commands $verbose
fi

rm -rf "$fcSock"

#if we get here, then fc is already terminated, either because it is actually 
#done, or it crashed. Either way, this script *must* terminate

if [[ $pidIssuer -ne 0 ]]; then
    #Suppress all output (will fail if the issuer did terminate as it should)
    kill -- -$pidIssuer > /dev/null 2> /dev/null
fi