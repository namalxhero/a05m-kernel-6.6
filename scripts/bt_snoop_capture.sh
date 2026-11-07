#!/system/bin/sh
# bt_snoop_capture.sh — MediaTek Bluetooth HCI snoop dump capture
#
# What this does:
#   The MTK Bluetooth driver keeps a small ring buffer of recent HCI
#   traffic (commands, events, ACL/ISO data) in kernel memory. Writing
#   "dump btsnoop" to its fw_log device node tells it to print that
#   buffer into the kernel log (dmesg) as [btmtk_info] lines. This
#   script triggers that dump, pulls the matching lines out of dmesg,
#   and saves them to a plain text file.
#
# What this is NOT:
#   A live packet capture. The buffer only holds the last ~30 entries
#   per traffic type, so each run gives you a short recent snapshot,
#   not a continuous trace. Run it right after the Bluetooth activity
#   you care about, or use -w to poll repeatedly.
#
# Usage (as root, e.g. from Termux with `su`):
#   sh bt_snoop_capture.sh              # one snapshot -> ./btsnoop_<timestamp>.log
#   sh bt_snoop_capture.sh -o FILE       # choose the output path
#   sh bt_snoop_capture.sh -w            # watch mode: dump+save every 5s until Ctrl+C
#   sh bt_snoop_capture.sh -w -i 10      # watch mode with a custom interval (seconds)

set -eu

OUT=""
WATCH=0
INTERVAL=5

while [ $# -gt 0 ]; do
    case "$1" in
        -o) OUT="$2"; shift 2 ;;
        -w) WATCH=1; shift ;;
        -i) INTERVAL="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,24p' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [ "$(id -u 2>/dev/null || echo 1)" != "0" ]; then
    echo "This needs root. Run it as: su -c 'sh $0 $*'" >&2
    exit 1
fi

# The device node name depends on how the BT driver was built; try the
# known candidates in order and use the first one that exists.
NODE=""
for cand in /dev/fw_log_bt /dev/multi_fw_log_bt /dev/stpbtfwlog /dev/stpbt_multi_fwlog; do
    if [ -e "$cand" ]; then
        NODE="$cand"
        break
    fi
done

if [ -z "$NODE" ]; then
    echo "Could not find the BT fw_log device node under /dev." >&2
    echo "The Bluetooth driver may not be loaded, or the node uses a name this script doesn't know." >&2
    echo "Try: ls /dev | grep -i fw_log   (then re-run with that name added to the script)" >&2
    exit 1
fi

echo "Using device node: $NODE" >&2

dump_once() {
    out_file="$1"
    # Trigger the dump into the kernel log.
    echo "dump btsnoop" > "$NODE" 2>/dev/null || {
        echo "Write to $NODE failed (need root, or driver busy)." >&2
        return 1
    }
    sleep 0.3
    {
        echo "# bt_snoop_capture.sh snapshot"
        echo "# device node: $NODE"
        echo "# captured: $(date)"
        echo "#"
        dmesg | grep -E '\[btmtk_info\] (\*\*\* Dump|\[.*time\()'
    } > "$out_file"
    echo "Saved: $out_file ($(wc -l < "$out_file") lines)" >&2
}

if [ "$WATCH" = "1" ]; then
    echo "Watch mode: dumping every ${INTERVAL}s. Ctrl+C to stop." >&2
    n=0
    while true; do
        n=$((n + 1))
        f="${OUT:-btsnoop_watch}_$(date +%Y%m%d_%H%M%S)_${n}.log"
        dump_once "$f" || true
        sleep "$INTERVAL"
    done
else
    f="${OUT:-btsnoop_$(date +%Y%m%d_%H%M%S).log}"
    dump_once "$f"
fi
