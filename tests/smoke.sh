#!/usr/bin/env bash
# Dependency-free (other than openssl) interface smoke tests.
# Uses stub QEMU/virt-fw-vars and fake firmware blobs. Does NOT test real UEFI boot.
set -Eeuo pipefail
LAB="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/sb-lab"
TEST="$(mktemp -d)"
trap 'rm -rf -- "$TEST"' EXIT
mkdir -p "$TEST/bin" "$TEST/keys" "$TEST/w"
for part in PK KEK DB DB2 DBX; do
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TEST/keys/$part.key" -out "$TEST/keys/$part.pem" -days 1 -subj "/CN=$part test" >/dev/null 2>&1
done
truncate -s 2097152 "$TEST/OVMF_CODE_4M.secboot.fd"
truncate -s 131072 "$TEST/OVMF_VARS_4M.fd"
cat > "$TEST/bin/qemu-system-x86_64" <<'EOQ'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$MOCK_QEMU_ARGS"
EOQ
cat > "$TEST/bin/virt-fw-vars" <<'EOV'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$MOCK_VARS_ARGS"
input=''; output=''; printed=0
while (($#)); do
    case "$1" in
        --input) input="$2"; shift 2;;
        --output) output="$2"; shift 2;;
        --print) printed=1; shift;;
        *) shift;;
    esac
done
if [[ -n "$output" ]]; then cp "$input" "$output"; fi
if ((printed)); then echo 'SetupMode=0, SecureBoot=1 (MOCK)'; fi
EOV
chmod +x "$TEST/bin"/*
export OVMF_CODE="$TEST/OVMF_CODE_4M.secboot.fd" OVMF_VARS_TEMPLATE="$TEST/OVMF_VARS_4M.fd"
export SB_LAB_STATE_DIR="$TEST/w" QEMU_BIN="$TEST/bin/qemu-system-x86_64"
export MOCK_QEMU_ARGS="$TEST/args_qemu" MOCK_VARS_ARGS="$TEST/args_vars" PATH="$TEST/bin:$PATH"
"$LAB" init --pk "$TEST/keys/PK.pem" --kek "$TEST/keys/KEK.pem" --db "$TEST/keys/DB.pem" --db "$TEST/keys/DB2.pem" --dbx "$TEST/keys/DBX.pem" >/dev/null
openssl x509 -inform DER -in "$TEST/w/esp/KEYS/DB.cer" -noout -subject >/dev/null
"$LAB" enroll-offline > /dev/null
test -s "$TEST/w/OVMF_VARS.fd.before-offline-enrollment.bak"
test "$(grep -Fc -- '--add-db-cert' "$TEST/args_vars")" -eq 2
test "$(grep -Fc -- '--add-dbx-cert' "$TEST/args_vars")" -eq 1
printf 'Signed EFI sample\n' > "$TEST/hello.efi"
"$LAB" boot --efi "$TEST/hello.efi" --no-kvm >/dev/null
grep -q 'smm=on' "$TEST/args_qemu"
grep -q 'if=pflash' "$TEST/args_qemu"
grep -q 'file=fat:rw:' "$TEST/args_qemu"
test "$(cat "$TEST/w/esp/EFI/BOOT/BOOTX64.EFI")" = 'Signed EFI sample'
truncate -s 1048576 "$TEST/mydisk.qcow2"
"$LAB" boot --disk "$TEST/mydisk.qcow2" --no-kvm >/dev/null
grep -q 'format=qcow2' "$TEST/args_qemu"
grep -q 'snapshot=on' "$TEST/args_qemu"
test ! -e "$TEST/w/esp/EFI/BOOT/BOOTX64.EFI"
printf 'iso' > "$TEST/example.iso"
"$LAB" boot --iso "$TEST/example.iso" --no-kvm >/dev/null
grep -q 'media=cdrom' "$TEST/args_qemu"
"$LAB" status > /dev/null
"$LAB" reset --yes > /dev/null
test -s "$TEST/w/esp/KEYS/DB.cer"
if "$LAB" keys --pk "$TEST/keys/PK.key" --kek "$TEST/keys/KEK.pem" --db "$TEST/keys/DB.pem" >/dev/null 2>&1; then
    echo 'FAIL: accepted private key as certificate' >&2
    exit 1
fi
printf 'PASS: CLI, PEM -> DER, separate db/dbx, offline VARS command, EFI/disk/ISO launch, reset, invalid input\n'
