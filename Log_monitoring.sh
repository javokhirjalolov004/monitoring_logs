#!/usr/bin/env bash
# monitor_logs.sh
# Real-time log monitor:
# - Ajratib ko'rsatadi: ERROR, AUTH (authentication failures), SUDO
# - Bir yoki bir nechta log faylini qabul qiladi yoki tizim defaultlarini tekshiradi
#
# Ishlatish:
#   sudo ./monitor_logs.sh /var/log/auth.log /var/log/syslog
# yoki:
#   sudo ./monitor_logs.sh    # avtomatik mavjud loglarni tanlaydi

set -u
shopt -s nocasematch

# Ranglar
RED="\033[31m"; YELLOW="\033[33m"; CYAN="\033[36m"; GREEN="\033[32m"; MAGENTA="\033[35m"
BOLD="\033[1m"; RESET="\033[0m"

# Default fayllar (exist bo'lsa qo'shiladi)
default_files=(
  /var/log/auth.log
  /var/log/secure
  /var/log/syslog
  /var/log/messages
)

files=()
if [ "$#" -gt 0 ]; then
  # Argument sifatida berilganlarni ishlat
  for f in "$@"; do
    files+=("$f")
  done
else
  # mavjud default fayllarni qo'sh
  for f in "${default_files[@]}"; do
    [ -f "$f" ] && files+=("$f")
  done
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo -e "${RED}Xato:${RESET} Hech qanday log fayl topilmadi va argument berilmadi."
  echo "Masalan: sudo ./monitor_logs.sh /var/log/auth.log /var/log/syslog"
  exit 1
fi

# Filtrlar (case-insensitive)
is_error() {
  # "error" so'zi yoki "segfault" kabi aniq xatoliklar
  [[ "$1" =~ [Ee]rror ]] || [[ "$1" =~ segfault ]] || [[ "$1" =~ panic ]]
}
is_auth() {
  # keng tarqalgan auth xabarlari
  [[ "$1" =~ "failed password" ]] || [[ "$1" =~ "authentication failure" ]] \
    || [[ "$1" =~ "invalid user" ]] || [[ "$1" =~ "authentication error" ]] \
    || [[ "$1" =~ "authentication failure for" ]] || [[ "$1" =~ "pam_unix" ]] \
    || [[ "$1" =~ "invalid user" ]] || [[ "$1" =~ "failed Login" ]] \
    || [[ "$1" =~ "authentication failure" ]]
}
is_sudo() {
  # sudo: prefiksi yoki COMMAND=/etc/...
  [[ "$1" =~ "sudo:" ]] || [[ "$1" =~ "sudo:" ]]
}

# Start tails for each file in background, prefix lines with [filename]
for f in "${files[@]}"; do
  if [ ! -r "$f" ]; then
    echo -e "${YELLOW}Ogohlantirish:${RESET} $f ga o'qish ruxsati yo'q. Root bilan ishga tushiring (sudo) yoki ruxsat bering."
    continue
  fi

  # Har bir log uchun alohida tail -> sed orqali prefix qo'yamiz va background-da ishlatamiz
  tail -F -n0 "$f" 2>/dev/null | while IFS= read -r line; do
    printf "[%s] %s\n" "$(basename "$f")" "$line"
  done &
done

# PID larni saqlab, skript tugashi bilan tozalash
pids=$(jobs -p)
trap 'echo; echo "Stopping tails..."; kill $pids 2>/dev/null || true; exit 0' INT TERM EXIT

# Endi global inputni birlashtirib o'qish
# jobs -p bosqichida hamma background tail'lar ishga tushadi va ularning outputi shu yerga keladi
# Shu sababli standart inputni kutib turgan siklga kiramiz
while IFS= read -r rawline; do
  # rawline format: [filename] <original log line>
  # ajratish
  prefix=$(printf "%s" "$rawline" | awk '{print $1}')
  body=$(printf "%s" "$rawline" | cut -d' ' -f2-)

  # aniqlash
  if is_sudo "$body" || is_sudo "$rawline"; then
    # sudo satri
    printf "%b%s%20s%b %s\n" "$BOLD$MAGENTA" "[SUDO]" "$prefix" "$RESET" "$body"
  elif is_auth "$body" || is_auth "$rawline"; then
    # authentication failure
    printf "%b%s%20s%b %s\n" "$BOLD$YELLOW" "[AUTH]" "$prefix" "$RESET" "$body"
  elif is_error "$body" || is_error "$rawline"; then
    # general error
    printf "%b%s%20s%b %s\n" "$BOLD$RED" "[ERROR]" "$prefix" "$RESET" "$body"
  else
    # boshqa satrlar — agar kerak bo'lsa kommentariyalar bilan ko'rsatilsin (hozir default — juda kamroq chiqadi)
    printf "%b%s%20s%b %s\n" "$CYAN" "[INFO]" "$prefix" "$RESET" "$body"
  fi
done
