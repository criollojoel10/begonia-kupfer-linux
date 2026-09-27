#!/bin/sh
# Reconstruye /etc/mkinitcpio.conf con el conf de Kupfer y regenera el
# initramfs. Lo invoca 95-mkinitcpio-begonia.hook.
#
# Por que hace falta (fallo real del run 36305169422, trabajo previo):
# el paquete mkinitcpio deja /etc/mkinitcpio.conf con los hooks DE STOCK en su
# post_install, y 50-mkinitcpio-overwrite.hook (de mkinitcpio-kupfer-hooks)
# solo se dispara si cambian /etc/mkinitcpio.conf o /etc/kupfer/*. Con el conf
# de stock el initramfs se queda sin rootfsdetect, sin rootfsresize, sin
# firmwaresearchpath y sin los modulos del panel ni el firmware del tactil que
# van en FILES: pantalla en negro.
#
# Se ejecuta en la transaccion en la que entra device-mt6785-xiaomi-begonia, que
# es posterior a la del kernel porque el paquete depende de linux-mt6785. Asi da
# igual como pacman agrupe las transacciones.
#
# Todo se protege: si algo no esta, sale con 0 en vez de abortar la transaccion
# (un Exec de hook que falla tumba el build entero).
set -u

# 1) conf de Kupfer -> /etc/mkinitcpio.conf
if command -v mkinitcpio-overwrite >/dev/null 2>&1; then
    mkinitcpio-overwrite || echo "aviso: mkinitcpio-overwrite fallo" >&2
else
    echo "aviso: mkinitcpio-overwrite no esta instalado" >&2
fi

# 2) initramfs del kernel con ese conf
if [ -f /etc/mkinitcpio.d/linux.preset ]; then
    mkinitcpio -p /etc/mkinitcpio.d/linux.preset || {
        echo "aviso: mkinitcpio fallo" >&2
        exit 1
    }
fi

exit 0
