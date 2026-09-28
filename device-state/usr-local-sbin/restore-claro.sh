#!/bin/bash
# Red de seguridad: si la conexion activa en wlan0 NO es la Redmi, se vuelve a
# CLARO_JOEL. Se usa con systemd-run --user --on-active=N para no perder el
# acceso al movil mientras se prueba otro perfil.
#
# La comparacion acepta "Redmi Note 12 Pro 5G w0", que es el nombre del perfil
# UNICO que puede estar activo en wlan0. Con igualdad exacta contra un nombre
# distinto, el rodapie se derrubaba a si mismo y te dejaba sin wifi.
# El perfil "w1" no hace falta en el case: va atado a wlan1 por interface-name,
# y el awk de arriba ya filtra por $2=="wlan0", asi que nunca puede aparecer aqui.
act=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null \
      | awk -F: '$2=="wlan0"{print $1}')
{
  echo "=== restore-claro: $(date) ==="
  echo "  conexion activa en wlan0: '${act:-ninguna}'"
  case "$act" in
    "Redmi Note 12 Pro 5G"|"Redmi Note 12 Pro 5G w0")
      echo "  la Redmi esta conectada: NO se toca nada" ;;
    *)
      echo "  se vuelve a CLARO_JOEL"
      nmcli con up CLARO_JOEL ;;
  esac
  nmcli -f DEVICE,STATE,CONNECTION dev status
} >> /var/log/restore-claro.log 2>&1
