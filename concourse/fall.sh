#!/usr/bin/env bash

workdir=/tmp
teams=""
regexp="NULL"
declare -A pipelines=()
declare -A paths=(
	[stdin]="$workdir"/fly.stdin
	[stderr]="$workdir"/fly.stderr
	[stdout]="$workdir"/fly.stdout
)

declare -A fds=(
	[stdin]=3
	[stderr]=4
	[stdout]=5
)

declare -A cmd=(
	[date]=date
	[fly]=fly
	[mkfifo]=mkfifo
	[unlink]=rm
	[sleep]=sleep
	[ff]=firefox
	[pkill]=pkill
	[ctx]=/usr/local/bin/concourse/bin/ctr
	[grep]=grep
	[awk]=awk
	[kubectl]=kubectl
)

declare -A fly=(
	[target]=gs
	[c]=$CONCOURSE_URL
)

declare -A k8s=(
	[ns]=$CONCOURSE_NAMESPACE
	[sleep]=3
)

count=0
pids=[]
current_time="$(${cmd[date]} +%s)"
if [ -n $MAX_PIPELINE_IDLE_TIME ]; then
	idle=$MAX_PIPELINE_IDLE_TIME
else
	idle=604800
fi
max_time=$((current_time - idle))

main () {
	while (($#)); do
		case "$1" in
			-l | --login-all)
				if [ -n "$2" ]; then
					fly[target]="$2"
				fi
				set_auth
				exit 0
				;;
			--max-pipeline-idle)
				if [ -n "$2" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
					max_time=$((current_time - $2))
				else
					toerr "invalid max-pipeline-idle: \'%s\'." "$2"
				fi
				shift 2
				;;
			-j | --jobs)
				if [ -n "$2" ]; then
					teams="$2"
				fi
				get_jobs
				exit 0
				;;
			--list-stale-jobs)
				if [ -n "$2" ]; then
					teams="$2"
				fi
				list_old
				break
				;;
			--pause-stale-jobs)
				if [ -n "$2" ]; then
					teams="$2"
				fi
				pause_old
				break
				;;
			--stale-pipelines)
				if [ -n "$2" ]; then
					teams="$2"
				fi
				stale_pipelines
				break
				;;
			--pause-stale-pipelines)
				if [ -n "$2" ]; then
					teams="$2"
				fi
				stale_pipelines
				break
				;;
			-r | --resources)
				if [ -n "$2" ]; then
					teams="$2"
				fi
				get_resources
				exit 0
				;;
			-c | --check-resources)
				if [ -n "$2" ]; then
					teams="$2"
				fi
			  check_resources
				exit 0
				;;
			--purge-containers)
				if [ -n "$2" ]; then
					regexp=${2##*/}
					teams=${2%%/*}
				else
					printf "please supply 'team/regexp'\n" >&2
					show_help
					exit 1
				fi
				purge_containers
				exit 0
				;;
			-h | --help)
				show_help
				exit 0
				;;
			*)
				printf "Help, I've fallen and I can't get up!\n  Try --help.\n" >&2
				exit 1
		esac
	done
	printf "nothing to do\n  Try --help.\n"
	exit 0
}


show_help () {
	printf "Usage: %s [OPTION...]\n\n" "$0"
	printf "    -l, --login-all [initial target]     Login to all targets.\n"
	printf "                                         Opens a web browser tab to log into all targets.\n"
	printf "                                             it is recommended to log into concourse ui\n"
	printf "                                             via firefox prior to running the this command\n"
	printf "                                         [initial target] defaults to 'gs'\n\n"

	printf "    -r, --resources [target]             print json representing resources for a given project\n"
	printf "                                         if [target] is omitted, all resources are listed'\n"
	printf "                                         try: \`%s -r | tee foo.json | jq\`\n\n" "$0"

	printf "    -c, --check-resources [target]       run a resource check for a given project\n"
	printf "                                         if [target] is omitted, all resources are checked'\n\n"

	printf "        --pause-stale-pipelines [target] pause all stale pipelines in a given target\n"
	printf "                                         if [target] is omitted, all targets are checked'\n\n"

	printf "        --max-pipeline-idle seconds      maximum number of seconds between now and when any job\n"
	printf "                                         within a pipeline has ran\n"
	printf "                                             defaults to 604800\n"
	printf '                                             can also be set via $MAX_PIPELINE_IDLE_TIME\n\n'

	printf "    -p, --purge-containers target/regexp ensure all builds are aborted and containers removed\n"
	printf "                                         in the supplied project AND matching the provided\n"
	printf "                                         regexp for example if one wanted to remove all\n"
	printf "                                         containers matching 'bar' OR 'foo' in\n'"
	printf "                                         'fizzbuzz' they could try:\n"
	#shellcheck disable=SC2016
	printf '                                          `%s -r -p fizzbuzz/subnet-exporter|foo`\n' "$0"
	printf "                                         NOTE: '-p' uses bash shell expansion to separate on '/'\n"
	printf "                                               DO NOT supply a '/' in the regexp\n\n"
	printf "                                         NOTE: '-p' is not a general solution, it is implementation\n"
	printf "                                               specific\n"
}

bail () {
	if [ -z "$1" ]; then
		toerr "no exit code returned\n" 1>&2
		exit 1
	elif [ "$1" -ne 0 ]; then
		{ [[ -z "$2" ]] && toerr "failed\n" 1>&2; } || toerr "%s\n" "$2"
	fi
	exit "$1"
}


toout(){
	flock -x "${fds[stdout]}"
	#shellcheck disable=SC2059
	printf "$@"
	flock -u "${fds[stdout]}"
}
toerr(){
	flock -x "${fds[stderr]}"
	#shellcheck disable=SC2059
	printf "$@" 1>&2
	flock -u "${fds[stderr]}"
}

set_pipes () {
	"${cmd[mkfifo]}" "${paths[@]}" || bail 1 'failed to create pipes'
		for i in "${!fds[@]}"; do
			eval "exec ${fds[$i]}<> ${paths[$i]}"
		done
}

unset_pipes () {
	for i in "${paths[@]}"; do
	[ -f "$i" ] && \
		{ "${cmd[unlink]}" "$i" ||  toerr 'failed to unlink %s\n' "$i" ; }
	done
}

get_teams() {
	teams=$("${cmd[fly]}" -t "${fly[target]}" teams)
}

out (){
	for pid in ${pids[*]}; do
		kill -0 "$pid" 2>/dev/null \
			&& kill "$pid"
	done
	final="$(jobs -p)"
	[ -n "$final" ] && kill "$final" 2>/dev/null
	unset_pipes
	exit 1
}


set_auth(){
	set_pipes
	get_teams
	for i in $teams; do
		 eval "${cmd[fly]} \
			-t $i \
			login \
				-n $i \
				-c ${fly[c]} \
			>&${fds[stdout]} \
			<&${fds[stdin]} \
			2>&${fds[stderr]} &"

		pid="$!"
		echo "$i $pid"

		while read -r line; do
			[[ $line == *"https"* ]] && \
				{ ${cmd[ff]} -new-tab -url "$line" ; break ; }
		done < "${paths[stdout]}"
		wait $pid
	done
}

get_pipelines() {
		pipelines=()
		while read -r id name paused rest; do
			pipelines["$name"]="$id $paused"
		done < <(
		${cmd[fly]} -t "$1" pipelines
	)

}


check_resources() {
	[ "$teams" == "" ] && get_teams
	for i in $teams; do
		get_pipelines "$i"
		for j in "${!pipelines[@]}"; do
			while read -r name rest; do
				${cmd[fly]} -t "$i" check-resource --resource="$j/$name"
			done < <(
				${cmd[fly]} resources -t "$i" -p "$j"
			)
		done
	done

}


get_resources() {
	# don't judge me monkey
	[ "$teams" == "" ] && get_teams
	flock -x "${fds[stdout]}"
	printf '['
	for i in $teams; do
		[ -n "$ft" ] && printf ","
		printf '{"team":"%s","pipelines": [' "$i"
		get_pipelines "$i"

		for j in "${!pipelines[@]}"; do
			[ -n "$fp" ] && printf ","
			printf '{"pipeline":"%s", "resources": [' "$j"
			while read -r name type rest; do
				[ -n "$fj" ] && printf ","
				printf '{"name": "%s","type": "%s"}' "$name" "$type"
				fj=true
			done < <(\
				${cmd[fly]} resources -t "$i" -p "$j"
			)
			unset fj
			printf "]}"
			fp=true
		done
		unset fp
		printf "]}"
		pipelines=()
		ft=true
	done
	printf ']'
	flock -u "$stderr"

}

get_jobs() {
	[ "$teams" == "" ] && get_teams
	for i in $teams; do
		get_pipelines "$i"
		for j in "${!pipelines[@]}"; do
			while read -r id name last_build; do
				toout "%s %s %s %s %s\n" "$id" "$i" "$j" "$name" "$last_build"
			done < <(
					${cmd[fly]} jobs -t "$i" -p "$j" --json 2>/dev/null\
					| jq -r '.[] | "\(.id) \(.name) \(.finished_build.start_time)"' \
						; [ "${PIPESTATUS[0]}" -eq 0 ] \
						|| bail 1 "failed to get jobs: $i/$j"
			) &
			pids[$(get_count)]=$!
			wait_pids
		done
	done
}

get_count(){
	flock -x "${fds[stdout]}"
	printf "%s\n" $count
	((count++))
	flock -u "${fds[stdout]}"
}

wait_pids() {
		while [ "$count" -ne 0 ]; do
			kill -0 $pid 2>/dev/null \
				&& wait ${pids[$count]}
			unset ${pids[$count]}
			((count--))
		done
}

to_date(){
	date --date=@"$1"
}

stale_pipelines(){
	do_pause=1
	dont_pause=0
	declare -A p=()
	while read -r id team pipeline job last_build; do
		key="$team $pipeline"
		[ -n "${p[$key]}" ] && [ "${p[$key]}" -eq $dont_pause ] && continue
		[ "$last_build" == 'null' ] && continue
	  [ "$last_build" -lt 0 ] && continue

		if [ "$last_build" -gt "$max_time" ]; then
			 p["$key"]=$dont_pause
			 continue
		fi

		p[$key]=$do_pause
	done < <(get_jobs)

	for i in "${!p[@]}"; do
		[ ${p[$i]} -eq $do_pause ] && toout "%s\n" "$i";
	done
}

disable_stale_pipelines(){
	while read -r team pipeline; do
		#printf "disabling: %s.%s\n" "$team" "$pipeline"
		toout "${cmd[fly]}" -t "$team" pause-pipeline "$pipeline"
	done < <(stale_pipelines)
}

list_old() {
	while read -r id team pipeline job last_build; do
		if [[ "$last_build" == 'null' ]] || [ "$last_build" -lt 0 ]; then
			toout "%s %s/%s has invalid time for last run: %s\n" \
				"$team" "$pipeline" "$job" "$last_build" 1>&2
				continue
		fi

	[[ "$last_build" -lt "$max_time" ]] \
		&& printf "%s %s %s\n" "$team" "$pipeline" "$job";
	done < <(get_jobs)
}

pause_old(){
	while read -r team pipeline job; do
		toout "${cmd[fly]}" pj -t "$team" -j "$pipeline/$job" &
			pids[$(get_count)]=$!
	done < <(list_old)
	wait_pids
}

purge_containers() {
	while read -r cont host build; do
		printf "\n\n%s %s %s\n" "$cont" "$host" "$build"
		${cmd[fly]} -t prod abort-build -b "$build" && \
		${cmd[kubectl]} --namespace="${k8s[ns]}" exec pod/"$host" -- /bin/bash -c "\
			${cmd[ctx]} --namespace=${k8s[ns]} t kill -a $cont ;\
			${cmd[sleep]} $${k8s[sleep]} ;\
			${cmd[ctx]} --namespace=${k8s[ns]} container rm $cont \
				|| { ${cmd[ctx]} --namespace=${k8s[ns]} t kill -a -s 9 $cont ; ${cmd[sleep]} ${k8s[sleep]} ; } ;\
			${cmd[ctx]} --namespace=${k8s[ns]} container rm $cont \
				|| { printf 'FAIL: %s\n' $cont >&2 ; return 1 ; }"
					done < <(\
		#shellcheck disable=SC2016
		${cmd[fly]} -t "$teams" containers \
		| ${cmd[grep]} -E "$regexp" \
		| ${cmd[awk]} '{print $1 " " $2 " " $6}')
}

trap out INT EXIT TERM
main "$@"
