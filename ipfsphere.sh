#!/bin/bash

# Author : Piotr Trybisz (ptrybisz at gmail com)
# Created On : 17.05.2023
# Last Modified By : Piotr Trybisz (ptrybisz at gmail dot com)
# Last Modified On : 17.05.2023
# Version : 0.1
#
# Description : decentralised chat using ipfs
#
#
# Licensed under GPL (see /usr/share/common-licenses/GPL for more details
# or contact the Free Software Foundation for a copy)

function version {
	#get md5sum of this file
	md5sum=$(md5sum $0 | cut -d' ' -f1)
	#get md5sum of this file from github
	local url="https://raw.githubusercontent.com/PetrusTryb/ipfsphere/main/ipfsphere.sh?$RANDOM"
	local github_md5sum=$(curl -H 'Cache-Control: no-cache' -s $url | md5sum | cut -d' ' -f1)
	if [ "$md5sum" == "$github_md5sum" ]; then
		dialog --msgbox "You are using the latest version ($md5sum)" 8 40
	else
		dialog --yesno "New version of IPFSphere is available. Do you want to update?" 8 40 2>/tmp/choice.tmp
		if [ $? -eq 0 ]; then
			#update
			curl -s $url > $0
			chmod +x $0
		fi
	fi
}

function help {
	echo "IPFSphere - decentralised chat using ipfs"
	echo "Usage: ipfsphere.sh [OPTION]"
	echo "Options:"
	echo "  -h	display this help and exit (you are here)"
	echo "  -v	display version info and install update if available"
	echo "  -r	reset ipfsphere (deletes all data, including messages and certificates)"
	echo "  -s	shutdown ipfsphere (stop ipfs daemon)"
	echo ""
	echo "Warning: this script is still in development, use at your own risk"
}

function init {
	ipfs version
	if [ $? -eq 0 ]; then
		echo "ipfs is already installed"
	else
		if [ $(id -u) -ne 0 ]; then
			dialog --msgbox "Dependencies not installed, please run this script as root." 8 40
			clear
			exit 1
		fi
		curl -O https://dist.ipfs.tech/kubo/v0.20.0/kubo_v0.20.0_linux-amd64.tar.gz
		tar xvfz kubo_v0.20.0_linux-amd64.tar.gz
		rm -f kubo_v0.20.0_linux-amd64.tar.gz
		sudo ./kubo/install.sh
		ipfs init
	fi
	if [ "$(ipfs name pubsub state)" == "enabled" ]; then
		echo "Daemon is already running"
	else
		ipfs config --json Experimental.PubsubEnabled true
		ipfs config --json Ipns.UsePubsub true
		ipfs config Pubsub.Router gossipsub
		ipfs config Ipns.RepublishPeriod 2m0s
		ipfs config Ipns.RecordLifetime 24h
		ipfs config Reprovider.Interval 2m0s
		ipfs config Reprovider.Strategy all
		ipfs config Routing.Type dhtclient
		ipfs config --json Experimental.FilestoreEnabled true
		# run ipfs daemon in background
		(ipfs daemon --enable-pubsub-experiment) >/dev/null 2>&1 &
		# wait for daemon to start
		dialog --infobox "Starting daemon, please wait..." 8 40
		sleep 5
	fi
}

function config {
	#check if nickname file exists
	if [ ! -f ~/.ipfsphere_nick ]; then
		dialog --inputbox "Enter nickname:" 8 40 2>/tmp/nickname.tmp
		if [ $? -eq 1 ]; then
			#exit
			clear
			exit 0
		fi
		#nick=user input + random number from 10000 to 99999
		local nickname=$(cat /tmp/nickname.tmp)#$(shuf -i 10000-99999 -n 1)
		local KeySym=IPFSphere$nickname
		# generate keypair
		ipfs key gen --type=rsa --size=4096 $KeySym
		dialog --infobox "Your nickname is $nickname" 8 40
		#export keys
		ipfs key export $KeySym --format=pem-pkcs8-cleartext -o privkey.pem
		if [ $? -ne 0 ]; then
			clear
			echo "Undefined keysym: $KeySym" >&2
			exit 1
		fi
		openssl pkey -in privkey.pem -pubout > pubkey.pem
		#save nickname
		echo $nickname > ~/.ipfsphere_nick
		#publish pubkey
		ipfs name publish --ipns-base=b58mh --key=$KeySym /ipfs/$(ipfs add pubkey.pem -Q)
	fi
}

function newTmpFile {
	local tmpFile
	tmpFile="$(mktemp -t ipfsphere.XXXXXX)"
	echo "${tmpFile}"
}

