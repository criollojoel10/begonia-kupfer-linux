#!/bin/sh
# Reconstruye /etc/mkinitcpio.conf con el conf de Kupfer, regenera el
# initramfs y reconstruye aboot.img. Lo invoca 80-mkinitcpio-begonia.hook.
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
# El paso 3 (update-bootimg) es por si el hook 91-android-bootimg-updater.hook no
# llegara a dispararse en esa transaccion. /boot/aboot.img lleva dentro el
# initramfs, asi que un initramfs bueno con un aboot.img viejo sigue arrancando
# mal. Es idempotente: si el 91 se dispara despues, reconstruye lo mismo.
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
    # Ojo: esto sale con 0 aunque mkinitcpio falle a proposito. Un Exec de hook
    # que devuelve error puede tumbar la transaccion entera, y aqui no se trata
    # de tapar un initramfs roto: hay un check de CI que lo verifica y su error
    # dice mucho mas que "hook failed". Si el conf ya era el de Kupfer y otro
    # hook ya habia generado bien el initramfs, este fallo no es grave.
    mkinitcpio -p /etc/mkinitcpio.d/linux.preset || {
        echo "aviso: mkinitcpio fallo, el initramfs puede no ser el de Kupfer" >&2
    }
fi

# 3) aboot.img lleva por dentro el initramfs que hay ahora mismo en /boot
if [ -x /usr/bin/update-bootimg ]; then
    update-bootimg || echo "aviso: update-bootimg fallo" >&2
else
    echo "aviso: update-bootimg no esta instalado" >&2
fi

exit 0
