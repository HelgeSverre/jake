#!/usr/bin/env bash
# Simple dumb fuzzer for jake-fuzz-parse
# Mutates corpus files and looks for crashes
#
# Usage: ./scripts/dumb-fuzz.sh [iterations]
#        Default: 1000 iterations

set -euo pipefail

ITERATIONS="${1:-1000}"
HARNESS="./zig-out/bin/jake-fuzz-parse"
CORPUS_DIR="corpus"
FINDINGS_DIR="findings"
CRASH_DIR="$FINDINGS_DIR/crashes"

mkdir -p "$CRASH_DIR"

if [[ ! -x "$HARNESS" ]]; then
	echo "Building fuzz harness..."
	zig build fuzz-parse -Doptimize=ReleaseSafe
fi

if [[ ! -d "$CORPUS_DIR" ]] || [[ -z "$(ls -A "$CORPUS_DIR" 2>/dev/null)" ]]; then
	echo "Seeding corpus..."
	mkdir -p "$CORPUS_DIR"
	cp Jakefile "$CORPUS_DIR/"
	find samples -name "Jakefile" -exec cp {} "$CORPUS_DIR/" \; 2>/dev/null || true
	find samples -name "*.jake" -exec cp {} "$CORPUS_DIR/" \; 2>/dev/null || true
fi

CORPUS_FILES=("$CORPUS_DIR"/*)
CORPUS_COUNT=${#CORPUS_FILES[@]}

if [[ $CORPUS_COUNT -eq 0 ]]; then
	echo "No corpus files found!"
	exit 1
fi

echo "Fuzzing with $CORPUS_COUNT corpus files for $ITERATIONS iterations..."
echo "Crashes will be saved to: $CRASH_DIR"
echo ""

crashes=0
runs=0

# Mutation strategies
mutate_input() {
	local input="$1"
	local strategy=$((RANDOM % 8))

	case $strategy in
	0) # Insert random bytes
		local pos=$((RANDOM % (${#input} + 1)))
		local char=$(printf "\\x$(printf '%02x' $((RANDOM % 256)))")
		echo "${input:0:$pos}${char}${input:$pos}"
		;;
	1) # Delete random byte
		if [[ ${#input} -gt 1 ]]; then
			local pos=$((RANDOM % ${#input}))
			echo "${input:0:$pos}${input:$((pos + 1))}"
		else
			echo "$input"
		fi
		;;
	2) # Flip random bit
		if [[ ${#input} -gt 0 ]]; then
			local pos=$((RANDOM % ${#input}))
			local byte=$(printf '%d' "'${input:$pos:1}")
			local bit=$((1 << (RANDOM % 8)))
			local newbyte=$((byte ^ bit))
			printf '%s%b%s' "${input:0:$pos}" "\\x$(printf '%02x' $newbyte)" "${input:$((pos + 1))}"
		else
			echo "$input"
		fi
		;;
	3) # Replace with interesting token
		local tokens=("task" "@if" "@else" "@end" "@each" "{{" "}}" "@import" "@default" ":" "[" "]" "=" "\n" "\t" "    ")
		local tok="${tokens[$((RANDOM % ${#tokens[@]}))]}"
		local pos=$((RANDOM % (${#input} + 1)))
		echo "${input:0:$pos}${tok}${input:$pos}"
		;;
	4) # Duplicate a chunk
		if [[ ${#input} -gt 10 ]]; then
			local start=$((RANDOM % (${#input} - 5)))
			local len=$((RANDOM % 10 + 1))
			local chunk="${input:$start:$len}"
			echo "${input}${chunk}"
		else
			echo "$input$input"
		fi
		;;
	5) # Truncate
		if [[ ${#input} -gt 1 ]]; then
			local len=$((RANDOM % ${#input}))
			echo "${input:0:$len}"
		else
			echo "$input"
		fi
		;;
	6) # Add newlines
		local pos=$((RANDOM % (${#input} + 1)))
		echo "${input:0:$pos}"$'\n\n\n'"${input:$pos}"
		;;
	7) # Pass through (no mutation)
		echo "$input"
		;;
	esac
}

trap 'echo ""; echo "Completed $runs runs, found $crashes crashes"; exit 0' INT

for ((i = 1; i <= ITERATIONS; i++)); do
	# Pick random corpus file
	corpus_file="${CORPUS_FILES[$((RANDOM % CORPUS_COUNT))]}"
	input=$(cat "$corpus_file")

	# Apply 1-3 mutations
	mutations=$((RANDOM % 3 + 1))
	for ((m = 0; m < mutations; m++)); do
		input=$(mutate_input "$input")
	done

	# Write to temp file
	tmpfile=$(mktemp)
	echo "$input" >"$tmpfile"

	# Run harness with timeout
	runs=$((runs + 1))
	if ! timeout 2s "$HARNESS" "$tmpfile" >/dev/null 2>&1; then
		exit_code=$?
		if [[ $exit_code -eq 124 ]]; then
			echo "[$i] TIMEOUT"
		elif [[ $exit_code -gt 128 ]]; then
			# Crashed (signal)
			crashes=$((crashes + 1))
			crash_file="$CRASH_DIR/crash-$(date +%s)-$RANDOM"
			cp "$tmpfile" "$crash_file"
			echo "[$i] CRASH (signal $((exit_code - 128))) -> $crash_file"
		fi
	fi

	rm -f "$tmpfile"

	# Progress every 100 iterations
	if [[ $((i % 100)) -eq 0 ]]; then
		echo "[$i/$ITERATIONS] runs=$runs crashes=$crashes"
	fi
done

echo ""
echo "Completed $runs runs, found $crashes crashes"
if [[ $crashes -gt 0 ]]; then
	echo "Crash files saved to: $CRASH_DIR"
	ls -la "$CRASH_DIR"
fi