function mainwindow {
	#subscribe to all saved channels
	if [ ! -f ~/.ipfsphere_channels ]; then
		touch ~/.ipfsphere_channels
	fi
	for channel in $(cat ~/.ipfsphere_channels); do
		#check if not already subscribed
		ipfs pubsub ls | grep IPFSphere_channel_$channel > /dev/null
		if [ $? -eq 0 ]; then
			#already subscribed
			echo "already subscribed to $channel"
		else
			dialog --infobox "Subscribing to $channel" 8 40
			#subscribe
			$(ipfs pubsub sub IPFSphere_channel_$channel >>~/.ipfsphere_sub_$channel &)
			sleep 0.5
			$(refresh_service $channel) &
			request_resend $channel
		fi
	done
	while true; do
	options=()
	for channel in $(cat ~/.ipfsphere_channels); do
		options+=($channel "")
	done
	local dialog_title="$(cat ~/.ipfsphere_nick) @ IPFSphere"
	if [ ${#options[@]} -eq 0 ]; then
		gui_cmd=(dialog --title "$dialog_title" --extra-button --extra-label "Add new channel" --cancel-label "Exit" --menu "Select options:" 22 76 16 "No channels found" "")
	else
		gui_cmd=(dialog --title "$dialog_title" --extra-button --extra-label "Add new channel" --cancel-label "Exit" --menu "Select options:" 22 76 16 "${options[@]}")
	fi
	choices=$("${gui_cmd[@]}" 2>&1 >/dev/tty)
	if [ $? -eq 3 ]; then
		#add new channel
		addchannel
	elif [ $? -eq 1 ]; then
		if [ -z "$choices" ]; then
			#exit
			clear
			exit 0;
		elif [ "$choices" != "No channels found" ]; then
			#show channel
			channelwindow $choices
		fi
	fi
	done
}

function sign_message {
	local message=$1
	local signature
	signature=$(echo -n "$message" | openssl dgst -sha256 -sign privkey.pem | openssl enc -A -base64)
	echo "$signature" "$message"
}

function verify_message {
	local message=$1
	local signature=$2
	local pubkey_path=$3
	echo 0 #TODO: in future, verify signature
	#echo -n "$message" | openssl dgst -sha256 -verify "$pubkey_path" -signature <(echo "$signature" | openssl enc -A -base64 -d) >/dev/null 2>&1
}

function timestamp_to_date {
	local timestamp=$1
	if [ -z "$timestamp" ]; then
		timestamp=$(date +%s)
	fi
	date -d @$timestamp +%Y-%m-%d-%H:%M:%S
}

function date_to_timestamp {
	local date=$1
	date -d "$date" +%s
}

function process_channel_data {
	local ch=$1
	#check if channel file exists
	if [ ! -f ~/.ipfsphere_sub_$ch ]; then
		touch ~/.ipfsphere_sub_$ch
	fi
	if [ ! -f ~/.ipfsphere_parsed_$ch ]; then
		touch ~/.ipfsphere_parsed_$ch
	fi
	if [ ! -f ~/.ipfsphere_date_$ch ]; then
		touch ~/.ipfsphere_date_$ch
	fi
	while read line; do
		if [ -z "$line" ]; then
			continue
		fi
		#check if line is already processed
		local signature=$(echo "$line" | awk '{print $1}')
		local date=$(echo "$line" | awk '{print $2}')
		if [ -z "$signature" ]; then
			continue
		fi
		if [ "$signature" == "RESEND_REQUEST" ]; then
			local last_date=$(cat ~/.ipfsphere_date_$ch)
			if [ -z "$last_date" ]; then
				last_date="0"
			fi
			#check if resend request is not older than last
			if [ $last_date -lt $date ]; then
				handle_resend_request $ch
				echo $date > ~/.ipfsphere_date_$ch
			fi
			continue
		fi
		local nickname=$(echo "$line" | awk '{print $3}')
		#spaces from 4th column
		local message=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | sed 's/^ *//g')
		local human_date=$(timestamp_to_date $date)
		if [ -z "$nickname" ]; then
			continue
		fi
		if [ $(grep -c "$human_date" ~/.ipfsphere_parsed_$ch) -eq 0 ]; then
			#get user pubkey
			#ipfs name resolve IPFSphere#$nickname > /tmp/pubkey.tmp TODO: in future
			#check if message is signed
			if [ $(verify_message "$date $nickname $message" "$signature" "/tmp/pubkey.tmp") -eq 0 ]; then
				#add message to channel file
				echo "[$human_date] $nickname: $message" >> ~/.ipfsphere_parsed_$ch
			else
				echo "[$human_date] $nickname(?): $message" >> ~/.ipfsphere_parsed_$ch
			fi
		fi
	#only unique lines
	done < <(cat ~/.ipfsphere_sub_$ch | awk '!x[$0]++')
}

function refresh_service {
	while true; do
		sleep 3
		if [ "$(ipfs name pubsub state)" == "disabled" ]; then
			echo "123"
			exit 0
		fi
		for ch in $(cat ~/.ipfsphere_channels); do
			process_channel_data $ch
		done
	done
}

function request_resend {
	local channel=$1
	local request_date=$(date +%s)
	local request_data="RESEND_REQUEST $request_date"
	dialog --infobox "Requesting sync for: $channel" 3 50
	ipfs pubsub pub IPFSphere_channel_$channel <<< $request_data
}

function handle_resend_request {
	local channel=$1
	dialog --infobox "Syncing channel: $channel" 3 50
	#last week
	local date_from=$(date +%s -d "1 week ago")
	local tmp_file=$(newTmpFile)
	while read line; do
		#continue if contains resend request
		local signature=$(echo "$line" | awk '{print $1}')
		local date=$(echo "$line" | awk '{print $2}')
		if [ "$signature" == "RESEND_REQUEST" ]; then
			continue
		fi
		if [ "$date" == "RESEND_REQUEST" ]; then
			continue
		fi
		if [ -z "$date" ]; then
			continue
		elif [ -z "$signature" ]; then
			continue
		elif [ $date -ge $date_from ]; then
			echo "$line" >> $tmp_file
		fi
	done < <(cat ~/.ipfsphere_sub_$ch | awk '!x[$0]++')
	#dialog --tailbox $tmp_file 22 76
	ipfs pubsub pub IPFSphere_channel_$channel $tmp_file
	sleep 1
}

function channelwindow {
	local channel=$1
	process_channel_data $channel
	#show channel
	dialog --title "$channel" --colors --extra-button --extra-label "Write message" --ok-label "Back" --scrollbar --tailbox ~/.ipfsphere_parsed_$channel 22 76
	if [ $? -eq 3 ]; then
		#write message
		dialog --inputbox "Enter message:" 8 90 2>/tmp/message.tmp
		#message = [signature][date&time][nickname][message]
		message=$(sign_message "$(date +%s) $(cat ~/.ipfsphere_nick) $(cat /tmp/message.tmp)")
		if [ -z "$(cat /tmp/message.tmp)" ]; then
			channelwindow $channel
		else
			#publish message
			ipfs pubsub pub IPFSphere_channel_$channel <<< $message
			#show channel
			channelwindow $channel
		fi
	fi
}

function addchannel {
	dialog --inputbox "Enter channel name:" 8 40 2>/tmp/channelname.tmp
			channel=$(cat /tmp/channelname.tmp)
			#check if channel already exists
			if [ -z "$channel" ]; then
				sleep 0.1
			elif grep -Fxq "$channel" ~/.ipfsphere_channels; then
				dialog --msgbox "Channel already exists" 8 40
			else
				#add channel to list
				echo $channel >> ~/.ipfsphere_channels
				#subscribe to channel
				$(ipfs pubsub sub IPFSphere_channel_$channel >> ~/.ipfsphere_sub_$channel &)
				#start refresh service
				$(refresh_service $channel) &
				wait 0.5
				request_resend $channel
			fi
}

while getopts 'hvsr' OPTION; do
  case "$OPTION" in 
    h)
      help
	  exit 0
      ;;
    v)
      version
	  clear
	  exit 0
      ;;
	s)
		#find process that has ipfs in command and kill it
		ipfs shutdown
		for ch in $(cat ~/.ipfsphere_channels); do
			cat ~/.ipfsphere_sub_$ch | awk '!x[$0]++' > ~/.ipfsphere_sub_$ch.tmp
			mv ~/.ipfsphere_sub_$ch.tmp ~/.ipfsphere_sub_$ch
			echo "Compacted channel: $ch"
		done
		#kill all child processes but not this one
		kill $(ps aux | grep 'pubsub sub' | awk '{print $2}')
		sleep 3
		clear
		exit 0
		;;
	r)
		dialog --yesno "Are you sure you want to reset IPFSphere?" 8 40
		if [ $? -eq 0 ]; then
			clear
			key="IPFSphere$(cat ~/.ipfsphere_nick)"
			ipfs key rm $key > /dev/null 2>&1
			if [ $? -eq 0 ]; then
				echo "IPFSphere key removed"
			else
				echo "Undefined key: $key" >&2
			fi
			rm ~/.ipfsphere* > /dev/null 2>&1
			rm privkey.pem > /dev/null 2>&1
			rm pubkey.pem > /dev/null 2>&1
		else
			clear
			echo "IPFSphere reset aborted"
		fi
		exit 0
		;;
  esac
done

clear
init
config
mainwindow