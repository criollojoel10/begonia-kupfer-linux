# Estado del begonia: lo que hay que reponer si se flashea `userdata`

La imagen de Kupfer no trae nada de esto, y **flashear solo `boot` no lo toca**, así que mientras
no se flashee `userdata` esto no hace falta. Está aquí para que quede en git y sea reproducible.

Recogido del begonia real el 28-09-2026 con el run `36359217206` ya instalado.

| Fichero de aquí | Va en el móvil en | Notas |
|---|---|---|
| `NetworkManager/system-connections/*.nmconnection` | `/etc/NetworkManager/system-connections/` | 4 perfiles, modo `600`, propiedad `root` |
| `dbus-1-services/org.freedesktop.secrets.service` | `/usr/share/dbus-1/services/` | override de D-Bus, **no** es una unidad de systemd |
| `usr-local-sbin/restore-claro.sh` | `/usr/local/sbin/`, modo `755` | red de seguridad del wifi |

## Lo que hay que poner a mano: las contraseñas

**Este repo es público**, así que los `psk=` están cambiados por `AQUI_VA_TU_CLAVE`. Las
contraseñas de `CLARO_JOEL`, `Redmi Note 12 Pro 5G` y `SKYLIFE_ALEJANDRA_5G` no se han subido
a ningún sitio. Al reponer los perfiles, sustituye ese valor por la clave real de cada red.

## Los masks de gnome-keyring no son ficheros

Son symlinks a `/dev/null`, y git no los representa. Van en `~/.config/systemd/user/`, **no** en
`/etc/systemd/user/`:

```sh
mkdir -p ~/.config/systemd/user
ln -sf /dev/null ~/.config/systemd/user/gnome-keyring-daemon.service
ln -sf /dev/null ~/.config/systemd/user/gnome-keyring-daemon.socket
systemctl --user disable --now gnome-keyring-secrets.service
```

Ojo: `/etc/systemd/user/sockets.target.wants/gnome-keyring-daemon.socket` sí existe y sigue
apuntando a la unidad real de `/usr/lib/systemd/user/`. No molesta, porque el mask de
`~/.config/systemd/user/` tiene prioridad, pero por eso `find` parece encontrar gnome-keyring
"activo" si solo se mira `/etc`.

## El `PATH` de opencode

En `~/.bashrc`, y **también** en `~/.bash_profile` antes del `source ~/.bashrc`, porque
`~/.bashrc:6` corta la ejecución en shells no interactivas y por eso `opencode` no aparecía
conectándose por SSH:

```sh
export PATH="$HOME/.opencode/bin:$PATH"
```

## Lo que no está aquí, a propósito

- **El monedero de KWallet.** `/home/joel/.local/share/kwalletd/Default keyring.kwl` (2872 B, con
  espacio en el nombre), más `Default keyring_attributes.json` y `keyring.salt`. Sigue cifrado con
  una contraseña y **no se ha probado** que se pueda abrir. Hay display manager
  (`/etc/systemd/system/display-manager.service` → `plasma-mobile.service`, que existe), pero en
  todo el sistema **no hay ningún `pam_*kwallet*`**: ni `/usr/lib/security/pam_kwallet.so` ni
  `/etc/pam.d/` con algo de kwallet, así que no hay PAM que conteste al prompt. Lo que quedaría
  es dejarlo sin contraseña, aceptando claves en claro.
- **Las claves SSH.** `~/.ssh/authorized_keys` y `~/.ssh/id_ed25519` no se suben por definición.
  Sin `authorized_keys` no hay acceso por Tailscale ni por USB, y el móvil queda inaccesible sin
  pantalla.
- **El fichero original de gnome-keyring**, guardado solo en el móvil en
  `/root/org.freedesktop.secrets.service.gnomekeyring.bak`:

  ```ini
  [D-BUS Service]
  Name=org.freedesktop.secrets
  Exec=/usr/bin/gnome-keyring-daemon --start --foreground --components=secrets
  ```

## Comprobación rápida después de reponer

```sh
pgrep gnome-keyring                 # no debe salir nada
systemctl --user is-enabled gnome-keyring-daemon.service   # masked
pgrep ksecretd                      # debe salir
nmcli con show | grep -c wifi        # 4
grep -l 'pmf=1' /etc/NetworkManager/system-connections/*.nmconnection | wc -l   # 4
```

Sobre el `pmf=1` y por qué el síntoma era `no secrets` en vez de un fallo de asociación, está en
[la sección del wifi del README raíz](../README.md#agregar-una-red-wifi-el-pmf-importa).
