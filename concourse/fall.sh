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
max_time=$((current_time - 604800))


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
			-j | --jobs)
				if [ -n "$2" ]; then
					teams="$2"
				fi
				get_jobs
				exit 0
				;;
			-o | --old)
				if [ -n "$2" ]; then
					teams="$2"
				fi
				list_old
				break
				;;
			-p | --pause-old)
				if [ -n "$2" ]; then
					teams="$2"
				fi
				pause_old
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

	printf "    -p, --purge-containers target/regexp ensure all builds are aborted and containers removed\n"
	printf "                                         in the supplied project AND matching the provided\n"
	printf "                                         regexp for example if one wanted to remove all\n"
	printf "                                         containers matching 'bar' OR 'foo' in\n'"
	printf "                                         'fizzbuzz' they could try:\n"
	printf '                                          `%s -r -p fizzbuzz/subnet-exporter|foo`\n' "$0"
	printf "                                         NOTE: '-p' uses bash shell expansion to separate on '/'\n"
	printf "                                               DO NOT supply a '/' in the regexp\n\n"
	printf "                                         NOTE: '-p' is not a general solution, it is implementation"
	printf "                                               specific\n"
}

bail () {
	if [ -z "$1" ]; then
		printf "no exit code returned\n" 1>&2
		return 1
	elif [ "$1" -ne 0 ]; then
		[[ -z "$2" ]] && printf "failed\n" 1>&2 || printf "%s\n" "$2" 1>&2
	fi
	exit "$1"
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
		{ "${cmd[unlink]}" "$i" ||  printf 'failed to unlink %s\n' "$i" >&2 ; }
	done
}

get_teams() {
	teams=$("${cmd[fly]}" -t "${fly[target]}" teams)
}

out (){
	printf "caught INT\n" 1>&2
	for pid in ${pids[*]}; do
		printf "killing %s\n" "$pid" 1>&2
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
			[[ $line == *"https"* ]] && { ${cmd[ff]} -new-tab -url "$line" ; break ; }
		done < "${paths[stdout]}"
		wait $pid
	done
}

get_pipelines() {
		pipelines=()
		while read -r id name paused rest; do
			pipelines["$name"]="$id $paused"
		done < <(
		fly -t "$1" pipelines
	)

}


check_resources() {
	[ "$teams" == "" ] && get_teams
	for i in $teams; do
		get_pipelines "$i"
		for j in "${!pipelines[@]}"; do
			while read -r name rest; do
				fly -t "$i" check-resource --resource="$j/$name"
			done < <(
				fly resources -t "$i" -p "$j"
			)
		done
	done

}


get_resources() {
	# don't judge me monkey
	[ "$teams" == "" ] && get_teams
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
				fly resources -t "$i" -p "$j"
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

}

get_jobs() {
	[ "$teams" == "" ] && get_teams
	for i in $teams; do
		get_pipelines "$i"
		for j in "${!pipelines[@]}"; do
			while read -r id name last_build; do
				flock -x 1
				printf "%s %s %s %s %s\n" "$id" "$i" "$j" "$name" "$last_build"
				flock -u 1
			done < <(
					fly jobs -t "$i" -p "$j" --json 2>/dev/null\
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
	printf "%s\n" $count
	((count++))
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

list_old() {
	while read -r id team pipeline job last_build; do
		if [[ "$last_build" == 'null' ]] || [ "$last_build" -lt 0 ]; then
			flock -x 2
			printf "%s %s/%s has invalid time for last run: %s\n" \
				"$team" "$pipeline" "$job" "$last_build" 1>&2
			flock -u 2
				continue
		fi

	[[ "$last_build" -lt "$max_time" ]] \
		&& printf "%s %s %s\n" "$team" "$pipeline" "$job";
	done < <(get_jobs)
}

pause_old(){
	while read -r team pipeline job; do
		echo fly pj -t "$team" -j "$pipeline/$job" &
			pids[$(get_count)]=$!
	done < <(list_old)
	wait_pids

}


purge_containers() {
	while read -r cont host build; do
		printf "\n\n%s %s %s\n" "$cont" "$host" "$build"
		fly -t prod abort-build -b "$build" && \
		kubectl --namespace=${k8s[ns]} exec pod/"$host" -- /bin/bash -c "\
			${cmd[ctx]} --namespace=${k8s[ns]} t kill -a $cont ;\
			${cmd[sleep]} $${k8s[sleep]} ;\
			${cmd[ctx]} --namespace=${k8s[ns]} container rm $cont \
				|| { ${cmd[ctx]} --namespace=${k8s[ns]} t kill -a -s 9 $cont ; ${cmd[sleep]} ${k8s[sleep]} ; } ;\
			${cmd[ctx]} --namespace=${k8s[ns]} container rm $cont \
				|| { printf 'FAIL: %s\n' $cont >&2 ; return 1 ; }"
					done < <(\
		fly -t "$teams" containers \
		| grep -E "$regexp" \
		| awk '{print $1 " " $2 " " $6}')
}

trap out INT EXIT TERM
main "$@"
