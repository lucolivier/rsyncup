#!/bin/bash
#-------------------------------------------------------------------------------------------------------
#	rsyncup
#					version : 	1.00ß06
#					modified : 	2016/09/29
#					created : 	2013/01/23
#					creator :	lucol
#-------------------------------------------------------------------------------------------------------
#	resources
#					rsynkups.conf
#-------------------------------------------------------------------------------------------------------
#	usage params
#					conf=<param-file>
#						To give and alternative conf file rather than default 'rsyncup.conf'
#						(in same folder)
#					filters=<param-file>
#						To give and alternative filters file rather than default 'rsyncup.exclusions'
#						(in same folder) or built-in when default not exist.
#-------------------------------------------------------------------------------------------------------
#					To launch as deamon "(path &) &" eg: "(./rsyncup &) &"
#-------------------------------------------------------------------------------------------------------

# debug levels are cumulative
#		>0	echo logEntry
#		>1	echo setParamValue
#		>2	void logFolder
#		>3	don't execute backup
debug=1

### Funcs
#
	function logEntry {
		#$1=str
		if [ $prmLog ]; then
			echo "$1" >>$prmLog ; [ $prmItemReportPath ] && echo "$1" >>$prmItemReportLog
																											[ $debug -gt 0 ] && echo "$1"
		else
			echo "$1"
		fi
	}

	function logEntryErr {
		#$1 str
		logEntry "$errFlag $1"
	}

	function logEntryExit {
		#$1=str
		logEntry "$errFlag $1 Exiting!"
		exit 1
	}

	function logEntry2 {
		# Deprecated: historycally needed for indented lines
		#$1=str
		logEntry "$1"
	}

	function logEntry2Err {
		#$1 str
		logEntry2 "$errFlag $1"
	}

	function logAddResult {
		#$1 std | err
		#$2=Log file to add
		local lineCtr
		if [ "$1" == 'std' ]; then
			cat "$2" | egrep -v '^$' >$prmTmpLog
		else
			cat "$2" | egrep -v '^$|from member names|des noms des membres|building file list' >$prmTmpLog
		fi
		lineCtr=$(cat "$prmTmpLog" | wc -l | sed 's/ //g')
		[ ! $lineCtr ] && lineCtr=0
		if [ $lineCtr -gt 0 ]; then
			if [ "$1" == 'std' ] || [ "$1" == 'stdtar' ]; then
				logEntry2 "---standard report---"
				if [ "$1" == 'std' ]; then
					tail -2 "$prmTmpLog" >>$prmLog
					[ $prmItemReportPath ] && tail -2 "$prmTmpLog" >>$prmItemReportLog
				fi
				logEntry2 ">See full log at $prmLog/$(basename $2)"
				logEntry2 ">$(echo "$lineCtr" | sed 's/ //g') result lines."
				cp -f "$2" "$(dirname $prmLog)/$(basename $2)"
				[ $prmItemReportPath ] && cp -f "$2" "$prmItemReportPath/$(basename $2)"
			fi
			if [ "$1" == 'err' ]; then
				let curErr=$curErr+$lineCtr
				let curSetErr=$curSetErr+$lineCtr
				logEntry2 "***errors report***" >>$prmLog
				cat "$prmTmpLog" >>$prmLog
				[ $prmItemReportPath ] && cat "$prmTmpLog" >>$prmItemReportLog
			fi
		fi
	}

	function logSetStorageStats_OLD {
		#$1 request to rsyncup-helper
		local data
		data=($(getHelperData $prmRsyncServer $prmHelperPort "$1"))
		if [ ! $data ] || [ ${data[0]} == 'ERR:' ]; then
			logEntry2 ". set storage: *** Statistic couldn't be retrieve ***"
			let curErr=$curErr+1
		else
			logEntry2 ". set storage: path ${data[1]} - size ${data[0]}"
		fi		
	}

	function logSetStorageStats {
		#$1=(all, levels =>based on defined level) #$2 (before,after)
		local prm_Address prm_HelperPort prm_Group prm_Path res stats stats_cmds stats_names i max
		stats_cmds=('vol' 'dir' 'path')
		stats_names=('Storage' 'Group Storage' 'Set Storage')

		if [ "$prmItemStorage" == 'remote' ] && [ $prmItemHelperPort ]; then
			prm_Address=$prmItemRsyncServer
			prm_Group=$prmItemRsyncServerGroup
			prm_Path=$prmItemStoragePath
			prm_HelperPort=$prmItemHelperPort
		elif [ "$prmItemStorage" == 'local' ]; then
			prm_Address='local'
			prm_Group='local'
			prm_Path=$prmItemStoragePath
			prm_HelperPort='local'
		fi

		if [ $prm_Address ]; then

			logEntry2 "$(initUpperCase $prmItemStorage) Stats: $2"

			for (( i=0 ; i<${#stats_cmds[*]} ; i++)); do

				[ "$prmItemStorage" == 'local' ] && [ "${stats_cmds[i]}" == 'dir' ] && continue
				
				[ $i -eq 0 ] && [ ! $prmItemStoreVolMax ] && continue
				[ $i -eq 1 ] && [ ! $prmItemStoreGroupMax ] && continue
				[ $i -eq 2 ] && [ ! $prmItemStoreSetMax ] && continue

				stats=($(getStats $prm_Address $prm_HelperPort ${stats_cmds[i]} $prm_Group $prm_Path))

				if [ $? -ne 0 ]; then
					logEntry2Err "${is}${stats_names[i]}: ${stats[*]}"
					let curSetErr=$curSetErr+1
				else
					if [ "${stats_cmds[i]}" == 'vol' ]; then
						if [ $prmItemStoreVolMax ]; then
							errStampOU1= ; errStampOU2=
							if [ "$(echo ${stats[4]} | sed 's/%//')" -gt $prmItemStoreVolMax ]; then
								errStampOU1='*** '
								errStampOU2=" <<<<<<<<<<< *** OVER USAGE OF ${prmItemStoreVolMax}% ***"
								let curSetErr=$curSetErr+1
							fi
						fi
						logEntry2 "${is}${errStampOU1}Storage $errStampOU2"
						logEntry2 "${is}partition ${stats[0]} - mount point ${stats[5]}"
						logEntry2 "${is}capacity ${stats[1]} - used ${stats[2]} - available ${stats[3]} - usage ${stats[4]}"
					else
						[ "${stats_cmds[i]}" == 'dir' ] && max=$prmItemStoreGroupMax || max=$prmItemStoreSetMax
						if [ $max ]; then
							errStampOU1= ; errStampOU2=
							if [ $(convertSize ${stats[0]}) -gt $(convertSize $max) ]; then
								errStampOU1='*** '
								errStampOU2=" <<<<<<<<<<< *** OVER MAX SIZE OF $max ***"
								let curErr=$curErr+1
							fi
						fi
						logEntry2 "${is}${errStampOU1}${stats_names[i]} $errStampOU2"
						logEntry2 "${is}Path ${stats[1]} - Size ${stats[0]}"
					fi
				fi
			done
		fi
	}

	function checkValue {
		#$1 value #$2 format
		local value vtest varr
		value="$1"
		case $2 in
			'num')			value=$(echo $value | sed 's/[^0-9]//g')
							;;
			'dec') 			value=$(echo $value | sed 's/[^0-9\.]//g')
							;;
			'wday')			value=$(echo $value | sed -e 's/[^0-9]//g')
							[ $value -lt 1 ] || [ $value -gt 7 ] && value=
							;;
			'mday')			value=$(echo $value | sed 's/[^0-9]//g')
							[ $value -lt 1 ] || [ $value -gt 31 ] && value=
							;;
			'size')			value=$(echo $value | sed -e 's/[^0-9MGT]//g' -e 's/^\([0-9]\{0,2\}\)[ ]\{0,100\}\([GMT]\).*/\1 \2/' )
							vtest=($(echo $value))
							[ ${#vtest[*]} -lt 2 ] && value= ; value=$(echo ${value[*]} | sed 's/ //g')
							;;
			'pcent')		value=$(echo $value | sed -e 's/[^0-9%]//g' -e 's/^\([0-9]\{0,2\}\).*/\1/')
							;;
			'path')			value=$(echo $value | sed -e 's/[^A-Za-z0-9\._\/-]//g' -e 's/\/$//g')
							;;
			'relpath')		value=$(echo $value | sed -e 's/[^A-Za-z0-9\._\/-]//g' -e 's/^\//g' -e 's/\/$//g')
							[ "$(echo $value | sed '/^\/$/!d')" ] && value=
							;;
			'abspath')		value=$(echo $value | sed -e 's/[^A-Za-z0-9\.\_\/-]//g' -e 's/\/$//g')
							[ ! "$(echo $value | sed '/^\//!d')" ] && value="/$value"
							[ "$(echo $value | sed '/^\/$/!d')" ] && value=
							;;
			'address')		value=$(echo $value | sed 's/[^A-Za-z0-9\.]//g')
							vtest=($(echo $value | sed 's/\./ /g'))
							[ ${#vtest[*]} -lt 1 ] && value=
							;;
			'alpha')		value=$(echo $value | sed 's/[^A-Za-z]//g') 
							;;
			'email')		value=$(echo $value | sed 's/[^A-Za-z0-9\._@-]//g')
							vtest=($(echo $value | sed 's/@/ /g'))
							[ ${#vtest[*]} -ne 2 ] && value=
							if [ $value ]; then
								vtest=($(echo ${vtest[1]} | sed 's/\./ /g'))
								[ ! ${#vtest[*]} -ge 2 ] && value=
							fi
							;;
			'emails')		value=$(echo $value | sed 's/[^A-Za-z0-9\._@-\,]//g')
							for email in $(echo $value | sed 's/\,/ /g'); do
								vtest=$(checkValue "$email" 'email')
								if [ "$vtest" == '' ]; then
									value=
									break
								fi
							done
							;;
			'cstr')			value=$(echo $value | sed 's/_/ /g')
							;;
			a[1-9])			vtest=($(echo $value | sed 's/:/ /g'))
							varr=$(echo $2 | sed 's/a//')
							[ ${#vtest[*]} -ne $varr ] && value=
							;;
			'freq')			vtest=$(echo $value | sed 's/[^DWMT:0-9]//g')
							[ ! "$value" == "$vtest" ] && value=
							if [ $value ]; then
								vtest=($(echo $value | sed 's/:/ /g'))
								[ ! $(echo ${vtest[0]} | sed '/^[DWMT]/!d') ] && value=
								if [ $value ] && [ ${vtest[1]} ]; then
									if [ "${vtest[0]}" == 'D' ] || [ "${vtest[0]}" == 'T' ]; then
										[ ${vtest[1]} ] && value=
									elif [ "${vtest[0]}" == 'W' ] || [ "${vtest[0]}" == 'M' ]; then
										varr=$(echo ${vtest[1]} | sed 's/[^0-9]//g')
										[ ! "${vtest[1]}" == "$varr" ] && value=
										if [ $value ]; then
											if [ "${vtest[0]}" == 'W' ]; then
												[ ! "$(checkValue ${vtest[1]} 'wday')" ] && value=
											elif [ "${vtest[0]}" == 'M' ]; then
												[ ! "$(checkValue ${vtest[1]} 'mday')" ] && value=
											fi
										fi
									else
										value=
									fi
								fi
							fi
							;;
			'method')		vtest=$(echo $value | sed 's/[^CNDBWMY:0-9]//g')
							[ ! "$value" == "$vtest" ] && value=
							if [ $value ]; then
								vtest=($(echo $value | sed 's/:/ /g'))
								[ ! $(echo ${vtest[0]} | sed '/^[CN]/!d') ] && value=
								if [ $value ] && [ ${vtest[1]} ]; then
									if [ "${vtest[0]}" == 'C' ]; then
										([ ! "${vtest[1]}" == 'Y' ] && [ ! "${vtest[1]}" == 'MY' ] && [ ! "${vtest[1]}" == 'WMY' ]) && value=
										[ ${vtest[2]} ] && value=
									elif [ "${vtest[0]}" == 'N' ]; then
										if [ "${vtest[1]}" == 'D' ]; then
											[ ${vtest[2]} ] && value=
										elif [ "${vtest[1]}" == 'B' ]; then
											varr=$(echo ${vtest[2]} | sed 's/[^0-9]//g')
											[ ! "${vtest[2]}" == "$varr" ] && value=
										else
											value=
										fi
									else
										value=
									fi
									varr=$(echo ${vtest[2]} | sed 's/[^0-9]//g')
									[ ! "${vtest[2]}" == "$varr" ] && value=
								fi
							fi
							;;
			'free')			;;
			*)				logEntryExit "$1 - Unknown format ($2)."
							;;
		esac
		echo "$value"
	}

	function getArrayValueByKey {
		#$1 val name $2 val key [$3 separator]
		local array item sep
		sep=':'
		[ $3 ] && sep=$3
		array=($(eval echo \${$1[*]}))
		for item in ${array[*]}; do
			if [ $(echo $item | sed "/^$2$sep/!d" ) ]; then
				if [ $(echo $1 | sed '/^val/!d') ]; then
					echo $item | sed -e "s/.*$sep//" -e 's/_/ /g'
				else
					echo $item | sed -e "s/.*$sep//" # because of paths which may contain '_'
				fi
				return 0
			fi
		done
		#echo 'Not exists!'
		return 1
	}

	function setParam {
		#$1 global|backupset #$2 key #$3 value|conf #$4 format [#$5 is optional]
		local valueO valueF res prefix array
		if [ "$1" == 'global' ]; then
			prefix='prm' ; array='prms'
		else
			prefix='prmItem' ; array='prmsBS'
		fi
		res=0
		valueO="$3"
		if [ "$3" == 'conf' ]; then
			valueO="$(getArrayValueByKey $array $2 '|')"
			#if [ "$valueO" == 'Not exists!' ]; then
			if [ $? -ne 0 ]; then
				if [ ! $5 ]; then
					if [ "$1" == 'global' ]; then
						logEntryExit "'$2' param not set in $(basename $prmFile) file."
					else
						logEntry2Err "'$2' param not set in for BackupSet in $(basename $prmFile) file."
						let curSetParamErr+=1
																											[ $debug -gt 2 ] && echo "BS Processing errors=$curSetParamErr"
					fi
				fi
				valueF=
				res=1
			fi
		fi
		if [ $res -ne 1 ]; then
			valueF=$(checkValue "$valueO" $4)
			if [ "$valueF" == '' ] || [ "$valueF" == '-' ]; then
				if [ "$1" == 'global' ]; then
					mess="'$2' param ($valueO) wrong in Global of $(basename $prmFile) file."
				else
					mess="'$2' param ($valueO) wrong in BackupSet of $(basename $prmFile) file."
				fi
				if [ ! $5 ] || ([ $valueO ] && [ ! "$valueO" == '-' ]); then
					[ "$1" == 'global' ] && logEntryExit "$mess"
					logEntry2Err "$mess"
					res=1
				elif [ ! "$valueO" == '-' ]; then
					[ "$1" == 'global' ] && logEntryErr "$mess" || logEntry2Err "$mess"
					res=1
				fi
				if [ "$1" == 'backupset' ] && [ $res -eq 1 ]; then
					let curSetParamErr+=1
																											[ $debug -gt 2 ] && echo "BS Processing errors=$curSetParamErr"
				fi
			fi
		fi
		eval "$prefix$2='$valueF'"
																											[ $debug -gt 1 ] && echo "$prefix$2=$valueF"
		return $res
	}

	function setGlobalParam {
		#$1 key #$2 value | conf #$3 format [#$4 is optional]
		setParam global $1 $2 $3 $4
		return $?
	}
	
	function setBackupSetParam {
		#$1 key #$2 value | conf #$3 format [#$4 is optional]
		local value valueS valueF res

		if [ "$(echo $1 | egrep 'Server|HelperPort|StoragePath|StoreVolMax|StoreGroupMax')" ] && [ "$2" == 'conf' ]; then
			value="$(getArrayValueByKey prmsBS $1 '|')"

			if [ "$(echo $value | sed '/^global/!d')" ]; then
				valueS=$value ; value=
				case $1 in
					Server)
						if [ "$prmGlobalStorage" == 'remote' ]; then
							prmItemStorage='remote'
							prmItemRsyncServer=$prmGlobalStorageAddress
							prmItemRsyncServerPort=$prmGlobalStoragePort
							prmItemRsyncServerGroup=$prmGlobalStorageGroup
							prmItemStoragePath=$prmGlobalStoragePath
							value="$prmItemRsyncServer:$prmItemRsyncServerPort:$prmItemRsyncServerGroup"
							prmItemServer='global'
                        elif [ "$prmGlobalStorage" == 'local' ]; then
                            prmItemStoragePath=$prmGlobalStoragePath
                            value=$prmGlobalStoragePath
                            prmItemServer='global'
						fi ;;
					HelperPort)
						if [ $prmGlobalHelperPort ]; then
							prmItemHelperPort=$prmGlobalHelperPort
							value=$prmItemHelperPort
						fi ;;
					StoragePath)
						prmItemStoragePath=$prmGlobalStoragePath
						if [ ! "$valueS" == 'global' ]; then
							prmItemStoragePath=${prmItemStoragePath}$(echo $valueS | sed 's/^global//')
							valueF=$(checkValue "$prmItemStoragePath" 'path')
							[ $valueF ] && value=$valueF
						else
							value=$prmItemStoragePath
						fi ;;
					StoreVolMax)
						if [ $prmGlobalStoreVolMax ]; then
							prmItemStoreVolMax=$prmGlobalStoreVolMax
							value=$prmItemStoreVolMax
						fi ;;
					StoreGroupMax)
						if [ $prmStoreGroupMax ]; then
							prmItemStoreGroupMax=$prmGlobalStoreGroupMax
							value=$prmItemStoreGroupMax
						fi ;;
				esac
				if [ ! $value ]; then
					logEntry2Err "'$1' required as global but global not set"
					let curSetParamErr+=1
																											[ $debug -gt 2 ] && echo "BS Processing errors=$curSetParamErr"
					return 1
				else
																											[ $debug -gt 1 ] && echo "prmItem$1=$value"
				fi
				return 0
			else
				setParam backupset $1 $2 $3 $4
				return $?
			fi
		else
			setParam backupset $1 $2 $3 $4
			return $?
		fi
	}

	function getMyRunTime {
		if [ "$curOS" == 'Darwin' ]; then
			echo 'Not Supported for now'
		else
			cat /etc/crontab | sed -e "/$my/!d" -e 's/\([0-9*]*\) \([0-9*]*\).*/\1:\2/'
		fi
	}
	
	function getMyVersion {
		cat $0 | sed -e '/^#.*version :/!d' -e 's/[ \x09]//g' -e 's/.*://'
	}

	function getHelperData {
		#$1 adddress #$2 port #$3 helper command
		local value err
		exec 3<>/dev/tcp/$1/$2
		err=$? ; if [ $err -ne 0 ]; then
			echo "ERR: Problem while connecting (error:$err)."
			exec 3<&- ; exec 3<&- ; return 1
		fi
		echo -e "$3\n" >&3
		read -t 120 value <&3
		err=$? ; if [ $err -ne 0 ]; then
			echo "ERR: Problem while getting response (error:$err)."
			exec 3<&- ; exec 3<&- ; return 1
		fi
		echo -e "quit\n" >&3
		exec 3<&- ; exec 3<&-
		if [ "$value" == '' ]; then
			echo "ERR: Helper return void result." ; return 1
		fi
		echo "$value"
		return 0
	}

	function getStats {
		#$1 target address or local
		#$2 helper port or local
		#$3 stat command (vol|dir|pat,path)
		#$4 group name or local
		#$5 abs or rel path according to remote or local
		local cmd result res err
		err=0
		if [ "$1" == 'local' ]; then
			if [ -d $5 ]; then
				case $3 in
					vol)
						res=($(df -h $5 | tail -1))
						if [ "$curOS" == 'Darwin' ]; then
							result=($(echo "${res[0]} ${res[1]} ${res[2]} ${res[3]} ${res[4]} ${res[8]}" \
							| sed 's/\([KMGT]\). /\1 /g'))
						else
							result=(${res[*]})
						fi
						;;
					dir|pat|path)
						result=($(du -sh $5))
						;;
					*)
						result=('ERR:' "Wrong Stat Command ($3).") ; err=1
						;;
				esac
			else
				result=('ERR:' 'Path does not exist.') ; err=1
			fi
		else
			if [ ! "$2" == 'local' ]; then
				case $3 in
					vol|'dir')	cmd="$3:$4"		;;
					pat|'path')	cmd="$3:$4/$5"	;;
					*)			result=('ERR:' "Wrong Helper Command ($3)") ; err=1 ;;
				esac
				if [ $cmd ]; then
					result=($(getHelperData $1 $2 $cmd))
					err=$?
				fi
			else
				result=('ERR:' 'No Remote Helper defined.') ; err=1
			fi
		fi
		echo "${result[*]}"
		return $err
	}

	function transfertLines {
		#$1 file1 #$2 file2 #$3 regex
		cat "$1" | sed "/$3/!d" >$2
		cp -pf "$1" "${1}.bkp"
		cat "${1}.bkp" | sed '/^a /d' >$1
		rm -f "${1}.bkp"		
	}

	function convertSize {
		#$1 size expressed as ####K|M|G|T
		local finalSize
		finalSize=$(echo $1 | sed 's/B$//')
		finalSize=$(echo $finalSize | sed 's/K$/000/')
		finalSize=$(echo $finalSize | sed 's/M$/000000/')
		finalSize=$(echo $finalSize | sed 's/G$/000000000/')
		finalSize=$(echo $finalSize | sed 's/T$/000000000000/')
		echo $finalSize
	}

	function upperCase {
		#$1 str
		echo $1 | sed 'y/abcdefghijklmnopqrstuvyz/ABCDEFGHIJKLMNOPQRSTUVYZ/'
	}

	function initUpperCase {
		#$1 str
		echo $1 | sed "s/^.\(.*\)/$(upperCase $(echo $1 | sed 's/^\(.\).*/\1/'))\1/"
	}

