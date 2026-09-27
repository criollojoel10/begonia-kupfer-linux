#!/bin/sh
# Encciende el wifi interno de MediaTek en begonia (MT6785).
#
# El stack vendor no tiene un "starter" de userspace: el nodo /dev/wmtWifi lo
# crea wmt_drv (connectivity/common) y escribirle '1' llama a
# mtk_wcn_wmt_func_on(WMTDRV_TYPE_WIFI), que enciende connsys, arma el WFSYS y
# lanza el probe del gen4m => aparece wlan0. Ese nodo es una reconstruccion
# minima del wmt_chrdev_wifi.c del kernel vendor, que no esta en ningun arbol
# de fuentes disponible.
#
# El orden importa:
#   1. mtk-vendor-btif  -> platform_driver "mediatek,btif" (btif@1100c000)
#   2. wmt_drv          -> crea /dev/wmtWifi y el core WMT
#   3. wlan_gen4m       -> registra el probe del WLAN
#   4. write '1'        -> wmt_dev_set_hif_btif() + func_on(WIFI)
# El 1 tiene que ir antes del 4 porque el propio write llama a
# wmt_dev_set_hif_btif() para registrar el BTIF como transporte STP; si el
# modulo no esta cargado, stp_init se queda sin hif info.
#
# Los platform_device (wifi@18000000, consys@18002000, btif@1100c000) ya
# existen desde of_platform_populate, asi que con modprobe basta: los
# platform_driver se enlazan solos.
#
# Los blobs los pide por request_firmware() de /usr/lib/firmware/mediatek/.
# Si el kernel no puede cargarlos, func_on falla y aqui se ve el dmesg.

set -e

log() { echo "mediatek-wifi: $*"; }

# wmt_drv primero, sin esperar: el nodo /dev/wmtWifi lo crea ese modulo, asi
# que esperarlo sin cargarlo es esperar 30 s a algo que no va a pasar. Se
# cargan en el orden del stack (btif -> wmt_drv -> wlan_gen4m), no en el que
# toca el nodo: ver la nota de arriba.
if ! modprobe wmt_drv; then
	log "ERROR: no se pudo cargar wmt_drv (sin el no hay /dev/wmtWifi)"
	exit 1
fi
if ! modprobe mtk-vendor-btif 2>/dev/null; then
	log "AVISO: no se pudo cargar mtk-vendor-btif; el WMT se queda sin HIF btif"
fi

# El nodo aparece al cargar wmt_drv, pero puede tardar si el dispositivo UFS no
# ha woken todavia.
i=0
while [ ! -e /dev/wmtWifi ]; do
	i=$((i + 1))
	if [ "$i" -gt 30 ]; then
		log "ERROR: /dev/wmtWifi no aparece"
		exit 1
	fi
	sleep 1
done

if ! modprobe wlan_gen4m; then
	log "ERROR: no se pudo cargar wlan_gen4m"
	exit 1
fi

# El nodo pide el caracter suelto, no una cadena: printf, no echo.
if printf 1 > /dev/wmtWifi; then
	log "func_on(WIFI) pedido"
else
	log "ERROR: el write a /dev/wmtWifi fallo"
	exit 1
fi

# Da un poco de margen al firmware y comprueba si aparecio la interfaz.
n=0
while [ "$n" -lt 20 ]; do
	if [ -d /sys/class/net/wlan0 ]; then
		log "wlan0 presente"
		ip link show wlan0 2>/dev/null | sed 's/^/  /' || true
		exit 0
	fi
	n=$((n + 1))
	sleep 1
done

log "AVISO: /dev/wmtWifi acepto el write pero wlan0 no aparece todavia"
dmesg 2>/dev/null | grep -iE "wmt|connac|gen4m|wlan" | tail -20 | sed 's/^/  /' || true
exit 0
