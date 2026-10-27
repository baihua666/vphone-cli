#!/bin/zsh
set -euo pipefail
module="${0:a:h}"
repo="${module:h:h}"
source "$module/Configuration/experiment.zsh"
output="$repo/.build/nfc-no-rf-m0"
mkdir -p "$output"
case "${1:-build}" in
    build|test) action=${1:-build} ;;
    *) print -u2 'usage: build.zsh [build|test]'; exit 2 ;;
esac
if [[ "$nfc_experiment_enabled" != 1 ]]; then
    rm -rf "$output/enabled"
    xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
        "$module"/VPhoneNFCResearch/*.swift -o "$output/disabled"
    "$output/disabled"
    if [[ "$action" == test ]]; then
        print -u2 'Tests require explicit VPHONE_EXPERIMENTAL_NFC_NO_RF=1'; exit 2
    fi
    exit 0
fi
mkdir -p "$output/enabled/classes" "$output/dependencies"
jar="$output/dependencies/jcardsim-3.0.5.11.jar"
expected=f6c3b6b8140401a47cf39d7b9dbfc052e381474c6c3b22018051024be1fca97c
if [[ ! -f "$jar" ]]; then
    temporary="$jar.partial.$$"
    trap 'rm -f "$temporary"' EXIT
    curl -fsSL --max-time 60 \
        https://repo.maven.apache.org/maven2/com/klinec/jcardsim/3.0.5.11/jcardsim-3.0.5.11.jar -o "$temporary"
    [[ "$(shasum -a 256 "$temporary" | cut -d ' ' -f 1)" == "$expected" ]] || { print -u2 'jCardSim checksum mismatch'; exit 1; }
    mv "$temporary" "$jar"
fi
[[ "$(shasum -a 256 "$jar" | cut -d ' ' -f 1)" == "$expected" ]] || { print -u2 'jCardSim checksum mismatch'; exit 1; }
java_root=${NFC_JAVA_HOME:-$(/usr/libexec/java_home -v 17)}
[[ -x "$java_root/bin/java" && -x "$java_root/bin/javac" ]] || { print -u2 'JDK 17 required'; exit 1; }
java_version=$("$java_root/bin/java" -version 2>&1)
[[ "$java_version" == *'version "17.'* ]] || { print -u2 'This research runner requires JDK 17'; exit 1; }
"$java_root/bin/javac" --release 8 -cp "$jar" -d "$output/enabled/classes" \
    "$module/Java/com/vphone/research/NFCNoRFCard.java"
sources=("$module"/VPhoneNFCResearch/*.swift)
if [[ "$action" == test ]]; then
    sources=("$module"/VPhoneNFCResearch/{NFCFraming,NFCSession,VSmartCardBackend,NFCResearchProbe}.swift "$module"/Tests/*.swift)
fi
xcrun swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
    -D "$nfc_experiment_flag" "${sources[@]}" -o "$output/enabled/$action"
if [[ "$action" == test ]]; then
    # Owned child processes exit on EOF; do not kill unrelated Java processes or VMs.
    "$output/enabled/test" "$java_root/bin/java" "$output/enabled/classes:$jar"
else
    "$output/enabled/build" "$java_root/bin/java" "$output/enabled/classes:$jar"
fi
