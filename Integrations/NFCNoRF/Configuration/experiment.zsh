# Single opt-in build condition. Undefined/0 by default, including Debug builds.
# The build runner applies this independently to Swift and the Java source set.
typeset -r nfc_experiment_flag=VPHONE_EXPERIMENTAL_NFC_NO_RF
typeset -r nfc_experiment_enabled=${VPHONE_EXPERIMENTAL_NFC_NO_RF:-0}