### Process Params file
#

	#1# Set Internal values
	#
																											[ $debug -gt 4 ] && echo "1# Set Internal values"
	valMethods=(
					C:Archives_no_deletion
					CWMY:Archives_WMY
					CMY:Archives_MY
					CY:Archives_Y
					N:Nested_no_deletion
					NB:Nested+backup
					ND:Nested+deletion
				)
	valFreqs=( D:Daily W:Weekly M:Mounthly T:Trigger )
	valDays=( 1:Monday 2:Tuesday 3:Wednesday 4:Thursday 5:Friday 6:Saturday 7:Sunday )
	cutChar=';'
	my="$(basename $0)"
	errFlag='*** Error:'


	#2# Get current OS
	#
																											[ $debug -gt 4 ] && echo "2# Get current OS"
	curOS=$(uname -srv | sed 's/ .*//')


	#3# Check command line params
	#
                                                                                                            [ $debug -gt 4 ] && echo "3# Check command line params"
    param= ; prmTemp=
	if [ $# -ne 0 ]; then
		for (( i=1 ; i<=$# ; i++ )); do
			eval param=\$$i
			param=($(echo $param | sed 's/=/ /'))
			#echo ${param[*]}
			if [ ${#param[*]} -ne 2 ]; then
				logEntryExit "wrong param: ${param[*]}."
			fi
			case ${param[0]} in
				conf|filters)
					if [ $(echo "${param[1]}" | sed '/^\.\//!d') ]; then
						prmTemp="$(dirname $0)/${param[1]}"
					elif [ $(echo "${param[1]}" | sed '/\//!d') ]; then
						prmTemp="${param[1]}"
					else
						prmTemp="$(dirname $0)/${param[1]}"
					fi
					if [ "${param[0]}" == 'conf' ]; then
						prmFile=$prmTemp
					else
						prmFiltersFile=$prmTemp
					fi
					;;
				*)
					logEntryExit "unknown param: ${param[0]}."
			esac
		done
	fi
	param= ; prmTemp=


	#4# Check params file
	#
                                                                                                            [ $debug -gt 4 ] && echo "4# Check params file"
	[ ! $prmFile ] && prmFile="$(dirname $0)/$my.conf"
	if [ ! -f "$prmFile" ]; then
		logEntryExit "$my.conf is missing."
	fi


	#5# Process env parameters
	#
                                                                                                            [ $debug -gt 4 ] && echo "5# Process env parameters"
	prms=($(cat "$prmFile" | sed -n '1,/BackupSet[ ]\{0,100\}(/'p					\
					 	   | sed -e 's/#.*//'										\
								 -e '/[	 ]\{0,100\}#/d' 							\
								 -e 's/^[	 ]\{1,100\}//g'							\
								 -e 's/[	]\{1,100\}/ /g'							\
								 -e '/^$/d'											\
								 -e 's/\([A-Za-z0-9-]*\)[ ]\{1,100\}\(.*\)/\1|\2/g'	\
								 -e 's/ //g'										\
								 -e "s/'//g"										\
								 -e 's/"//g'										\
								 -e 's/::/:-:/g' 									\
								 -e 's/|:/|-:/g'									\
								 -e 's/:$/:-/g'										\
								 -e "s/$cutChar/,/g"))
																											#echo ${prms[*]}

	#6# Check for duplicate param
	#
                                                                                                            [ $debug -gt 4 ] && echo "6# Check for duplicate param"
	prmsItemR= ; prmsItemT=
	for (( i=0 ; i<(${#prms[*]}-1) ; i++ )); do
		prmsItemR=$(echo "${prms[i]}" | sed 's/|.*//')
		for (( j=i+1 ; j<${#prms[*]} ; j++ )); do
			if [ "$prmsItemR" == $(echo "${prms[j]}" | sed 's/|.*//') ]; then
				logEntryExit "Duplicate param found '$prmsItemR'."
				break 2
			fi
		done
	done
	prmsItemR= ; prmsItemT=


	#7# Extract params
	#
                                                                                                            [ $debug -gt 4 ] && echo "7# Extract params"
	setGlobalParam BackupWeekDay 'conf' 'wday'
	prmBackupWeekDay=$(echo $prmBackupWeekDay | sed 's/[0-9]\{0,100\}\([0-9]\)$/\1/')

	setGlobalParam BackupMonthDay 'conf' 'mday'
	prmBackupMonthDay=$(echo "0${prmBackupMonthDay}" | sed 's/[0-9]\{0,100\}\([0-9]\{2\}\)$/\1/')

	setGlobalParam BackupSemFileName 'conf' 'free'
	setGlobalParam TempFolder 'conf' 'abspath'
	prmTempFolder="$prmTempFolder/$my"
	
	setGlobalParam RsyncServer 'conf' 'a3' optional
	if [ $prmRsyncServer ]; then
		prmItemSub=($(echo $prmRsyncServer | sed 's/:/ /g'))
		setGlobalParam RsyncServer ${prmItemSub[0]} 'address' optional
		setGlobalParam RsyncServerPort ${prmItemSub[1]} 'num' optional
		[ ! $prmRsyncServerPort ] && prmRsyncServerPort='873'
		setGlobalParam RsyncServerGroup ${prmItemSub[2]} 'alpha' optional
	fi
	
	setGlobalParam HelperPort 'conf' 'num'	optional
	setGlobalParam StoragePath 'conf' 'path' optional

	setGlobalParam LogPathFolder 'conf' 'abspath'
	prmLogPathFolder="$prmLogPathFolder/$my"
		
	[ ! "$curOS" == 'Darwin' ] && setGlobalParam MailFromReport 'conf' 'email' optional
	setGlobalParam MailToReport 'conf' 'emails' optional
    prmGlobalMailOff='optional' ; [ $prmMailToReport ] && prmGlobalMailOff=
	setGlobalParam MailSubjectReport 'conf' 'cstr' $prmGlobalMailOff

	setGlobalParam StoreVolMax 'conf' 'pcent' optional
	setGlobalParam StoreGroupMax 'conf' 'size' optional

	prms= ; prmItem= ; prmItemSub=


	#8# Process backup sets
	#																										#echo ; echo ; echo
                                                                                                            [ $debug -gt 4 ] && echo "8# Process backup sets"
	prmsBSs=($(cat "$prmFile" | sed -e 's/#.*//'											\
									 -e '/[	 ]\{0,100\}#/d' 								\
				 					 -e '/BackupSet[ ]\{0,100\}(/,/)/!d'					\
									 -e 's/^[	 ]\{1,100\}//g'								\
									 -e 's/[	]\{1,100\}/ /g'								\
									 -e '/^$/d'												\
									 -e '/^BackupSet/d'										\
									 -e 's/|/,/g'											\
									 -e 's/\([A-Za-z0-9-]*\)[ ]\{1,100\}\(.*\)/\1|\2/g'		\
									 -e 's/ //g'											\
									 -e "s/'//g"											\
									 -e 's/"//g'											\
									 -e 's/::/:-:/g' 										\
									 -e 's/|:/|-:/g'										\
									 -e 's/:$/:-/g'											\
									 -e "s/$cutChar/,/g"									\
									 | tr '\n' "$cutChar" | tr ')' '\n'						\
									 | sed -e "s/^$cutChar//g" -e "s/$cutChar$//g" ))
																											#echo ">${prmsBSs[*]}<" ; echo ; echo ${#prmsBSs[*]} ; echo
																											#for (( i=0 ; i<${#prmsBSs[*]} ; i++ )); do ; echo ">${prmsBSs[i]}" ; done


	#9# Process eMail template file
	#
                                                                                                            [ $debug -gt 4 ] && echo "9# Process eMail template file"
	prmEmailTmpl="$(dirname $0)/$my.emailtmpl"
	[ ! -f "$prmEmailTmpl" ] && prmEmailTmpl=

### Open session log
#

	#10# Set Log
	#
                                                                                                            [ $debug -gt 4 ] && echo "10# Set Log"
	mkdir -p $prmLogPathFolder
	if [ ! -d $prmLogPathFolder ]; then
		logEntryExit "Unable to create log folder ($prmLogPathFolder)."
	fi
																											[ $debug -gt 2 ] && rm -rf $prmLogPathFolder/*
	ts=$(date '+%y%m%d-%H%M%S')
	prmLog="$prmLogPathFolder/${ts}"
	prmTmpLog="${prmTempFolder}/${ts}_tmp"
	rptDashedLine='---------------------------------------------------------'
	
	logEntry $rptDashedLine
																											[ $debug -gt 0 ] && logEntry "DEBUGLEVEL: $debug"
	logEntry "LogPathFolder: $prmLogPathFolder"
	logEntry "BackupWeekDay: $prmBackupWeekDay"
	logEntry "BackupMonthDay: $prmBackupMonthDay"
	logEntry "BackupSemFileName: $prmBackupSemFileName"
	logEntry "TempFolder: $prmTempFolder"
	logEntry "RsyncServer: $prmRsyncServer"
	logEntry "RsyncServerPort: $prmRsyncServerPort"
	logEntry "RsyncServerGroup: $prmRsyncServerGroup"
	logEntry "HelperPort: $prmHelperPort"
	logEntry "StoragePath: $prmStoragePath"
	logEntry "StoreVolMax: ${prmStoreVolMax} %"
	logEntry "StoreGroupMax: $prmStoreGroupMax"
	[ ! "$curOS" == 'Darwin' ] && logEntry "MailFromReport: $prmMailFromReport"
	logEntry "MailToReport: $prmMailToReport"
	logEntry "MailSubjectReport: $prmMailSubjectReport"

### Setup execution environment
#

	#11# Set Src Env
	#
                                                                                                            [ $debug -gt 4 ] && echo "11# Set Src Env"
	mkdir -p $prmTempFolder
	[ ! -d $prmTempFolder ] && logEntryExit "Unable to create temp folder ($prmTempFolder)."
	rm -rf $prmTempFolder/*


	#12# Process exclusions file
	#
                                                                                                            [ $debug -gt 4 ] && echo "12# Process exclusions file"
	[ ! $prmFiltersFile ] && prmFiltersFile="$(dirname $0)/$my.exclusions"
	if [ -f "$prmFiltersFile" ]; then
		prmFiltersFile="--exclude-from=$prmFiltersFile"
	else
		prmFiltersFile="$prmTempFolder/${my}.exclusions"
		echo ".apdisk" >$prmFiltersFile
		echo ".DS_Store" >>$prmFiltersFile
		echo ".CFUserTextEncoding" >>$prmFiltersFile
		echo ".TemporaryItems" >>$prmFiltersFile
		echo ".Trashes" >>$prmFiltersFile
		echo ".fseventsd" >>$prmFiltersFile
		echo ".DocumentRevisions-V100" >>$prmFiltersFile
		echo ".Spotlight-V100" >>$prmFiltersFile
		echo ".Trash" >>$prmFiltersFile
		echo "._*" >>$prmFiltersFile
		prmFiltersFile="--exclude-from=$prmFiltersFile"
	fi


	#13# Set Current moment
	#
                                                                                                            [ $debug -gt 4 ] && echo "13# Set Current moment"
	curWoDay=$(date '+%u')
	curDay=$(date '+%d')


	#14# Set error counters and so on
	#
                                                                                                            [ $debug -gt 4 ] && echo "14# Set error counters and so on"
	curErr=0 ; curSetErr=0 ; curSetParamErr=0
	errStamp=
	is='. '


	#15# Set mail complementary params
	#
                                                                                                            [ $debug -gt 4 ] && echo "15# Set mail complementary params"
	rptMailParams=
	[ $prmMailFromReport ] && rptMailParams="-r $prmMailFromReport"


##16# Check global params reliability and BUILD GLOBAL SYMBOL
#
                                                                                                            [ $debug -gt 4 ] && echo "16# Check global params reliability and BUILD GLOBAL SYMBOL"
	if [ "${prmRsyncServer}${prmRsyncServerGroup}" ]; then
		if [ ! $prmRsyncServer ] || [ ! $prmRsyncServerGroup ]; then
			logEntryExit "Missing param for remote backup (RsyncServer: ${prmRsyncServer}:$prmRsyncServerPort:${prmRsyncServerGroup})."
		fi
		if [ "$(echo $prmStoragePath | sed '/^\//!d')" ]; then
			logEntryExit "Storage Path must be relative for remote backup."
		fi
		prmGlobalStorage='remote'
		prmGlobalStorageAddress=$prmRsyncServer
		prmGlobalStoragePort=$prmRsyncServerPort
		prmGlobalStorageGroup=$prmRsyncServerGroup
		prmGlobalStoragePath=$prmStoragePath
		prmGlobalHelperPort=$prmHelperPort
	elif [ $prmStoragePath ]; then
		if [ ! "$(echo $prmStoragePath | sed '/^\//!d')" ]; then
			logEntryExit "Storage Path must be absolute for local backup."
		fi
		prmGlobalStorage='local'
		prmGlobalStorageAddress='local'
		prmGlobalStoragePort=
		prmGlobalStorageGroup='local'
		prmGlobalStoragePath=$prmStoragePath
		prmGlobalHelperPort='local'
	else
		prmGlobalStorage= ### < for memo ! Not set if global not defined (neither remote nor local).
		[ $prmHelperPort ] && prmGlobalHelperPort=$prmHelperPort #<< because HelperPort may be set as symbol
	fi

	[ $prmStoreVolMax ] && prmGlobalStoreVolMax=$prmStoreVolMax
	[ $prmStoreGroupMax ] && prmGlobalStoreGroupMax=$prmStoreGroupMax


##17# Storage stats
#
                                                                                                            [ $debug -gt 4 ] && echo "17# Storage stats"
	if ([ "$prmGlobalStorage" == 'remote' ] && [ $prmGlobalHelperPort ]) || [ "$prmGlobalStorage" == 'local' ]; then
		logEntry $rptDashedLine
		kstore=$(initUpperCase $prmGlobalStorage)
		
		stats=($(getStats $prmGlobalStorageAddress $prmGlobalHelperPort vol $prmGlobalStorageGroup $prmGlobalStoragePath))
		if [ $? -ne 0 ]; then
			logEntryErr "$kstore Storage: ${stats[*]}"
			let curErr=$curErr+1
		else
			if [ $prmStoreVolMax ]; then
				errStampOU1= ; errStampOU2=
				if [ "$(echo ${stats[4]} | sed 's/%//')" -gt $prmStoreVolMax ]; then
					errStampOU1='*** '
					errStampOU2=" <<<<<<<<<<< *** OVER USAGE OF ${prmStoreVolMax}% ***"
					let curErr=$curErr+1
				fi
			fi
			logEntry "${errStampOU1}$kstore Storage $errStampOU2"
			logEntry2 "${is}partition ${stats[0]} - mount point ${stats[5]}"
			logEntry2 "${is}capacity ${stats[1]} - used ${stats[2]} - available ${stats[3]} - usage ${stats[4]}"
		fi

		stats=($(getStats $prmGlobalStorageAddress $prmGlobalHelperPort dir $prmGlobalStorageGroup $prmGlobalStoragePath))
		if [ $? -ne 0 ]; then
			logEntry "$prmGlobalStorage Group Storage: ${stats[*]}"
			let curErr=$curErr+1
		else
			if [ $prmStoreGroupMax ]; then
				errStampOU1= ; errStampOU2=
				if [ $(convertSize ${stats[0]}) -gt $(convertSize $prmStoreGroupMax) ]; then
					errStampOU1='*** '
					errStampOU2=" <<<<<<<<<<< *** OVER MAX SIZE OF ${prmStoreGroupMax} ***"
					let curErr=$curErr+1
				fi
			fi
			logEntry "${errStampOU1}$kstore Group Storage $errStampOU2"
			logEntry2 "${is}Path ${stats[1]} - Size ${stats[0]}"
		fi		
	fi


##18# Check for still running rsyncup process
#
                                                                                                            [ $debug -gt 4 ] && echo "18# Check for still running rsyncup process"
	if [ -f /var/run/$my.pid ]; then
		pidNbr=$(cat "/var/run/$my.pid")
		if [ "$(ps ax | sed -e "s/^ *//g" -e "/^$pidNbr/!d" -e '/sed/d')" ]; then
			logEntryExit "An other instance is still running."
		fi
	fi
	echo $$ >/var/run/$my.pid


##19# Last Presets
#
                                                                                                            [ $debug -gt 4 ] && echo "19# Last Presets"
	prmRsyncSuffix='______bkp'
	prmBSNames=() #keep tack for pervent duplicate backupset

###
### Main
###
	echo $rptDashedLine >>$prmLog
																											[ $debug -gt 0 ] && echo $rptDashedLine

	if [ ${#prmsBSs[*]} -eq 0 ]; then
		logEntryErr "$errFlag not backup set to process!"
		curErr=1
	else
		logEntry "${#prmsBSs[*]} BackupSets to process!"
																											[ $debug -gt 1 ] && for prmItem in ${prmsBSs[*]}; do echo $prmItem ; echo ; done
	fi

	for (( iPrms=0 ; iPrms<${#prmsBSs[*]} ; iPrms++ )); do
                                                                                                            [ $debug -gt 4 ] && echo "100# Main loop"
		prmItemStorage=

		echo $rptDashedLine >>$prmLog
																											[ $debug -gt 0 ] && echo $rptDashedLine

		prmsBS=($(echo ${prmsBSs[iPrms]} | sed "s/$cutChar/ /g"))

		curSetParamErr=0
		rptDate=$(date '+%d-%m-%y') ; rptTime=$(date '+%H:%M:%S')
		logEntry2 "#$(( $iPrms+1 )) - $rptTime"


	#101# Check for duplicate param
	#
                                                                                                            [ $debug -gt 4 ] && echo "101# Check for duplicate param"
		prmItemR= ; prmItemT=
		for (( i=0 ; i<(${#prmsBS[*]}-1) ; i++ )); do
			prmItemR=$(echo "${prmsBS[i]}" | sed 's/|.*//')
			for (( j=i+1 ; j<${#prmsBS[*]} ; j++ )); do
				if [ "$prmItemR" == $(echo "${prmsBS[j]}" | sed 's/|.*//') ]; then
					logEntry2Err "Duplicate param found '$prmItemR'."
					let curSetParamErr+=1
					break 2
				fi
			done
		done
		prmItemR= ; prmItemT=


	#102# Extract params
	#
                                                                                                            [ $debug -gt 4 ] && echo "102# Extract params"
		setBackupSetParam Files 'conf' 'abspath' optional

		setBackupSetParam Name 'conf' 'free' optional
		if [ ! $prmItemName ] && [ $prmItemFiles ]; then
			prmItemName=$(upperCase $(basename $prmItemFiles))
		fi
		i= ; while test 1; do
			for (( j=0 ; j<${#prmBSNames[*]} ; j++ )); do
				if [ "${prmItemName}$i" == "${prmBSNames[j]}" ]; then
					(( i++ ))
					continue 2
				fi
			done
			prmItemName=${prmItemName}$i
			prmBSNames=(${prmBSNames[*]} $prmItemName)
			break
		done

		setBackupSetParam DB 'conf' 'a3' optional
		if [ ! $prmItemName ] && [ ! $prmItemFiles ] && [ $prmItemDB ]; then
			prmItemName=$(upperCase $(echo $prmItemDB | sed 's/:.*//'))
		fi
		
		setBackupSetParam Server 'conf' 'a3' optional

		if [ $prmItemServer ] && [ ! "$prmItemServer" == 'global' ]; then
			prmItemStorage='remote'
			prmItemSub=($(echo $prmItemServer | sed 's/:/ /g'))
			setBackupSetParam RsyncServer ${prmItemSub[0]} 'address'
			setBackupSetParam RsyncServerPort ${prmItemSub[1]} 'num' optional
			[ ! $prmItemRsyncServerPort ] && prmItemRsyncServerPort='873'
			setBackupSetParam RsyncServerGroup ${prmItemSub[2]} 'alpha'
		fi
		prmItemSub=
		[ ! $prmItemStorage ] && prmItemStorage='local'

		setBackupSetParam HelperPort 'conf' 'num' optional

		setBackupSetParam StoragePath 'conf' 'path' optional

		setBackupSetParam Frequency 'conf' 'freq'
		setBackupSetParam Method 'conf' 'method'
		setBackupSetParam ReportPath 'conf' 'path' optional
		setBackupSetParam ReportMail 'conf' 'email' optional
		setBackupSetParam StoreVolMax 'conf' 'pcent' optional
		setBackupSetParam StoreGroupMax 'conf' 'size' optional
		setBackupSetParam StoreSetMax 'conf' 'size' optional


	#103# SKIP1: while param error found skipping the set
	#
                                                                                                            [ $debug -gt 4 ] && echo "103# SKIP1: while param error found skipping the set"
		if [ $curSetParamErr -ne 0 ]; then
			let curErr=$curErr+$curSetParamErr
			logEntry2Err "$curSetParamErr error(s) found during BackupSet params processing. Skipping!"
			echo "$rptDashedLine" >>$prmLog
																											[ $debug -gt 3 ] && echo "### SKIP1"
			continue
		fi


	#104# Set array based params
	#
                                                                                                            [ $debug -gt 4 ] && echo "104# Set array based params"
		prmItemDB_Tb=($(echo $prmItemDB | sed 's/:/ /g'))
		
		prmItemFrequency_Tb=($(echo $prmItemFrequency | sed 's/:/ /g'))
		if [ ${prmItemFrequency_Tb[0]} == 'M' ]; then
			if [ ! ${prmItemFrequency_Tb[1]} ]; then
				prmItemFrequency_Tb[1]=$prmBackupMonthDay
			else
				prmItemFrequency_Tb[1]=$(echo "0${prmItemFrequency_Tb[1]}" | sed 's/[0-9]\{0,100\}\([0-9]\{2\}\)$/\1/')
			fi
		elif [ ${prmItemFrequency_Tb[0]} == 'W' ]; then
			if [ ! ${prmItemFrequency_Tb[1]} ]; then
				prmItemFrequency_Tb[1]=$prmBackupWeekDay
			else
				prmItemFrequency_Tb[1]=$(echo ${prmItemFrequency_Tb[1]} | sed 's/[0-9]\{0,100\}\([0-9]\)$/\1/')
			fi
		fi
		
		prmItemMethod_Tb=($(echo $prmItemMethod | sed 's/:/ /g'))


	#105# Set report backupset header
	#
                                                                                                            [ $debug -gt 4 ] && echo "105# Set report backupset header"
		rptFreq="$(getArrayValueByKey valFreqs ${prmItemFrequency_Tb[0]})"
		if [ ${prmItemFrequency_Tb[0]} == 'M' ]; then
			rptFreq="$rptFreq (${prmItemFrequency_Tb[1]})"
		elif [ ${prmItemFrequency_Tb[0]} == 'W' ]; then
			rptFreq="$rptFreq ($(getArrayValueByKey valDays ${prmItemFrequency_Tb[1]}))"
		fi
		rptMethod="$(getArrayValueByKey valMethods ${prmItemMethod_Tb[0]}${prmItemMethod_Tb[1]})"
		[ ${prmItemMethod_Tb[2]} ] && rptMethod="$rptMethod (inc amt: ${prmItemMethod_Tb[2]})"
		rptHeader[1]="$prmItemName - $(upperCase $prmItemStorage) [$rptFreq] [$rptMethod]"
		
		if [ $prmItemFiles ]; then
			rptHeader[2]="${is}Files: $prmItemFiles"
			[ $prmItemDB ] && rptHeader[2]="${rptHeader[2]} - DB: $(echo $prmItemDB | sed 's/:.*//')"
		else
			rptHeader[2]="${is}DB: $(echo $prmItemDB | sed 's/:.*//')"
		fi
		
		if [ $prmItemServer ]; then
			rptHeader[3]=$(echo "${is}Store: $prmItemRsyncServer,$prmItemRsyncServerPort,$prmItemRsyncServerGroup,$prmItemStoragePath" \
							| sed 's/,$/,GROUP-ROOTED/')
		else
			rptHeader[3]="${is}Store: $prmItemStoragePath"
		fi

		if [ "$prmItemStoreVolMax$prmItemStoreGroupMax$prmItemStoreSetMax" ]; then
			rptHeader[4]="${is}Stats: VolMax $prmItemStoreVolMax - GroupMax $prmItemStoreGroupMax -  SetMax $prmItemStoreSetMax"
			if [ $prmItemServer ]; then
				if [ $prmItemHelperPort ]; then
					rptHeader[4]="${rptHeader[4]} - Helper $prmItemHelperPort"
				else
					rptHeader[4]="${rptHeader[4]} - no Helper won't work"
				fi
			fi
		else
			rptHeader[4]="${is}Stats: no" 
		fi
		
		if [ $prmItemReportPath ]; then
			rptHeader[5]="${is}Dedic: Path $prmItemReportPath"
			[ $prmItemReportMail ] && rptHeader[5]="${rptHeader[5]} - Email $prmItemReportMail"
		elif [ $prmItemReportMail ]; then
			rptHeader[5]="${is}Dedic: Email $prmItemReportMail"
		fi

		for (( j=1 ; j<=${#rptHeader[*]} ; j++ )); do
			echo "${rptHeader[j]}" >>$prmLog
																											[ $debug -gt 0 ] && echo "${rptHeader[j]}"
		done


	#106# Set dedicated log (before following in order to report backup set issues to dedicated)
	#
                                                                                                            [ $debug -gt 4 ] && echo "106# Set dedicated log (before following in order to report backup set issues to dedicated)"
		if [ $prmItemReportPath ]; then
			if [ $(echo $prmItemReportPath | sed '/^\//!d') ]; then
				if [ ! -d "$prmItemReportPath" ]; then
					logEntry2Err "Dedicated Reporting absolute path not exists! ($prmItemReportPath)"
					let curSetParamErr+=1 ; prmItemReportPath=
				else
					prmItemReportPath="$prmItemReportPath/$my"
				fi
			else
				if [ $prmItemFiles ]; then
					prmItemReportPathRel="$prmItemReportPath/$my"
					prmItemReportPath="$prmItemFiles/$prmItemReportPath"
					if [ ! -d "$prmItemReportPath" ]; then
						logEntry2Err "Dedicated Reporting relative path not exists! ($prmItemReportPath)"
						let curSetParamErr+=1 ; prmItemReportPath=
					else
						prmItemReportPath="$prmItemReportPath/$my"
					fi
				else
					logEntry2Err "Dedicated Reporting path relative but 'Files' path param not defined! ($prmItemReportPath)"
					let curSetParamErr+=1 ; prmItemReportPath=
				fi
			fi
			if [ $prmItemReportPath ]; then
				mkdir -p "$prmItemReportPath"
				if [ ! -d $prmItemReportPath ]; then
					logEntry2Err "Dedicated Reporting path relative but 'Files' path param not defined! ($prmItemReportPath)"
					let curSetParamErr+=1 ; prmItemReportPath=
				else
					prmItemReportLog="$prmItemReportPath/${ts}"
					for (( j=1 ; j<=${#rptHeader[*]} ; j++ )); do
						echo "${rptHeader[j]}" >>$prmItemReportLog
					done
					echo "$rptDashedLine" >>$prmItemReportLog
				fi
			fi
		fi


	#107# Check params reliability
	#
                                                                                                            [ $debug -gt 4 ] && echo "107# Check params reliability"
		if [ $prmItemFiles ] && [ ! -d $prmItemFiles ]; then
			logEntry2Err "'Files' path not exists ($prmItemFiles)."
			let curSetParamErr+=1
		fi
		if [ $prmItemDB ] && [ ! "$(ps aux | grep 'mysql' | grep -v 'grep')" ]; then
			logEntry2Err "No mysql program running for 'DB' param (${prmItemDB_Tb[0]})"
			let curSetParamErr+=1 ; pass=0
		fi
		if [ $prmItemStorage == 'local' ]; then
			if [ ! $(echo $prmItemStoragePath | sed '/^\//!d') ]; then
				logEntry2Err "'StoragePath' path can't be relative ($prmItemStoragePath) for local backup."
				let curSetParamErr+=1
			elif [ ! -d $(dirname $prmItemStoragePath) ]; then
				logEntry2Err "'StoragePath' path dir not exists ($(dirname $prmItemStoragePath)) for local backup."
				let curSetParamErr+=1
			elif [ ! $prmItemStoragePath ]; then
				logEntry2Err "'StoragePath' void for a local backup."
				let curSetParamErr+=1
			elif [ "$prmItemStoragePath" == '/' ]; then
				logEntry2Err "'StoragePath' will going to hurt system."
				let curSetParamErr+=1
			fi
		fi


	#108# SKIP2: while param error found skipping the set
	#
                                                                                                            [ $debug -gt 4 ] && echo "108# SKIP2: while param error found skipping the set"
		if [ $curSetParamErr -ne 0 ]; then
			let curErr=$curErr+$curSetParamErr
			logEntry2Err "$curSetParamErr error(s) found during BackupSet params processing. Skipping!"
			echo "$rptDashedLine" >>$prmLog
																											[ $debug -gt 3 ] && echo "### SKIP2"
			continue
		fi


	#109# Check if BackupSet have to be processed
	#
                                                                                                            [ $debug -gt 4 ] && echo "109# Check if BackupSet have to be processed"
		pass=1
		if [ ! "${prmItemFrequency_Tb[0]}" == 'D' ]; then
			if [ "${prmItemFrequency_Tb[0]}" == 'W' ]; then
				if [ ! "$curWoDay" == "${prmItemFrequency_Tb[1]}" ]; then
					logEntry2 "--- Weekly escaped for today ---"
					pass=0
				fi
			elif [ "${prmItemFrequency_Tb[0]}" == 'M' ]; then
				if [ ! "$curDay" == "${prmItemFrequency_Tb[1]}" ]; then
					logEntry2 "--- Monthly escaped for today ---"
					pass=0
				fi
			fi
			if [ $pass -eq 0 ] || [ "${prmItemFrequency_Tb[0]}" == 'T' ]; then
				if [ -f "$prmItemFiles/$prmBackupSemFileName" ]; then
					logEntry2 "### Backup semaphore found ###"
					pass=1
				else
					logEntry2 "--- No backup semaphore found ---"
					pass=0
				fi
			fi
		fi


	#110# SKIP3: while BackupSet is not to proccess
	#
                                                                                                            [ $debug -gt 4 ] && echo "110# SKIP3: while BackupSet is not to proccess"
		if [ $pass -ne 1 ]; then
																											[ $debug -gt 3 ] && echo "### SKIP3"
			continue
		fi


	#111# Arch, Logs, Destination params
	#
                                                                                                            [ $debug -gt 4 ] && echo "111# Arch, Logs, Destination params"
		if [ $prmItemStorage == 'remote' ]; then
			if [ $prmItemStoragePath ]; then
				tp="$prmItemStoragePath"
			else
				if [ $prmItemFiles ]; then
					tp="$(basename $prmItemFiles)"
				elif [ $prmItemDB ]; then
					tp="${prmItemDB_Tb[0]}"
				fi
			fi
		elif [ $prmItemStorage == 'local' ]; then
			tp="$prmItemStoragePath"
		else
			logEntryExit "BUG: backup is neither remote nor local."
		fi
		bn=$prmItemName

#echo "bn=$bn"
#echo "tp=$tp"

		prmRsyncOption=
		prmItemRSA=
		if [ "$prmItemStorage" == 'remote' ]; then
			prmItemRSA="$prmItemRsyncServer::$prmItemRsyncServerGroup/"
		fi
		prmItemSRC_="${prmTempFolder}/${ts}_${bn}"
		if [ "${prmItemMethod_Tb[0]}" == 'C' ]; then
			prmItemSRC_FILES_File="$prmItemSRC_.tgz"
			prmItemBKP="${prmItemRSA}$tp/"										# Take care to endded double /
			prmItemBKP_DB="$prmItemBKP"											#				"
			stats_Files_Fld=$tp
			stats_DB_Fld=
		else
			prmItemSRC_FILES_File="$prmItemFiles"
			if [ ! $prmItemStoragePath ]; then
				prmItemBKP="$prmItemRSA"
				stats_Files_Fld="$(basename $prmItemFiles)"
			else
				prmItemBKP="${prmItemRSA}$tp/"
				stats_Files_Fld="$tp/$(basename $prmItemFiles)"
			fi
			prmItemBKP_DB="${prmItemRSA}${tp}_DB/"
			stats_DB_Fld=${tp}_DB
			
			prmRsyncOption='--delete-excluded'
			if [ "${prmItemMethod_Tb[1]}" == 'B' ]; then
				prmRsyncOption="--backup --suffix=$prmRsyncSuffix $prmRsyncOption $prmFiltersFile"
			elif [ "${prmItemMethod_Tb[1]}" == 'D' ]; then
				prmRsyncOption="--delete $prmRsyncOption $prmFiltersFile"
			fi
		fi

		prmItemBKP=$(echo $prmItemBKP | sed 's/\/\/$/\//')

		prmRsyncPort=
		if [ "$prmItemStorage" == 'remote' ] && [ $prmItemRsyncServerPort ]; then
			prmRsyncPort="--port $prmItemRsyncServerPort"
		fi

		prmItemSRC_FILES_TarLogStd="$prmItemSRC_.files_arc-standard"
		prmItemSRC_FILES_TarLogErr="$prmItemSRC_.files_arc-errors"
		prmItemSRC_FILES_RsyncLogStd="$prmItemSRC_.files_trf-standard"
		prmItemSRC_FILES_RsyncLogErr="$prmItemSRC_.files_trf-errors"

		prmItemSRC_DB_File="$prmItemSRC_.dump"
		prmItemSRC_DB_DumpLogStd="$prmItemSRC_.db_dump-standard"
		prmItemSRC_DB_DumpLogErr="$prmItemSRC_.db_dump-errors"
		prmItemSRC_DB_TarLogStd="$prmItemSRC_.db_arc-standard"
		prmItemSRC_DB_TarLogErr="$prmItemSRC_.db_arc-errors"
		prmItemSRC_DB_RsyncLogStd="$prmItemSRC_.db_trf-standard"
		prmItemSRC_DB_RsyncLogErr="$prmItemSRC_.db_trf-errors"


	#112# Reset set errors counter
	#
                                                                                                            [ $debug -gt 4 ] && echo "112# Reset set errors counter"
		curSetErr=0

    #
	##113# Backup Src folder
	#
                                                                                                            [ $debug -gt 4 ] && echo "113# Backup Src folder"
		if [ $prmItemFiles ]; then
                                                                #echo "-${prmItemMethod_Tb[*]}-"
			if [ "${prmItemMethod_Tb[0]}" == 'C' ]; then
				logEntry2 "Compressing source: $prmItemFiles"
																											[ $debug -gt 3 ] && echo "tar czvf $prmItemSRC_FILES_File $prmItemFiles 1>$prmItemSRC_FILES_TarLogStd 2>$prmItemSRC_FILES_TarLogErr" || \
				tar czvf $prmItemSRC_FILES_File $prmItemFiles 1>$prmItemSRC_FILES_TarLogStd 2>$prmItemSRC_FILES_TarLogErr
				[ "$curOS" == 'Darwin' ] && transfertLines "$prmItemSRC_FILES_TarLogErr" "$prmItemSRC_FILES_TarLogStd" "^a "
				logAddResult 'stdtar' $prmItemSRC_FILES_TarLogStd
				logAddResult 'err' $prmItemSRC_FILES_TarLogErr
			fi

			logSetStorageStats 'levels' 'before'
			logEntry2 "Backuping source: $prmItemSRC_FILES_File to: $prmItemBKP"
			[ ! "$prmRsyncOption" == '' ] && logEntry2 "options: $prmRsyncOption"
																											[ $debug -gt 3 ] && echo "rsync -avz $prmRsyncPort $prmRsyncOption $prmItemSRC_FILES_File $prmItemBKP >$prmItemSRC_FILES_RsyncLogStd 2>$prmItemSRC_FILES_RsyncLogErr" || \
			rsync -avz $prmRsyncPort $prmRsyncOption $prmItemSRC_FILES_File $prmItemBKP >$prmItemSRC_FILES_RsyncLogStd 2>$prmItemSRC_FILES_RsyncLogErr
			logAddResult 'std' $prmItemSRC_FILES_RsyncLogStd
			logAddResult 'err' $prmItemSRC_FILES_RsyncLogErr
			logSetStorageStats 'levels' 'after'
		fi				

	#
	##114# Backup DB
	#
                                                                                                            [ $debug -gt 4 ] && echo "114# Backup DB"
		if [ $prmItemDB ]; then
			logEntry2 "Dumping DB: ${prmItemDB_Tb[0]} to: $prmItemSRC_DB_File"
																											[ $debug -gt 3 ] && echo "mysqldump --user='${prmItemDB_Tb[1]}' --password='${prmItemDB_Tb[2]}' --host='localhost' '${prmItemDB_Tb[0]}' >$prmItemSRC_DB_File 2>$prmItemSRC_DB_DumpLogErr" || \
			mysqldump --user="${prmItemDB_Tb[1]}" --password="${prmItemDB_Tb[2]}" --host='localhost' "${prmItemDB_Tb[0]}" >$prmItemSRC_DB_File 2>$prmItemSRC_DB_DumpLogErr
			#logAddResult 'std' $prmItemSRC_DB_DumpLogStd
			logAddResult 'err' $prmItemSRC_DB_DumpLogErr
			
			logEntry2 "Compressing DB File $prmItemSRC_DB_File"
																											[ $debug -gt 3 ] && echo "tar czvf $prmItemSRC_DB_File.tgz $prmItemSRC_DB_File 1>$prmItemSRC_DB_TarLogStd 2>$prmItemSRC_DB_TarLogErr" || \
			tar czvf "$prmItemSRC_DB_File.tgz" $prmItemSRC_DB_File 1>$prmItemSRC_DB_TarLogStd 2>$prmItemSRC_DB_TarLogErr
			[ "$curOS" == 'Darwin' ] && transfertLines "$prmItemSRC_DB_TarLogErr" "$prmItemSRC_DB_TarLogStd" "^a "
			logAddResult 'stdtar' $prmItemSRC_DB_TarLogStd
			logAddResult 'err' $prmItemSRC_DB_TarLogErr
			
			logSetStorageStats 'levels' 'before'
			logEntry2 "Backuping DB: $prmItemSRC_DB_File.tgz to: $prmItemBKP_DB"
																											[ $debug -gt 3 ] && echo "rsync -avz $prmRsyncPort $prmItemSRC_DB_File.tgz $prmItemBKP_DB >$prmItemSRC_DB_RsyncLogStd 2>$prmItemSRC_DB_RsyncLogErr" || \
			rsync -avz $prmRsyncPort $prmItemSRC_DB_File.tgz $prmItemBKP_DB >$prmItemSRC_DB_RsyncLogStd 2>$prmItemSRC_DB_RsyncLogErr
			logAddResult 'std' $prmItemSRC_DB_RsyncLogStd
			logAddResult 'err' $prmItemSRC_DB_RsyncLogErr
			logSetStorageStats 'levels' 'after'
		fi

	#115# Remove SEM file
	#
                                                                                                            [ $debug -gt 4 ] && echo "115# Remove SEM file"
		[ -f "$prmItemSrc/$prmBackupSemFileName" ] && rm -f "$prmItemSrc/$prmBackupSemFileName"


	#116# Mail Dedicated Report
	#
                                                                                                            [ $debug -gt 4 ] && echo "116# Mail Dedicated Report"
		if [ $prmItemReportMail ]; then
			if [ $prmEmailTmpl ]; then
				rptDB='No DB' ; [ $prmItemDB ] && rptDB=${prmItemDB_Tb[0]}
				rptErr='Successful' ; rptErrStamp=
				if [ $curSetErr -gt 0 ]; then
					rptErr="$curSetErr error(s)"
					rptErrStamp='***ERRORS***'
				fi
				rptLog='No defined dedicated log'
				if [ $prmItemReportPath ]; then
					rptLog="$prmItemReportPathRel"
				elif [ $prmItemReportPath ]; then
					rptLog="$prmItemReportPath"
				fi
				
				cat "$prmEmailTmpl" | \
					sed -e "s|%HOSTNAME%|$(hostname)|"				\
						-e "s|%NAME%|$prmItemName|"					\
						-e "s|%FILES%|$(basename $prmItemFiles)|"	\
						-e "s|%DB%|$rptDB|"							\
						-e "s|%DATE%|$rptDate|"						\
						-e "s|%TIME%|$rptTime|"						\
						-e "s|%METHOD%|$rptMethod|"					\
						-e "s|%PROG%|$rptFreq|"						\
						-e "s|%RESULT%|$rptErr|"					\
						-e "s|%LOGPATH%|$rptLog|"					\
						-e "s|%HEXE%|$(getMyRunTime)|"				\
						-e "s|%VERS%|$(getMyVersion)|"				\
						| mail -s "$rptErrStamp $prmMailSubjectReport $ts : $prmItemName" "$rptMailParams" "$prmItemReportMail"
											
			else
				logEntry2Err "Dedicated mail report can't be done. Mail template not exists!"
			fi
		fi

		#echo $rptDashedLine >>$prmLog
		#																									[ $debug -gt 0 ] && echo $rptDashedLine

	done

##200# Finishing global report
#
                                                                                                            [ $debug -gt 4 ] && echo "200# Finishing global report"
	echo $rptDashedLine >>$prmLog
																											[ $debug -gt 0 ] && echo $rptDashedLine

	rptErrStamp=
	if [ $curErr -gt 0 ]; then
		logEntry "*** FINISHING WITH $curErr ERROR(S) ***"
		rptErrStamp='***ERRORS***'
	fi


##201# Mail report
#
                                                                                                            [ $debug -gt 4 ] && echo "201# Mail report"
    if [ $prmMailToReport ]; then
        cat "$prmLog" | mail -s "$rptErrStamp $prmMailSubjectReport $ts" "$rptMailParams" "$prmMailToReport"
    fi


##202# Terminate job
#
                                                                                                            [ $debug -gt 4 ] && echo "202# Terminate job"
	rm -f /var/run/$my.pid



	
