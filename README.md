# Kupfer Linux for Xiaomi Redmi Note 8 Pro (begonia)

Port: **pmOS (Alpine) → Kupfer Linux (Arch)** para Xiaomi Redmi Note 8 Pro (`xiaomi-begonia`,
SoC MediaTek **MT6785**). **Primer dispositivo MediaTek soportado por Kupfer** (a 2026-09-13 la
página oficial lista 10 dispositivos en `dev` y 5 en `main`, **todos Qualcomm**:
msm8916/8953/sdm670/sdm845).

Kupfer: *"to Arch what postmarketOS is to Alpine"* — derivada de Arch Linux ARM, infraestructura
heredada de pmOS (`deviceinfo`, `kupferbootstrap`), boot vía Android boot.img (`aboot`).

Base elegida: rama **`dev`** de `gitlab.com/kupfer/packages/pkgbuilds`, no `main`. Motivo: `main` no
tiene el flavour `flavour-plasma-mobile` ni el split de paneles, que es justamente lo que se quiere
flashar. `dev` es la rama donde upstream desarrolla, así que este port va a corde con lo que la
comunidad.mergea primero.

---

## Estado

**Build verde y verificado en el begonia real.** Último run `36361060222` (commit
`0f5ce7b`, 28-09-2026 00:08→00:59 UTC), flavour `plasma-mobile`: 25 pasos, todos
verdes. El run anterior `36359217206` (commit `11637f4`, 23:35→00:31 UTC) es el
primer build con la pila de batería y también salió verde entero. Artifacts
`kupfer-begonia-plasma-mobile`, 4562 MB y 4559 MB, ambos expiran el 2026-10-05.

| Etapa | Estado |
|---|---|
| Investigación (arquitectura Kupfer + datos del device) | ✅ |
| Investigación de precedentes MTK / no-Qualcomm en Kupfer | ✅ |
| PKGBUILDs de device / kernel / firmware | ✅ |
| Parche `update-bootimg.sh` (header v2 + recovery_dtbo) | ✅ |
| Toolchain de cruce en el build (lo que faltaba) | ✅ |
| `mkbootimg` con la división entera arreglada (sin esto no sale `aboot.img`) | ✅ |
| Build de la imagen en GHA (base `dev`, 25 steps, ~55 min) | ✅ runs `36359217206` y `36361060222` verdes, ver [Notas de CI](#notas-de-ci) |
| `aboot.img` generado con el initramfs completo | ✅ |
| Los 5 módulos de panel/táctil dentro del initramfs | ✅ comprobado en CI |
| Firmware de novatek dentro del initramfs (faltaba) | ✅ |
| Stack MediaTek interno compilando (`wmt_drv`, `wlan_gen4m`, `mtk-vendor-btif`) | ✅ |
| Firmware MediaTek en `/usr/lib/firmware` (estaba en `/usr/mediatek/`) | ✅ |
| Los 7 blobs MediaTek **dentro de la imagen**, no solo en el paquete | ✅ comprobado en CI |
| Encendido automático del wifi interno (`mediatek-wifi.service`) | ✅ `ExecStart` y symlink comprobados en CI |
| **Fuel gauge GM30 del PMIC MT6359** (`battery`) | ✅ 10 parches, run `36359217206` verde, [medido en el device](overlay/linux/mt6785/README.md#qué-está-verificado-y-qué-no) |
| **ccache** (nunca había cacheado nada) | ✅ 3 bugs arreglados, `Verify ccache actually filled` en verde |
| Bluetooth interno | ❌ falta el driver HCI: el BTIF sí está y es el mismo bus que el wifi ([detalle](#el-bluetooth-interno-falta-el-driver-hci)) |
| Flasheo y verificación en device | ✅ flasheado solo en `boot`, [verificado](#flasheo-solo-en-boot-sin-tocar-userdata) |

## Investigación: no hay ningún port MediaTek que nos preceda

Se revisó el estado real del proyecto antes de escribir nada, para saber si existía una guía:

- **10 dispositivos** en `dev` y **5** en `main` (página oficial, generada 2026-09-13), **todos
  Qualcomm**: msm8916, msm8953, sdm670, sdm845. En el árbol de `pkgbuilds` son 9 paquetes
  `device-*` más 3 `-common` de apoyo.
- De ~100 merge requests, **cero de MediaTek**.
- De ~61 branches del repo de pkgbuilds, **ninguna de MediaTek**.
- Lo único no-Qualcomm son 2 drafts de **Exynos** (MR 159 / 162, Nexus 10), **cerrados sin
  mergear**. El motivo declarado en el hilo son problemas de **armv7h**, no el SoC: begonia es
  `aarch64`, así que esa razón no aplica.

Conclusión: **no hay guía previa, somos de verdad el primer port MTK de Kupfer.** El build con más
probabilidad de fallar es este, no por culpa del MediaTek en sí sino porque nadie recorrió antes
los mismos pasos. Contacto para dudas: Matrix, espacio `#kupfer-community`.

## Contexto del device

- pmOS edge vivo, kernel `6.16.4` vendored (`mt6785-mainline/linux` fork), systemd.
- **UFS** `59.6G` = `/dev/sdc` (47 particiones GPT; `sdc46` = userdata 52.3G), microSD `mmcblk0` 29G, zram swap.
- Rootfs montado en loop: `/dev/loop0` = `/dev/sdc46` (sector 4096), `loop0p1` = `/boot` (ext2, 480M),
  `loop0p2` = `/` (ext4, 51.8G). — Esquema idéntico al de Kupfer (imagen `msdos`: p1 boot + p2 root
  dentro de `userdata`).
- **deviceinfo** (de pmaports): header_version 2, dtb `mediatek/mt6785-xiaomi-begonia.dtb`,
  `recovery_dtbo /boot/empty.dtbo`, offsets base 0x40078000 / kernel 0x8000 / ramdisk 0x07c08000 /
  second 0xbff88000 / tags 0x0bc08000 / dtb 0x0bc08000, pagesize 2048, `rootfs_image_sector_size=4096`.
- Kernel cmdline obligatoria: `bootopt=64S3,32N2,64N2`.
- Táctil: variante **Tianma** ya confirmada en pmOS 6.16.4 vía **swap de firmware**
  (`nt36672a_begonia_tianma.bin.zst` bajo el nombre csot) — ver commit del port.
- WiFi/BT SoC: precisa rebuild con rama `begonia-conn-wifi`.

## Dependencias del port (rama `dev`)

PKGBUILDs nuevos (repos de Kupfer):

| PKGBUILD | Repo | Notas |
|---|---|---|
| `device/device-mt6785-xiaomi-begonia` | `device/` | cargo del deviceinfo pmOS a commit fijo |
| `linux/linux-mt6785` | `linux/` | kernel `mt6785-mainline/linux`, Image.gz + dtbs |
| `firmware/mt6785-xiaomi-begonia` | `firmware/` | blobs conectividad MTK + novatek + rtl |

Sobre el parche a `boot/android-bootimg-updater`: hace falta, y hace falta más de lo que parecía.
`dev` sí trae el branching por `header_version` en `update-bootimg.sh`, pero **no menciona `dtbo` en
absoluto** (0 coincidencias en todo el repo), así que la rama header v2 construye el bootimg sin
`--recovery_dtbo`. El overlay añade ese flag. Detalle en "El overlay del boot updater" más abajo.

### Gaps detectados

1. Begonia exige **header v2** (DTB separado + `--recovery_dtbo /boot/empty.dtbo`).
   `dev` sí trae el branching por `header_version` en `update-bootimg.sh`, pero **no soporta
   `--recovery_dtbo` en absoluto** (0 coincidencias de `dtbo` en todo el repo). Hace falta parche,
   y además hace falta el fichero `empty.dtbo`. Ver "El overlay del boot updater" más abajo.
2. Kernel cmdline `bootopt=64S3,32N2,64N2` → `deviceinfo_kernel_cmdline`.
3. DTB path → `deviceinfo_dtb="mediatek/mt6785-xiaomi-begonia"`.
4. Módulos de display/táctil en el initramfs. Los cinco existen como `=m` en el config de
   pmaports, así que el initramfs los lleva solo con declarar
   `deviceinfo_modules_initfs` (los tomamos del `modules-initfs` de pmaports, no los repetimos a
   mano): `boot/mkinitcpio-kupfer-hooks/mkinitcpio-overwrite.sh` prepende
   `deviceinfo_modules_initfs` a `MODULES=` de `/etc/mkinitcpio.conf` antes de que corra el
   `mkinitcpio` del hook `90-linux.hook`. El `mkinitcpio.conf.d/xiaomi-begonia.conf` del device
   se deja como red de seguridad, no como mecanismo.
5. `vbmeta` (flags=2) + `erase dtbo`: Kupfer no los flashea — pasos fastboot manuales extra.
6. Primer SoC MTK: no hay stack modem (igual que pmOS mainline, sin modem funcional).
7. Firmwares: `mediatek/` conectividad (7 blobs), `novatek/nt36672a_begonia_tianma.bin`, y
   `rtl_bt/rtl8821c_*` + `rtlwifi/rtl8192eu_nic.bin` para los dongles del hub.
8. **WiFi interno MediaTek (gen4m) desactivado a propósito.** `wlan_gen4m.ko` llama a
   `wireless_send_event()`, que solo se compila con `CONFIG_WEXT_CORE`; sin esa opción
   modpost aborta el kernel con `ERROR: modpost: "wireless_send_event" [...] undefined!`.
   El WiFi del hub (`rtl8xxxu`, `mt76`) no depende de ese stack, así que la imagen no debe
   depender de él. Ver `overlay/linux/mt6785/extra_config` para reactivarlo.
   Comprobado: con `CONFIG_WEXT_CORE=y` el símbolo resuelve y el kernel compila entero.

### El overlay del boot updater: dos trampas, y ninguna era visible

Sin esto begonia no arranca, y los dos fallos son silenciosos por construcción:

**a) La ruta del overlay estaba mal.** `cp -r src dst/` crea `dst/<basename de src>`. Con el
directorio del overlay llamado `boot-android-bootimg-updater` el fichero aterrizaba en
`boot/boot-android-bootimg-updater/`, una ruta que kupferbootstrap no conoce. El overlay
*parecía* aplicado y no lo estaba. Renombrado a `boot/android-bootimg-updater`, que es como se
llama en `kupfer/packages/pkgbuilds`, donde el `cp` fusiona encima del paquete real (y conserva
el `.hook` y el `.install` de upstream).

**b) El prebuilt le ganaba.** `boot-android-bootimg-updater` no está en `BASE_LOCAL_PACKAGES`
ni en la lista de `cmd_build`: llega por `--syncdeps`. `image build` pasa `try_download=True` a
`check_package_version_built()`, que compara `pkgver-pkgrel` contra disco/repo y, si no está,
**descarga el prebuilt** `boot-android-bootimg-updater-0.5-1-aarch64.pkg.tar.xz` de
`prebuilts/…/aarch64/boot/`. Descargado y verificado: su `update-bootimg` **no** trae el
`--recovery_dtbo`. El overlay nunca se construía.

Solución: subir `pkgrel` a `2` en el PKGBUILD overlaid. El nombre deja de coincidir con el del
prebuilt, así que se construye localmente. El paso de overlays verifica además que el
`pkgrel=2` sigue ahí, que el script contiene `recovery_dtbo`, y que el `empty.dtbo` tiene el
sha256 esperado — porque un overlay que se pierde en silencio no falla, y es exactamente lo que
pasó.

### `empty.dtbo`: por qué va versionado y no se genera

El bootloader de begonia arranca con header v2 y sin un recovery dtbo vacío no localiza el dtbo
de recovery. pmaports lo resuelve generando el dtbo en su APKBUILD con
`mkdtboimg create`, que viene del subpackage de Alpine `android-tools-mkdtboimg`. En Arch no
existe `mkdtboimg` ni en los repos ni en la AUR, y el prebuilt de Kupfer `mkbootimg-git-r254…`
solo trae `mkbootimg` y `unpack_bootimg`. `mkbootimg` sí acepta `--recovery_dtbo <path>`; lo que
faltaba era el fichero — y que ese `mkbootimg` no reventara al usarlo, que es un segundo bug; ver
[§2 de "Los dos cuelgues del port"](#2-mkbootimg---recovery_dtbo-y-la-división-entera-de-python-2).

Así que el binario de 136 bytes va versionado en el overlay del device. Es el que genera
pmaports, con el magic **MediaTek** `0xd7b7ab1e` (AOSP usa `0xd7b7caf1`) — de ahí que se
reutilicen los bytes exactos en vez de reinventar el formato. Se regenera con:

```sh
echo '/dts-v1/; / {};' | dtc -I dts -O dtb -o empty.dtb
mkdtboimg create empty.dtbo empty.dtb   # -> 136 bytes, sha256 f72e1df5…
```

### El panel Tianma: el nombre CSOT del DTB tiene que contener el binario Tianma

Este es el detalle que hace que el táctil funcione o no, y **no aparece en ningún log**: el panel
enciende igual, la imagen se ve bien, y el touch responde con los ejes cruzados.

El DTB de la rama 6.16 (la única que hay para begonia) solo conoce la variante CSOT:

```
panel@…        compatible = "xiaomi,begonia-csot-nt36672a", "novatek,nt36672a"
touchscreen@0  firmware-name = "novatek/nt36672a_begonia_csot.bin"
```

El driver del táctil (`novatek-nvt-ts-spi`) lee `firmware-name` del device tree y se lo pasa tal
cual a `request_firmware()`. No hay forma de que el kernel pida el otro binario. En una unidad
**Tianma** hay que servir el binario Tianma bajo el nombre CSOT:

```
md5sum nt36672a_begonia_tianma.bin.zst = 7d67c2e9167f1a630576c177c1b831f7  (53321 B)
md5sum nt36672a_begonia_csot.bin.zst  = 52f5e96f84fbdd6cbed2e98790a202df  (53731 B)
```

Por eso `firmware/mt6785-xiaomi-begonia` declara `_panel=tianma` y copia el binario Tianma encima
del nombre CSOT al empaquetar. El `mkinitcpio.conf.d/xiaomi-begonia.conf` mete los dos ficheros en
el initramfs, que es de donde los carga el driver (los módulos de panel y táctil van en
`earlymodules`).

Con `_panel=csot` se reconstruye para una unidad CSOT sin tocar nada más.

El CI comprueba el **md5 del contenido** del fichero con nombre CSOT, no que el fichero exista:
los dos nombres existen siempre, así que un `ls` no detectaría nada. En pmOS el mismo bug está
documentado y la corrección manual está confirmada en hardware sobre este móvil.

## El toolchain de cruce: el fallo que nobody de upstream se llega a ver

Este es el hallazgo que rompió el build, y merece su propia sección porque **el error que sale no
señala la causa**.

Al compilar un paquete `_mode=cross` con `crosscompile=true`, `packages/build.py:729-737` calcula

```python
cross_deps = deps + CROSSDIRECT_PKGS + [f"{GCC_HOSTSPECS[native][arch]}-gcc"]
native_chroot.try_install_packages(cross_deps)
```

y lo pasa **sin `allow_fail=False`**. El default de `try_install_packages`
(`chroot/abstract.py:535-558`) es `allow_fail=True`, así que el `error: target not found:
aarch64-unknown-linux-gnu-gcc` se traga en silencio y el build sigue sin compilador. Lo que sale,
muchos minutos después, es:

```
make[1]: aarch64-unknown-linux-gnu-gcc: No such file or directory
scripts/Kconfig.include:40: C compiler 'aarch64-unknown-linux-gnu-gcc' not found
make[2]: *** [scripts/kconfig/Makefile:85: olddefconfig] Error 1
```

Tres cosas se suman para que ese nombre no exista:

1. El paquete `aarch64-unknown-linux-gnu-gcc` **no existe**. Lo que existe es el pkgbuild local
   `cross/aarch64-unknown-linux-gnu-bin` (los binarios x-tools de ArchlinuxARM, 14.1.1,
   `arch=(x86_64)`), que lo *proporciona* vía `provides=`.
2. **Ningún PKGBUILD de todo el repo lo declara como dependencia** (grep included), así que la
   cadena de dependencias de `image build` nunca lo mete.
3. El `pacman.conf` del chroot (`chroot/abstract.py:420-447`) solo lleva `kupfer_local` + los repos
   de kupfer como `file://` + core/extra. El repo kupfer `cross` remoto no está, y el repo local
   `x86_64/cross` lo crea `init_local_repo()` con un `db.tar.xz` **de cero**.

Upstream no se entera porque **todos** sus paquetes aarch64 llegan como prebuilt de
`gitlab.com/kupfer/packages/prebuilts` y no se compilan nunca. Nosotros sí compilamos cuatro
(kernel, firmware, device, boot updater), y en cuanto uno es `_mode=cross` reventamos.

El fix es el primer `script:` de la CI de upstream
(`kupfer/packages/pkgbuilds/.gitlab-ci.yml`), que la documentación nunca menciona:

```sh
kupferbootstrap -v packages build --arch 'x86_64' $(echo cross/*/PKGBUILD | xargs -n1 dirname | xargs)
```

`--arch x86_64` es **obligatorio**: sin él `packages/cli.py:116` usa la arch del device (aarch64) y
el paquete se rechaza por `arch=(x86_64)`. Con `--arch x86_64` y siendo el host x86_64,
`foreign_arch=False` (`config.runtime.arch` es el arch del host, `os.uname().machine`, no el del
device), así que se compila en el chroot x86_64 nativo: solo descarga y reempaqueta. El paso del
workflow comprueba después que el `.pkg.tar.xz` ha aparecido en el repo local, porque un
`try_install_packages` que falla en silencio no falla en ninguna parte.

## Makedepends y config del kernel: lo que el entorno de build no trae

El contenedor de kupferbootstrap es `FROM archlinux:base-devel` más lo que instala su Dockerfile
(python, git, rsync, parted, android-tools, openssh…). `base-devel` no trae `zstd`, ni `openssl`,
ni `libelf`. El config de pmaports usa tres cosas que los necesitan:

| Qué | Por qué | Arreglo |
|---|---|---|
| `openssl` | `CONFIG_MODULE_SIG_ALL=y` genera una clave RSA al vuelo y firma cada módulo con `scripts/sign-file`, que llama a `openssl` | `openssl` en `makedepends` |
| `libelf` | `CONFIG_UNWINDER_ORC=y` (defconfig de arm64) hace que `tools/objtool` compile `<gelf.h>` y enlace `-lelf`. El APKBUILD de pmaports equivalente lleva `elfutils-dev` por lo mismo | `libelf` en `makedepends` |
| `CONFIG_MODULE_COMPRESS_ZSTD=y` | `modules_install` invoca el binario `zstd`; sin él, `Error 127` y el kernel no se empaqueta | desactivado en `extra_config` |

No comprimir módulos es además lo que hace el propio kernel de Arch, y tiene una ventaja aquí: el
initramfs no tiene que descomprimir `.ko.zst` en un UFS lentísimo. Si alguna vez se quiere volver a
comprimir, el sitio es `makedepends`, no el config.

`perl` también está en `makedepends` por `scripts/` y por `objtool`.

## Los dos cuelgues del port, y por qué el log no dice nada

El run `36244913341` es el primero que llegó al final: kernel compilado (`Image.gz` a las 13:46:03,
`mt6785-xiaomi-begonia.dtb` a las 13:46:39), initramfs generado, 756 paquetes instalados. Y aun así
se pasó **45 minutos sin una sola línea de log** antes de que lo cancelaran. La causa no era la que
parecía, y el log de GHA tampoco ayuda: mientras el job está `in_progress`, el endpoint
`/actions/jobs/<id>/logs` devuelve un parcial **congelado** (byte a byte idéntico entre llamadas) y
`/actions/runs/<id>/logs` da 404 hasta que el run termina. Para diagnosticar estos dos cuelgues
hubo que cancelar y leer el ZIP completo.

### 1. `click.confirm` de la clave SSH: el cuelgue de verdad

`kupferbootstrap/src/kupferbootstrap/net/ssh.py:115`, en `copy_ssh_keys()`:

```python
keys = find_ssh_keys()          # ~/.ssh/id_*
if len(keys) == 0:
    logging.warning("Could not find any ssh key to copy")
    create = click.confirm("Do you want me to generate an ssh key for you?", True)
```

`click.confirm` **lee de stdin**. En un runner de GHA no hay nadie tecleando, así que el proceso se
queda bloqueado para siempre. En local es imposible verlo: cualquier dev tiene ya un `~/.ssh/id_*`,
así que nunca se llega al `confirm`. El log lo dice con todas las letras:

```
(31/31) Updating the vlc plugin cache...
WARNING: Could not find any ssh key to copy
##[error]The operation was canceled.        <- 45 minutos después
```

Detrás de esa línea debería venir el `Running post-install CMDs` de `install_rootfs`
(`image/image.py:441`), y no viene.

**Arreglo** (`build.yaml`, paso *Build image*): generar una clave ed25519 sin passphrase antes de
invocar kupferbootstrap, con `find_ssh_keys()` dar con ella y no pisar nunca el `confirm`. Como
efecto secundario, la clave pública acaba en el `authorized_keys` del usuario de la imagen, que es
justo lo que se quiere.

El `if [ -f ... ]` hace el paso idempotente, por si algún día se cachea el `~/.ssh`.

### 2. `mkbootimg`: `--recovery_dtbo` y la división entera de Python 2

Este no fue un cuelgue sino un **fallo silencioso**, y es el más importante de los dos: sin
`aboot.img` la imagen no arranca, y pacman se come el error del hook y sigue como si nada.

```
(21/31) Updating aboot.img...
Generating new aboot.img with initramfs /boot/initramfs-linux.img
Traceback (most recent call last):
  File "/usr/bin/mkbootimg", line 303, in main
    img_id = write_header(args)
  File "/usr/bin/mkbootimg", line 152, in write_header
    args.output.write(pack('Q', get_recovery_dtbo_offset(args)))
struct.error: required argument is not an integer
error: command failed to execute correctly
```

El paquete que trae `mkbootimg` no es `android-tools`, sino **`mkbootimg-git`**, un pkgbuild de Kupfer
(`main/mkbootimg-git`) fijado al commit `ba2684e` (r254) de
`android.googlesource.com/platform/system/tools/mkbootimg`. Ese commit es anterior al porteo a Python
3, y su `get_number_of_pages()` sigue usando `/`:

```python
def get_number_of_pages(image_size, page_size):
    return (image_size + page_size - 1) / page_size        # float en Python 3
```

`get_recovery_dtbo_offset()` multiplica eso por el `pagesize` y lo pasa a `struct.pack('Q', …)`, que
rechaza floats. O sea: **cualquier device que pase `--recovery_dtbo` con este `mkbootimg` revienta**,
y begonia es el primero que lo pasa. Las versiones actuales de AOSP ya usan `//`, así que no es un
bug de Copper sino de la instantánea que upstream tiene fijada.

Obsérvese el detalle del encadenado: `write_header()` falla **antes** de `write_data()`, así que el
error salta con el `aboot.img` sin escribir. Nada en el log de pacman indica que la imagen esté
incompleta; los 31 hooks salen como `success`.

**Arreglo** (`overlay/main/mkbootimg-git/PKGBUILD`): el mismo PKGBUILD que upstream más dos cambios,
`pkgrel=3` (para ganar al prebuilt publicado, que es `-2`) y un `sed` de esa única línea, con un
`grep -qF` de guarda que hace fallar el build si upstream cambia el `_commit` y la línea ya no está.
El `sed` no cambia el comportamiento en ningún otro caso: `get_number_of_pages()` no se usa en
ningún otro sitio de ese fichero.

Lo correcto a medio plazo es subir el `_commit` de upstream a una revisión ya portada; no se ha
hecho aquí porque no se puede comprobar el contenido de una revisión concreta sin acceso a
`android.googlesource.com` (desde este entorno responde 503), y en vez de subir el pin a ciegas se
parchea la línea, que es verificable.

## Una nota sobre las firmas (investigado, luego descartado)

Estaba sobre la mesa parchear el `SigLevel` de los chroots a `Never` (el `generator.py:257` pone
`SigLevel = Required DatabaseOptional` y el keyring de los chroots solo lo puebla el `.INSTALL` de
`archlinux-keyring`; `archlinuxarm-keyring` no se instala en ninguno). Con `--noconfirm`, que
kupferbootstrap pasa siempre, un prompt `Import PGP key …?` se respondería solo y libalpm se
iría a WKD por HTTPS. **Era una hipótesis razonable y equivocada**: la fase `checking keys in keyring`
del run tardó ~2 minutos para los 756 paquetes y terminó sin Drama. El cuelgue de 45 minutos
empezaba *después*, en `install_rootfs`, y era el `click.confirm` de arriba.

Se deja el dato porque sigue siendo un riesgo latente real para quien componga un repo con claves
expiradas, no porque haga falta parchear nada aquí. La solución de upstream sería exponer `siglevel`
en el TOML o hacer `pacman-key --populate` al crear los chroots; hoy la `PacmanSection` del esquema
solo tiene `parallel_downloads`, `check_space` y `repo_branch`. Para el que se lo pregunte: los repos de Kupfer
ya son `SigLevel: Never` en `repos.yml` y sus prebuilts van sin firmar (su `.sig` da 404).

## Los cuatro `error: command failed to execute correctly` que son ruido

El build del run `36249822052` terminó en verde, pero el log tiene cuatro
`error: command failed to execute correctly` y eso obliga a decidir si son ruido o no. Todos
son del **build chroot** (`/chroots/build_aarch64`), ninguno del rootfs, y ninguno toca la imagen
que se arranca:

| Hook | Mensaje | Por qué es inocuo |
| --- | --- | --- |
| 6/8 y 7/8 | `==> ERROR: module not found: 'crypto_lz4'` | El `install/systemd` de mkinitcpio hace `map add_module 'crypto-lzo' 'crypto-lz4'`, y el config de pmaports trae `CONFIG_CRYPTO_LZO=y` pero `# CONFIG_CRYPTO_LZ4 is not set`. Aquí se usa el `/etc/mkinitcpio.conf` **de stock** (el que trae el paquete), no el de Kupfer. |
| 8/8 | `No deviceinfo found at /etc/kupfer/deviceinfo` | En el build chroot todavía no está instalado el paquete `device`, que se construye después. |
| 18/31 | `Error connecting: Could not connect` | PackageKit necesita D-Bus, que no existe en un chroot. |

El initramfs que se mete en `aboot.img` es el de la **rootfs**, y ese sí sale limpio, con los hooks
que escribe el hook `50-mkinitcpio-overwrite` (el paquete `mkinitcpio-kupfer-hooks` sustituye el
`/etc/mkinitcpio.conf` de stock por uno que no incluye `systemd`):

```
(17/31) Updating linux initcpios...
  -> Running build hook: [base] [firmwaresearchpath] [udev] [autodetect] [modconf]
                         [block] [rootfsdetect] [filesystems] [keyboard] [rootfsresize] [fsck]
  -> Early uncompressed CPIO image generation successful
==> Initcpio image generation successful
```

Por eso el paso de *Build image* busca señales positivas (`Initcpio image generation successful`,
`Generating new aboot.img`) y solo un patrón inconfundible (`struct.error`, que es nuestro bug de
`mkbootimg`). Los cinco módulos de panel y táctil se comprueban sobre el initramfs extraído, no
sobre el log.

## El initramfs no es un fichero comprimido: es dos segmentos

`gzip -dc /boot/initramfs-linux.img` responde `not in gzip format` sobre un initramfs
**perfectamente bueno**, y por eso el check de módulos daba por ausentes cinco módulos que sí
estaban dentro (run `36253998953`).

La causa está en el `mkinitcpio` que instala Arch: si hay ficheros ya comprimidos dentro
(`.gz`, `.xz`, `.zst`…), los mueve al *early root* para no comprimirlos dos veces
(`mkinitcpio:340-358`) y luego concatena ese CPIO **sin comprimir** delante del archivo comprimido
(`mkinitcpio:385-399`):

```
[ CPIO temprano sin comprimir ][ flujo gzip con el resto ]
```

Es el formato que espera el desempaquetador del kernel (acepta varios segmentos seguidos), y el
log lo delata con una línea que parece menor:

```
==> Creating gzip-compressed initcpio image: '/boot/initramfs-linux.img'
  -> Early uncompressed CPIO image generation successful
```

El check del workflow salta el CPIO temprano (buscando su entrada `TRAILER!!!`), localiza la
firma gzip a partir de ahí y descomprime con `zlib`, en vez de `gzip -dc`. Es lo mismo que hace
`lsinitcpio --early` / `skip_early_img`, pero sin depender de `bsdtar` ni de instalar `mkinitcpio`
en el runner (que es Ubuntu, no Arch).

## La tabla de particiones vive en sectores de 4096 bytes

`image.py:losetup_rootfs_image()` crea el loop device con `losetup -f -b 4096 -P`, y `parted` escribe
encima una tabla msdos **interpretada en 4096 bytes por sector**. Cualquiera que vuelva a abrir la
imagen con los 512 por sector por defecto (un `losetup` normal, un `sfdisk`, un `dd` calculado con
los offsets que devuelva) lee una tabla de particiones equivocada y no encuentra nada. En el primer
run con éxito, la extracción de `aboot.img` con `dd` + `debugfs` falló por eso, no por permisos.

Por eso el paso de *Build image* monta con `losetup -f --show -b 4096 -P`, y de ahí salen
`aboot.img` (94 MB) e `initramfs-linux.img` como artefactos propios: permiten reflashear solo el
boot sin volver a bajar 7 GB.

## El wifi interno de MediaTek (wmt_drv + wlan_gen4m) y el Bluetooth

El Note 8 Pro no necesita dongle para el wifi: el MT6785 tiene su propio stack (`gen4m` + `wmt`),
que en pmOS ya compila y en Kupfer quedó **apagado a propósito** por un símbolo mal puesto. Esta
sección explica el estado real de esa parte.

### El símbolo que lo apagaba era invisible

`wlan_gen4m.ko` llama a `wireless_send_event()`, y `cfg80211` solo lo exporta con
`CONFIG_CFG80211_WEXT`. Lo que se había puesto era `CONFIG_WEXT_CORE=y`, que **no existe como
símbolo de kconfig**: es un símbolo *oculto* (`def_bool y depends on CFG80211_WEXT || WIRELESS_EXT`).
`make olddefconfig` lo borra sin decir nada, y el build del kernel muere mucho después, en `modpost`:

```
ERROR: modpost: "wireless_send_event" [.../wlan_gen4m.ko] undefined!
```

`CONFIG_CFG80211_WEXT=y` es el fix (idéntico al que hizo falta en pmOS). Con eso el stack se
compila: `wmt_drv.ko`, `wlan_gen4m.ko` y `mtk-vendor-btif.ko`.

De paso, el `extra_config` tenía los mismos símbolos mal escritos que en pmOS, y kconfig los
descartaba en silencio: `CONFIG_MT76` no existe (es `MT76_CORE`, y `MT76_USB` depende de él, así que
se caía en cascada), y `MT76X0U`/`MT76X2U` van con la `x` en minúscula.

### El firmware estaba en `/usr/mediatek/`, donde nadie lo ve

`firmware-mt6785-xiaomi-begonia` movía los directorios del repo a `$pkgdir/usr/`, así que los blobs
acababan en `/usr/mediatek/`. `request_firmware()` solo busca en `/usr/lib/firmware`, con lo que
`func_on(WIFI)` no iba a encontrar nada. Ahora van a `/usr/lib/firmware/{mediatek,novatek}/`.

El inventario que pide el driver está completo en ese repo (`mt6785-mainline/firmware`, el mismo
commit que usa pmaports):

| Fichero | Quién lo pide |
|---|---|
| `WMT_SOC.cfg` | `wmt_conf.h` (fallback `WMT.cfg`) |
| `soc1_0_patch_mcu_2a_1_hdr.bin` | `wmt_dev.c` |
| `soc1_0_ram_mcu_2a_1_hdr.bin` | `wmt_ctrl.c` |
| `soc1_0_ram_wifi_2a_1_hdr.bin` | `wmt_ctrl.c` |
| `soc1_0_ram_bt_2a_1_hdr.bin` | `wmt_ctrl.c` |
| `WIFI_RAM_CODE_soc1_0_2a_1.bin` | `connacConstructFirmwarePrio()` (gen4m) |

El `2a` del nombre no es casualidad: se compone como `<prefijo>_<CFG_WIFI_IP_SET=2><flavor><eco>.bin`
y `kalGetFwFlavor()` en `os/linux/plat/mt6785/plat_priv.c` devuelve `'a'`. Si el kernel pidiera otro,
se prueban en orden `..._2a_1.bin`, `..._2a_1`, `WIFI_RAM_CODE_soc1_0`, `WIFI_RAM_CODE_soc1_0.bin`.

Dos ficheros más del repo que **no son obligatorios**: `wifi.cfg` y `txpowerctrl.cfg`. No es que el
driver los pida y si no los encuentra siga sin error, es que **la tabla de fábrica ya viene
compilada** en el driver y el fichero solo la sobreescribe: `wlanGetConfig()` (`CFG_SUPPORT_CFG_FILE=1`)
hace antes `wlanCfgInit(prAdapter, NULL, 0, 0)`, y `txPwrCtrlLoadConfig()`
(`CFG_SUPPORT_DYNAMIC_PWR_LIMIT=1`) mete antes la lista con `txPwrCtrlGlobalVariableToList()`. Como
este paquete instala el directorio entero del repo, si el driver los pide, se los encuentra.

El EEPROM (`EEPROM_MT<chip_id>.bin`) tampoco se proporciona, y aquí sí es a propósito: si el driver no
lo encuentra cae al **modo eFuse**, que es lo normal en un móvil, porque la calibración está en el
eFuse del SoC y no en un fichero.

Los `.zst` no hay que descomprimirlos: el config base del kernel es el de pmaports y ya trae
`CONFIG_FW_LOADER_COMPRESS_ZSTD=y`.

### Encenderlo: no hay "starter", hay que escribir en un nodo

El kernel vendor arranca el wifi desde userspace con un launcher que no existe en ningún árbol de
fuentes. Lo que sí hay es `/dev/wmtWifi`, un nodo misc que crea `wmt_drv` (dentro,
`wmt_wifi_trigger.c`): escribir `'1'` llama a `mtk_wcn_wmt_func_on(WMTDRV_TYPE_WIFI)`, que enciende
connsys, arma el WFSYS y lanza el probe del gen4m → aparece `wlan0`.

Ojo con un malentendido fácil: ese `RUNTIME-UNPROVEN` **no dice que el driver no funcione en el
móvil**, y además no está en ningún fichero de este port. Está en el fichero que el fwport añade al
kernel para el trigger (`drivers/misc/mediatek/connectivity/common/common_main/linux/
wmt_wifi_trigger.c:16`), y es una nota para quien lo porte: *"compile/link verified only ... the
end-to-end bring-up has not been exercised on a device"*, que solo duda del **orden** del `func_on`.
Su commit es del 18/06 a las 02:27; los verificados en hardware, ese mismo día, a las 08:18
(`b8c1b8b5`) y las 09:25 (`0468921f`). Sencillamente no se actualizó el comentario. El MR de su
forward-port (`mt6785-mainline/linux` !2) dice con todas las letras que **`wlan0` escanea y se asocia
en 2.4 y 5 GHz, con DHCP y ping verificados en hardware**. El resumen está en
[El wifi: verificado por su autor, sin probar por nosotros](#el-wifi-verificado-por-su-autor-sin-probar-por-nosotros).

`device-mt6785-xiaomi-begonia` instala ahora `mediatek-wifi.service` (habilitada por symlink en
`multi-user.target.wants`) con este orden, que **importa**:

1. `mtk-vendor-btif` → su `platform_driver` enlaza con `btif@1100c000`
2. `wmt_drv` → crea `/dev/wmtWifi`
3. `wlan_gen4m` → registra el probe del WLAN
4. `printf 1 > /dev/wmtWifi` → `wmt_dev_set_hif_btif()` y luego `func_on(WIFI)`

El btif va primero porque el propio write llama a `wmt_dev_set_hif_btif()` para registrar el BTIF
como transporte STP: sin el módulo cargado, `stp_init` se queda sin hif info. Y es `printf` y no
`echo` porque el nodo lee **un** carácter.

Los `platform_device` (`wifi@18000000`, `consys@18002000`, `btif@1100c000`) ya existen desde
`of_platform_populate`, así que con `modprobe` basta. En el DTS de pmaports ya está todo (los 12
`reg` de consys en el orden que espera `consys_read_reg_from_dts`, la memoria reservada
`consys_reserved` de 4 MB y el `shared-dma-pool` `wifi_mem` de 3 MB); lo único que hay que
mantener apagado es `wmac@18000000`, porque colisiona con el stack.

`mtk-wifi-test.sh` (en la raíz del repo) es el script de diagnóstico para el móvil: comprueba
módulos, firmware, nodos, carga en ese orden, dispara el trigger y vuelca el `dmesg` relevante. Si
`wlan0` no aparece, su paso 8 vuelca además los ficheros de diagnóstico que el propio driver deja
en `/proc/driver` (`wmt_dbg`, `wmt_dump_info`, `wmt_aee`), que son los que dicen si el fallo es el
BTIF, el conn-MCU o el firmware. Ese volcado es la diferencia entre depurar a ciegas y saber por
dónde mirar.

### El wifi: verificado por su autor, sin probar por nosotros

Merece la pena ser preciso, porque "nunca se ha ejecutado" y "nadie lo ha ejecutado" son
afirmaciones muy distintas para este driver.

- **El driver funciona en este móvil, y lo verificó quien lo escribió.** El forward-port es el MR
  !2 de `mt6785-mainline/linux` (*"Draft: begonia (MT6785): conn/WiFi vendor forward-port"*): su
  descripción afirma que `wlan0` escanea y se asocia en 2.4 y 5 GHz, con DHCP y ping verificados
  en hardware. El historial encaja con eso: el commit `b8c1b8b5` ("Verified on hardware: this
  clears the 'no hif info' gate; STP/BTIF now activates") y los volcados de registros en vivo de
  `0468921f` son apuntes de bring-up, no teoría. Nosotros compilamos la punta de esa serie
  (`3a1ea76942`).
- **Fuera de ese bring-up, nadie ha probado este stack en un begonia.** El MR !2 no tiene ni un
  comentario y nadie ha contestado, así que no hay un segundo informe de nadie. Es un MR
  *cross-fork* (del fork del autor, `minorum/linux`, a `mt6785-mainline/linux`) y lleva desde junio
  de 2026 sin que nadie lo mueva, que es lo razonable para una importación de fabricante de ~545k
  líneas etiquetada como *"not proposing merge yet"*. Somos los primeros en llevarlo a Kupfer, y los
  primeros en probarlo en pmOS con este empaquetado.
- **Lo que queda abierto es el empaquetado, no el silicio**: que los módulos carguen en el orden
  que el driver necesita, que el firmware esté donde el driver lo busca y que el `1` se comporte
  como en el bring-up de su autor. Eso es justo lo que comprueba `mtk-wifi-test.sh`.

### El Bluetooth interno: falta el driver HCI

`mtk-vendor-btif.ko` compila y enlaza, pero **no registra ningún HCI**, así que BlueZ no tiene nada
a lo que conectarse. Y lo importante: **esto no es un problema de configuración**, no hay ningún blob
de firmware ni ningún servicio que lo arregle. Es que falta la pieza de código.

Lo que sí está, y es bastante:

- El móvil lleva el **mismo BTIF que usa el wifi que funciona**. El MCU de conectividad, el canal de
  control WMT y el transporte STP son un stack único, y en begonia el transporte STP vivo *es* el
  BTIF (todo el tráfico sale por `mtk_wcn_btif_write`).
- El nodo DT está en mainline y viene **habilitado por defecto**: `btif@1100c000`
  (`compatible = "mediatek,btif"`, tres rangos `reg`, IRQs 138/155/154, clocks `btifc`/`apdmac`) en
  `arch/arm64/boot/dts/mediatek/mt6785.dtsi`. Nuestro módulo lo enlaza, y el blob de BT que el
  stack de wifi ya carga (`soc1_0_ram_bt_2a_1_hdr.bin.zst`) es el suyo. `BGF_EINT`
  (`GIC_SPI 321`) también está cableado en el DTS de begonia.
- El firmware de BT del conn-MCU está en la imagen y el bus que lo transporta funciona.

Lo que falta es la **capa HCI**, es decir el driver que leería ese transporte y se lo entregaría a
BlueZ. Nada en `drivers/bluetooth/` consume el BTIF, y no hay ninguna llamada a `hci_register_dev()`
en todo `drivers/misc/mediatek/`. Por eso no existe `hci0`, se carguen los módulos como se carguen.

Los dos atajos que podrían parecerlo se descartan solos:

- `btmtkuart.c` es el único driver HCI de MediaTek del árbol, pero maneja un chip de BT **externo**
  por un UART de verdad (`mt7622`, `mt7663u`, `mt7668u`: SoCs de router; el móvil no lleva ninguno
  de esos chips integrado), y el `btif` del móvil no es un UART, así que la extensión de línea de
  comandos ni llega a activarse.
- El `userspace` vendor `mtk_bt_stack` no es redistribuible, y el shim 8250-BTIF al estilo vendor
  (`8250_btif` + `btmtkuart_hci`) se propuso en 2017 y nunca entró en mainline.

**Lo que sí funciona para BT: un dongle USB** (`btusb` con RTL8821C o similar), igual que el wifi
por dongle: los drivers de USB están en el `extra_config` y el soporte de BT (`CONFIG_BT_HCIBTUSB`)
está compilado. El blob `soc1_0_ram_bt` se queda en el paquete de firmware porque forma parte del
set que carga el bring-up de wifi, no porque sirva para algo hoy.

## Notas de CI

El build no se limita a "salir verde": hay cuatro pasos que comprueban cosas que solo se ven con el
móvil en la mano, porque si no el error aparece en el mejor caso a los diez minutos de encender la
pantalla.

1. **`Verify kernel modules and firmware in the image`** — lista el paquete del kernel ya
   construido (`bsdtar -tf`, sin arrancar nada) y exige los 3 `.ko` del stack MediaTek, los 21
   `.ko` de los dongles USB (ethernet, wifi, BT y serie) y los 5 del panel/táctil; y lista el
   paquete de firmware exigiendo los 8 blobs, incluido el **md5 del binario que hay bajo el nombre
   `csot`**: en una unidad Tianma tiene que ser el Tianma, y un simple `ls` no lo distingue
   porque los dos ficheros existen siempre.
2. **`Verify aboot.img header`** — lee la cabecera del `aboot.img` que sale del build y exige
   `header_version=2`, `recovery_dtbo_size=136` (el `empty.dtbo`), `page_size`, `header_size`, los
   tres payloads no vacíos, las direcciones de carga de pmaports (base `0x40078000` + offsets) y
   los cinco módulos de panel/táctil dentro de `earlymodules=` (que es una lista separada por
   comas, así que buscar `earlymodules=<mod>` no vale). Es el check que de verdad decide si el
   móvil arranca: el aboot de begonia rechaza un boot v0/v1 con DTB, y sin recovery dtbo no
   encuentra el override del panel. `unpack_bootimg` no viene en los runners, así que se parsea
   el layout AOSP a mano.
3. **`Verify the rootfs`** — monta la partición de la imagen final y mira, por separado, (a) el
   `FILES` que dejó el `mkinitcpio-overwrite` en `/etc/mkinitcpio.conf`, (b) los `.zst` de novatek
   en `/usr/lib/firmware/novatek/`, (c) el **md5** del que está bajo el nombre `csot`, (d) los
   nombres de paquete instalados, (e) los **7 blobs MediaTek dentro de la imagen** y que
   `firmware-mt6785-xiaomi-begonia` esté instalado, y (f) que la unidad del wifi interno esté en
   la imagen, que su `ExecStart` apunte a un fichero que existe y es ejecutable **dentro de ella**,
   y que el symlink de `multi-user.target.wants` esté.
4. **`List images`** — el boot fs tiene que caber en la partición `boot` de 64 MiB y traer dentro
   un `aboot.img` no vacío.

Los tres últimos existen por fallos reales, y los dos últimos por uno que es la razón de que este
puerto no se pueda dar por bueno solo porque la imagen compila:

- **(e)**: un paquete bien construido **no es lo mismo** que un paquete instalado. El subpaquete
  de firmware de conectividad se construía (766 KB) y no llegaba a la rootfs, y el síntoma —cero
  blobs en `/usr/lib/firmware/mediatek/`— solo se ve montando la imagen. Es el mismo fallo que
  tumbó la imagen de pmOS del run `36304158010` (allí por culpa de apk; aquí por la cache de
  `packages`).
- **(f)**: `ExecStart=/usr/lib/device-mt6785-xiaomi-begonia/mediatek-wifi.sh` mientras el PKGBUILD
  instalaba el script en `/usr/libexec/`. El servicio no podía arrancar jamás (`203/EXEC`), el wifi
  interno no se encendía nunca, y **nada de eso rompía el build**. Un `ExecStart` mal escrito es
  del todo invisible desde fuera: el paquete está, la unidad está, el symlink está.

Dos trampas que costaron un run cada una y que conviene no volver a pisar:

- `find "$PKGDIR" -name "$1-*.pkg.tar.*"` para localizar el paquete del kernel se queda con
  `linux-mt6785-headers-*`, porque el kernel genera las dos cosas y `"headers"` ordena antes que
  el número de versión. El paquete de cabeceras no tiene ningún `.ko` y el verify falla
  quejándose de 29 módulos que sí están. El nombre tiene que seguir a un **dígito** (`pkgver`
  siempre empieza por uno; un subpackage no).
- El nombre de un `.ko` no tiene por qué coincidir con el símbolo de kconfig: `rtl8150.ko` (no
  `r8150.ko`), `mt76-usb.ko` (con guion). Y el grep tiene que anclar (`/\.ko$`) para que un
  módulo compilado dentro del kernel no cuente como presente, porque no se puede `modprobe`.
- **La cache de `packages` de Actions no puede tener `restore-keys` por prefijo.** kupferbootstrap
  no reinstala desde cero: busca cada paquete en su repo local y, si el checksum encaja, lo da por
  bueno. Con `restore-keys` por prefijo, el run se colgaba los paquetes del último run verde
  aunque los PKGBUILD del overlay hubieran cambiado (nuestro `pkgver`/`pkgrel` no cambia en cada
  commit), y la imagen se construía con un paquete viejo. Pasó con el rename
  `firmware-mediatek-mt6785` → `firmware-mt6785-xiaomi-begonia`: el build creó el 0.1-3 nuevo y
  instaló el 0.1-2 viejo, sin los blobs de novatek, y el initramfs salió sin el firmware del
  táctil. La clave es ahora `hashFiles('overlay/**')` y sin `restore-keys`; `ccache` los conserva
  porque ahí sí interesa, y perder la cache de paquetes solo obliga a recompilar el kernel propio.
- **`FILES` de mkinitcpio va con `/lib/firmware`, no con `/usr/lib/firmware`.** mkinitcpio guarda
  cada elemento de `FILES` en el cpio **con la ruta que se le da**, y el cargador de firmware busca
  `/lib/firmware/updates*` y luego `/lib/firmware` (`fw_path()` en
  `drivers/base/firmware_loader/main.c`). Con `/usr/lib/firmware/...` el `.zst` acaba en
  `usr/lib/firmware/...` dentro del initramfs, donde nadie lo mira. Upstream usa
  `/lib/firmware/qcom/...` en sus device confs por el mismo motivo. Y con rutas explícitas en vez
  de un glob, porque `mkinitcpio-overwrite` sourcea los `.conf` en un orden en el que el paquete de
  firmware puede todavía no estar instalado y el glob se quedaría literal.
- **`ln -s` a `/etc/systemd/system/multi-user.target.wants/` no crea el directorio.** Es el fallo que
  tumbó el run `36301882701`: el paquete device habilitaba `mediatek-wifi.service` con un `ln -s`
  a un directorio que `install -Dm644` no había creado, y `package()` moría con
  `ln: failed to create symbolic link ... No such file or directory` →
  `==> ERROR: A failure occurred in package()`. Con `mkdir -p` antes, verde.
- **Un `.install` de makepkg no arregla nada en la imagen final.** La primera hipótesis para el
  `crypto_lz4` era regenerar el initramfs desde el `post_install` de `linux.install`, pero un
  `.install` solo lo ejecuta `makepkg`, nunca pacman en el target: en el chroot de build, además,
  no existen ni `/usr/bin/mkinitcpio-overwrite` ni `/etc/mkinitcpio.d/linux.preset` (el preset va a
  `$pkgdir`), así que es un no-op silencioso. Para la imagen final hace falta un hook de libalpm.
- **`/etc/mkinitcpio.conf` se degrada al de stock y nadie lo arregla.** `mkinitcpio` escribe su conf
  de stock en su `post_install` siempre, y `50-mkinitcpio-overwrite.hook` (de
  `mkinitcpio-kupfer-hooks`) solo corre si cambian `/etc/mkinitcpio.conf` o `/etc/kupfer/*`. Si la
  fragmentación de transacciones de pacman hace que `mkinitcpio` se reinstale en una transacción
  donde no se toca `/etc/kupfer/*`, el conf se queda con los hooks de Arch
  (`systemd microcode kms sd-vconsole…`) y el initramfs sale sin `rootfsdetect`/`rootfsresize` (no
  monta la rootfs), sin `firmwaresearchpath` y sin los módulos del panel ni el firmware del táctil de
  `FILES` ⇒ pantalla en negro. De ahí el hook `80-mkinitcpio-begonia.hook` del paquete device: se
  dispara en la transacción en la que entra el paquete, que es posterior al kernel porque es
  dependencia suya, y rehace el conf con `mkinitcpio-overwrite` y regenera el initramfs entero. Va
  en `80-` y no en `95-` a propósito: **`/boot/aboot.img` lleva dentro el initramfs** (lo empaqueta
  `update-bootimg`, que dispara `91-android-bootimg-updater.hook`), así que un hook que regenerase el
  initramfs *después* del `91` dejaría `aboot.img` con el initramfs roto de antes y el móvil
  arrancaría mal aunque `/boot/initramfs-linux.img` esté bien. Los hooks `PostTransaction` se
  ejecutan en orden alfabético de nombre de fichero, así que `80-` va antes que el `90-` y el `91-`.
  El check de CI "Verify the rootfs" lo verifica en la imagen.
- El `hook systemd` de mkinitcpio hace `map add_module 'crypto-lzo' 'crypto-lz4'`, y el config base
  de pmaports trae `CONFIG_CRYPTO_LZO=y` pero `CONFIG_CRYPTO_LZ4` apagado. Con el conf de stock eso
  es un `==> ERROR: module not found: 'crypto_lz4'` cada vez que se construye un initramfs en el
  chroot de build (no es fatal, pero grita). Por eso `CONFIG_CRYPTO_LZ4=m` en `extra_config`.
- **ccache no había cacheado nunca nada, por tres bugs independientes.** Los tres tenían que
  arreglarse a la vez; con uno solo arreglado sigue sin cachear.
  1. `generator.py:94` escribe `BUILDENV=(!distcc color !ccache !check !sign)`, así que el
     entorno de build descarta ccache aunque esté instalado en el chroot.
  2. El compilador es de cross y `/usr/lib/ccache` solo trae los shims de **host**. Aun así no se
     usan shims: un shim de ccache en el `PATH` se autoconfigura de forma no verificable, así que
     el override va en la línea de comandos de `make` (`CC="ccache ${CROSS_COMPILE}gcc"`,
     `HOSTCC="ccache gcc"`), sin envolver `LD`/`AR`/`NM`/`OBJCOPY`/`STRIP`.
  3. ccache 4.x escribe en `$HOME/.cache/ccache`, pero kupferbootstrap monta `$HOME/.ccache`
     (`chroot/build.py:183`). Con el directorio equivocado la caché se llena en un sitio que se
     descarta al acabar el run.

  El síntoma era delator: las entradas `ccache-*` del repo pesaban **273 B**, que es lo que pesa un
  marcador de directorio vacío. La premisa de que los runs antiguos eran rápidos por la caché era
  falsa: el mejor run medido (`36310845797`) tardó 39 min 13 s, con `Build image` en 28 min 52 s.

  El `PKGBUILD` hace `export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"`, guarda con `command -v`
  tanto `ccache` como `${CROSS_COMPILE}gcc` para no fallar en silencio, y acaba con `ccache -s`. El
  paso `Verify ccache actually filled` falla si el run deja menos de 100 ficheros, para que esto no
  vuelva a pasar inadvertido.
- **`${CROSS_COMPILE}` ya lleva la raya final.** Es `aarch64-unknown-linux-gnu-`, así que el
  compilador es `${CROSS_COMPILE}gcc`, **con** guion. `${CROSS_COMPILE%-}gcc` fue el bug del run
  `36360020474`.
- El paso `Upload artifacts` lleva `if: always()`. Sin eso, un `verify` mal escrito destruye los
  50 min de build sin dejar nada que debuggear.

El resto de notas de CI:

- El build usa el wrapper **Docker** de kupferbootstrap (`type = "docker"`): construye
  Arch packages con `makepkg`, que no existe en el runner Ubuntu (`type = "none"` →
  `makepkg: command not found`).
- `DOCKER_BUILDKIT=1` es obligatorio: el `Dockerfile` upstream usa `RUN --mount=type=bind`
  y `ADD --link`, que requieren BuildKit.
- `registry.gitlab.com/kupfer/kupferbootstrap` **no es pullable anónimamente** (302 → sign_in), así
  que el workflow construye la imagen antes de usarla. Eso calienta además las capas en la cache
  de BuildKit.
- Las invocaciones van envueltas en `script -qec` porque el wrapper hace `docker run -it`
  y los runners de Actions no tienen TTY (`the input device is not a TTY`).
- El TOML se valida contra el esquema de kupferbootstrap **antes** de arrancar el build, y con un
  chequeo de tipos extra: `Config.fromDict(validate=True)` no distingue `True` de `1` porque en
  Python `True` es un `int` válido, y ese agujero dejó pasar dos bugs de tipo seguidos
  (`clean_mode` como string, `parallel_downloads` como bool) que rompieron más tarde, dentro de
  pacman, con `invalid value for 'ParallelDownloads' : 'True'`.
- La documentación oficial (`kupfer.gitlab.io/kupferbootstrap/main/usage/`) **no menciona el paso de
  `cross/`**. La referencia de cómo se hace un build exitoso es el `.gitlab-ci.yml` de
  `kupfer/packages/pkgbuilds`, que es lo que se ha seguido aquí. En la doc sí está `packages check`
  como paso obligatorio de una contribución, y el MR debe decir qué funciona, qué no y qué no se
  probó.

## Lo que la doc oficial sí cubre (y lo que no)

Revisada entera antes de escribir los PKGBUILDs, por si existía un camino ya trillado:

- `usage/porting/` — device/kernel/firmware van en `device/`, `linux/`, `firmware/`. `_mode=host`
  por defecto; `_mode=cross` solo para kernels. `_nodeps=true` para paquetes que no deben arrastrar
  dependencias. `packages check` obligatorio. Solo hay bootloader `aboot`.
- `usage/quickstart/` — `config init` → `packages update` → `image build` → `image flash abootimg`
  && `image flash full userdata`.
- `usage/faq/` — `packages build [--force] [--arch $target_arch] <repo>/<pkgbase>`.
- `usage/install/` — wrapper `docker` si no estás en Arch (aquí obligatorio, no opcional).
- `cli/kupferbootstrap.image/` — `image build` usa repos locales y, para lo que falte, "required
  packages will be built or preferably downloaded from HTTPS repos". De ahí el `pkgrel=2` del boot
  updater: mientras el nombre coincida con el del prebuilt, gana el prebuilt.

De `usage/porting/` sale además que `packages build` acepta **rutas relativas al dir de
pkgbuilds** (`cross/crossdirect` es el ejemplo que dan), que es justo la forma que necesita el paso
del toolchain.

## Artefactos del build

- `aboot.img` → boot partition (`fastboot flash boot`)
- `image full` → `fastboot flash userdata` (sparse)

## Flasheo (tras build GHA exitoso)

```sh
# 1. Backup de la imagen pmOS actual (rollback)
# 2. En fastboot:
fastboot flash boot aboot.img
fastboot flash userdata begonia-kupfer.img   # sparse
fastboot flash vbmeta vbmeta.img             # flags=2
fastboot erase dtbo
fastboot reboot
```

> Kupfer no gestiona vbmeta/dtbo: los pasos extra son obligatorios y estándar en begonia.
> `vbmeta.img` = `avbtool make_vbmeta_image --flags 2 --padding_size 2048`.

### `fastboot` se carga la imagen entera en RAM: no flashees los 6,7 GB en crudo

El `fastboot` de AOSP (`load_sparse_file()`) hace `malloc(total_sz)` y lee el fichero **completo**
en memoria, tanto si es sparse como si no. En una máquina normal esto mata el proceso:

```
kupfer-flash.service: systemd-oomd killed 4 process(es) in this unit.
Main process exited, code=killed, status=9/KILL
Failed with result 'oom-kill'.
Consumed 22.790s CPU time over 27.175s wall clock time, 4.7G memory peak, 3.9G memory swap peak.
```

No es el OOM killer del kernel ni un límite de cgroup, es **`systemd-oomd`**, que mata por presión
de memoria en el slice del usuario aunque el cgroup tenga `memory.max=max`. Pasa igual con y sin
`-S 100M` (y `ManagedOOMPreference=avoid` tampoco lo evita), así que el culpable es el `malloc`, no
el flag. Por eso en pmOS nunca pasa: su imagen es de 1-2 GB y cabe de sobra.

La solución es **preconvertir la imagen** y flashear el `.simg`: con un fichero ya en formato sparse,
`fastboot` solo lee la cabecera e itera chunks, con lo que la memoria se queda en megabytes.

```sh
img2simg run2/mt6785-xiaomi-begonia-plasma-mobile-root.img root.simg   # 7,18 GB -> 6,02 GB
fastboot flash userdata root.simg        # SIN -S
```

Además, si el proceso te muere a mitad, lánzalo **fuera del cgroup de la terminal** (la pestaña de
Konsole mata sus hijos cuando se reinicia):

```sh
systemd-run --user --unit=kupfer-flash --collect \
  bash -lc './flash-final.sh --yes > flash-final.log 2>&1; echo "EXIT=$?" >> flash-final.log'
```

`flash-final.sh` valida tamaños y hashes, comprueba `LABEL=kupfer_root` (con `blkid`, que no
entiende sparse, sobre la imagen cruda) y, sin `--yes`, solo imprime el plan y sale con 0 sin tocar
nada.

## Flasheo solo en `boot`, sin tocar `userdata`

Es la vía para **actualizar el kernel conservando todo lo demás del móvil**: los perfiles de
NetworkManager, la clave SSH, el `$HOME`, el monedero. Es la que se usó para llevar la pila de
batería al begonia real, y se verificó entera antes de escribir una sola partición.

### Por qué no hace falta tocar `userdata`

Toda la pila de batería —los drivers compilados en el kernel y el DTB con
`mt6359_gauge`/`battery_manager`— va **dentro del `aboot.img`**, o sea dentro de la partición
`boot`. `userdata` no aporta nada a la batería.

Comprobado en el device antes de flashear:

| Comprobación | Resultado |
|---|---|
| Distribución real del almacenamiento | `/dev/sdc` = UFS interna (SKhynix) con GPT de 59,6 GB. **`sdc46` = 52,3 GiB, ext4, `LABEL=kupfer_root`, montada en `/`** ⇒ esa es `userdata`. `mmcblk0` = 29 GB vfat = microSD. |
| Partición `boot` | **`sdc34`, 64 MiB, `PARTLABEL=boot`**. El `aboot.img` ocupa 27.924.480 B, cabe de sobra. |
| ¿El rootfs actual aguanta un kernel nuevo? | Sí. El kernel que corría y el nuevo son ambos **6.16.4**, y **`CONFIG_MODVERSIONS` está apagado** (0 módulos con sección `__versions`): no se validan CRCs de símbolos, así que los `.ko` del rootfs siguen siendo válidos. |
| ¿El initramfs nuevo es una regresión? | No. El viejo y el nuevo son estructuralmente idénticos (2 zstd, 2 gzip, 14 cpio) y **ninguno lleva los `.ko` del panel**. En el viejo sus 2 apariciones de la cadena `.ko` son bytes sueltos dentro de datos comprimidos, no nombres de fichero. El `earlymodules=` del cmdline no depende del initramfs. |
| `vbmeta` actual | `Algorithm: NONE`, **`Flags: 2`** (verificación desactivada), **`Descriptors: (none)`**. Al no tener descriptores no verifica nada ⇒ **no hace falta reflashearlo** aunque cambie el kernel. |
| Rollback | `fastboot fetch` existe en platform-tools 33 ⇒ se puede guardar el `boot` actual exacto antes de escribir. |

### Los comandos

Deja el móvil **enchufado al cargador**: es la primera vez que arranca el gauge nuevo y lo que más
se vigila es la lógica de batería baja.

```sh
cd /home/joel/work-begonia/kupfer-img

FB=/home/joel/work-begonia/tools/pt33/platform-tools/fastboot
```

`$FB` es un alias solo para abreviar. Si tu shell es `fish`, escribe `$FB` como
`set FB /home/joel/work-begonia/tools/pt33/platform-tools/fastboot`; si no, sustituye cada
`$FB` por la ruta entera.

```sh
# 1. En fastboot: reserva el boot actual. OBLIGATORIA, el rollback depende de esto.
$FB devices
$FB fetch boot boot-actual.img
sha256sum boot-actual.img

# 2. Un solo comando de escritura. Sin --wipe, sin userdata, sin recovery, sin dtbo.
sha256sum -c <<< "397051a671ec2e08c282a9a528ea05c48decf05c68f3981df3e7bb5b18337490  aboot-bateria.img"
$FB flash boot aboot-bateria.img
$FB reboot
```

`fetch` está en platform-tools 33 y también en el 37 del sistema (`/usr/bin/fastboot`), así que
da igual cuál de los dos uses. Si `fetch` no devolviera nada, para ahí: sin esa reserva no se
sigue.

### Rollback

```sh
$FB flash boot boot-actual.img
$FB reboot
```

### Verificación tras arrancar

```sh
ssh joel@100.112.2.11 '
dmesg | grep -iE "mt6359-gauge|mtk_battery|battery-manager|mt6397|fgauge|bm_update_status"
ls /sys/class/power_supply/
for f in capacity voltage_now current_now temp status; do
  printf "%-12s %s\n" "$f" "$(cat /sys/class/power_supply/battery/$f)"
done'
```

Lo que salió en el begonia real el 28-09-2026, con el run `36359217206`:

- 8 dispositivos del PMIC en sysfs, gauge leyendo corriente real
  (`fgauge:[get_ptim_current]ptim current:10821`) y `bm_update_status` cada 10 s con
  `soc:4 vbat:3843`.
- **Cero `probe deferral` y cero `probe fail`** en todo el `dmesg`.
- `capacity=4` con `voltage_now=3840000` µV, `temp=270`, `charge_full=2946000`,
  `cycle_count=1`. El SOC por culombios y el voltaje coinciden, así que la tabla sin calibrar no
  está fallando. Detalle y lo que sigue sin medirse, en
  [el README del overlay](overlay/linux/mt6785/README.md#qué-está-verificado-y-qué-no).

### Descargar el artefacto: `gh api` no sirve, `aria2c` sí, con un rodeo

La descarga son 4,5 GB. `gh api` va a una sola conexión: 2,18 GB en 5 minutos. Con `aria2c`
`-x16` baja 4,46 GB en 25-30 s, **pero no se le puede pasar `--header "Authorization: Bearer ..."`**:
la API responde 302 hacia `productionresultssa9.blob.core.windows.net`, `aria2c` reenvía el header
al host destino y Azure lo rechaza con `errorCode=24 -> Authorization failed`.

El rodeo es resolver la redirección primero y darle a `aria2c` la URL ya firmada, que no necesita
header:

```sh
URL=$(curl -s -o /dev/null -D - -H "Authorization: Bearer $TOKEN" \
      "https://api.github.com/repos/OWNER/REPO/actions/runs/RUN/artifacts/ID/zip" \
      | awk 'tolower($1)=="location:"{print $2}' | tr -d '\r')
aria2c -x16 -s16 -k1M --file-allocation=none --auto-file-renaming=false -o artifact.zip "$URL"
```

Esa URL lleva su SAS con caducidad (`se=`), así que hay que **re-resolverla en cada reintento**; no
vale guardarla.

Del artifact solo se usan dos ficheros, y uno no:

```
aboot.img                                          27.924.480   -> sí, va a boot
mt6785-xiaomi-begonia-plasma-mobile-root.img    7.180.648.448   -> no, solo si flasheas userdata
mt6785-xiaomi-begonia-plasma-mobile-boot.img        62.914.560   -> no, el boot va dentro de aboot.img
mt6785-xiaomi-begonia-plasma-mobile-full.img     7.390.363.648   -> no, es el rootfs con el GPT delante
initramfs-linux.img                                 17.150.743   -> no, ya va embebido en aboot.img
```

Si aun así hay que flashear `userdata`, el roundtrip sparse se verificó byte a byte:
`img2simg` da 6,69 GiB → 5,74 GB con magic `3aff26ed`, y `simg2img` recupera el sha256
`197d98518c3ace9e8647dbdf26428f41a7018687fc41d5402483a2fba92bfb83` idéntico al original. Ojo:
`simg2img` contra `/tmp` falla con ENOSPC, hay que hacerlo contra disco real.

## Agregar una red wifi: el `pmf` importa

Un AP mixto WPA2/WPA3 rechaza la asociación de un cliente que no soporte MFP (802.11w), y el
código de estado 802.11 que devuelve es el **16**. En `wpa_supplicant` sale así:

```
Trying to associate with SSID 'Redmi Note 12 Pro 5G'
CTRL-EVENT-ASSOC-REJECT  bssid=00:00:00:00:00:00 status_code=16
```

Lo que confunde es que la asociación **falla antes** de necesitar la clave, y NM pide el secreto
después para reintentar; como no hay agente disponible, el síntoma que se ve es `no secrets` y
parece un problema de llavero. **No lo es: la `psk` nunca llega a usarse.** El arreglo es
`wifi-sec.pmf=1` (MFP capaz, no obligatorio), que funciona tanto con APs WPA2 puras como con las
mixtas. Probado en el device: `pmf=1` conecta, `pmf=3` da `association took too long`, y `sae` no
aporta nada aquí.

Dos trampas de NetworkManager que costaron tiempo:

- Dos perfiles de conexión con el **mismo `id`** (aunque los ficheros y los UUID sean distintos) no
  se distinguen: `nmcli con up "Redmi Note 12 Pro 5G w0"` responde `unknown connection`. Hay que
  tirar de `nmcli con up uuid <uuid>`.
- `nmcli con mod ... wifi-sec.pmf 1` **no persiste** el cambio, porque NM no escribe la clave si
  cree que es el valor por defecto. Hay que editar el keyfile directamente y recargar con
  `nmcli con reload`.

Los cuatro perfiles del device quedan con `key-mgmt=wpa-psk`, `pmf=1` y `psk` en el fichero.

## La imagen no trae `org.freedesktop.secrets.service`

La imagen solo trae `org.kde.secretservicecompat.service` → `Exec=/usr/bin/ksecretd` y
`org.kde.kwalletd6.service`. **No hay ningún `org.freedesktop.secrets.service`**, ni en
`/usr/lib/systemd/user/` ni en `/usr/share/dbus-1/services/`.

No es un problema heredado: la imagen **tampoco trae `gnome-keyring`**, que era lo que secuestraba
`org.freedesktop.secrets` con un llavero vacío. El begonia que corre ahora sí tiene el override,
porque se creó a mano; flasheando solo `boot` sobrevive, pero si algún día se flashea `userdata`
hay que rehacerlo. El fichero que hace falta es simplemente un `Exec=/usr/bin/ksecretd` con el
nombre `org.freedesktop.secrets.service`, en `/usr/lib/systemd/user/`, para que D-Bus enrute ahí las
peticiones de secretos de NetworkManager.

## Build en GitHub Actions

Ver `.github/workflows/build.yaml`. Runs bajo demanda (`workflow_dispatch`).
Los builds pesados van a GHA (evita OOM en la máquina local).

## El overlay es un espejo del árbol de `pkgbuilds`

`overlay/` no es un directorio plano de paquetes: reproduce **exactamente** las rutas
del repo `gitlab.com/kupfer/packages/pkgbuilds` (rama `dev`):

```
overlay/linux/mt6785/                    -> linux/mt6785/              (nuevo, kernel)
overlay/firmware/mt6785-xiaomi-begonia/   -> firmware/mt6785-xiaomi-begonia/  (nuevo, blobs)
overlay/device/device-mt6785-xiaomi-begonia/ -> device/device-mt6785-xiaomi-begonia/ (nuevo, device)
overlay/boot/android-bootimg-updater/    -> boot/android-bootimg-updater/  (modifica upstream)
overlay/main/mkbootimg-git/              -> main/mkbootimg-git/            (modifica upstream)
```

Gracias a eso el MR es literalmente:

```sh
git clone -b dev https://gitlab.com/kupfer/packages/pkgbuilds
cp -r overlay/* packages/pkgbuilds/
```

y no puede divergir de lo que se ha construido en el CI. Los dos directorios que
*modifican* paquetes de upstream llevan solo los ficheros que cambian
(`PKGBUILD` y `update-bootimg.sh`); el resto lo aporta el checkout porque
`cp -r` fusiona encima.

Los paquetes que se añaden al repo son `linux-mt6785` (kernel), `firmware-mt6785-xiaomi-begonia`
(conectividad + panel) y `device-mt6785-xiaomi-begonia` (deviceinfo, initramfs, autostart
del stack MTK). Los otros dos son parches a paquetes que ya existen y que **necesitan un
pkgrel más alto** para que se construyan en vez de cogerse el prebuilt:

| paquete | upstream | aquí | por qué |
| --- | --- | --- | --- |
| `boot-android-bootimg-updater` | `0.5-1` | `0.5-2` | su `update-bootimg.sh` no sabe pasar `--recovery_dtbo` |
| `mkbootimg-git` | `r254.ba2684e-2` | `r254.ba2684e-3` | su `mkbootimg` calcula mal el tamaño en cabecera v2 (división entera) |

`kupferbootstrap packages check --ci-mode` pasa limpio sobre los cinco paquetes. El CI lo corre
igual (paso homónimo en `.github/workflows/build.yaml`), que es lo que exige la guía de porting.
El comprobador es un formateador estricto (orden de variables, comillas, indentación de listas) y
no necesita el chroot, así que también se puede lanzar en local contra un checkout:

```sh
cp -r overlay/* /ruta/a/pkgbuilds/
/ruta/a/kupferbootstrap/.venv/bin/kupferbootstrap -v packages check --ci-mode \
    device-mt6785-xiaomi-begonia linux-mt6785 firmware-mt6785-xiaomi-begonia \
    boot-android-bootimg-updater mkbootimg-git
```

## Abrir el MR

1. Fork de `gitlab.com/kupfer/packages/pkgbuilds` y `git clone -b dev <tu fork> && cd pkgbuilds`
2. `cp -r /ruta/al/port/overlay/* .`
3. `git checkout -b begonia` y commit con los tres paquetes nuevos y los dos parches.
4. `kupferbootstrap packages check --ci-mode` (el CI de upstream lo corre también).
5. Push al fork y MR contra la rama `dev`, con el título **prefijado con `Draft: `** mientras el
   port no haya arrancado en el móvil: es lo que piden las guías de porting, y lo quitas cuando ya
   esté probado. Ojo con el matiz, porque cambia lo que se está diciendo: el `Draft:` no es por el
   wifi, que su autor ya verificó en un begonia ([ver](#el-wifi-verificado-por-su-autor-sin-probar-por-nosotros)),
   es por el resto del port.

Y para probarlo de verdad, el flujo es el de siempre
([quickstart de kupferbootstrap](https://kupfer.gitlab.io/kupferbootstrap/main/usage/quickstart/)),
con el perfil en `~/.config/kupfer/kupferbootstrap.toml` (secciones `[profiles.<nombre>]`, clave
`[profiles] current`):

```
kupferbootstrap config init
kupferbootstrap config profile init begonia     # device = "mt6785-xiaomi-begonia", flavour = "plasma-mobile"
kupferbootstrap packages update
kupferbootstrap image build
kupferbootstrap image flash abootimg && kupferbootstrap image flash full userdata
```

Dos extras que begonia necesita y el flujo de stock no hace: `fastboot erase dtbo` (el bootloader
quiere el `empty.dtbo` que va dentro de `aboot.img`) y un vbmeta con `--flags 2`. Lo tiene
resuelto `kupferbootstrap image boot`, que ya borra el dtbo.

El cuerpo del MR está **escrito y listo para pegar** en [`MR-kupfer-pkgbuilds.md`](MR-kupfer-pkgbuilds.md)
(en inglés, como el resto de la guía de porting). No se pudo abrir el MR desde aquí porque
este entorno no tiene token de gitlab.com.

El MR son exactamente cinco paquetes: tres nuevos (`linux/mt6785`, `firmware/mt6785-xiaomi-begonia`,
`device/device-mt6785-xiaomi-begonia`) y dos parches a paquetes que ya existen
(`boot/android-bootimg-updater`, `main/mkbootimg-git`).

Los dos parches a paquetes compartidos son la parte que un maintainer querrá revisar
primero: si se prefieren como cambios a `boot-android-bootimg-updater` y `mkbootimg-git`
en su propio MR, este port se queda solo con los tres paquetes nuevos y las mismas
`pkgrel` nuevas.

## Roadmap

- [x] Port PKGBUILDs y overlay de boot-img
- [x] Build de imagen Plasma Mobile en GHA (base `dev`) verde
- [ ] Flasheo + verificación en el móvil (panel Tianma, touch, WiFi interno MediaTek, dongles, Plasma)
- [x] Informe de qué funciona / qué no / qué no se probó (este README)
- [ ] MR upstream a `kupfer/packages/pkgbuilds` (rama `dev`)
- [x] Táctil Tianma resuelto en la imagen (`_panel=tianma` en el paquete de firmware)
- [x] `packages check --ci-mode` limpio sobre los cinco paquetes

## Referencias

Cosas de Kupfer:

- https://kupfer.gitlab.io / https://gitlab.com/kupfer/kupferbootstrap
- https://gitlab.com/kupfer/packages/pkgbuilds (rama `dev`)
- Guías de porting de Kupfer: `device/`, `linux/`, `firmware/`, `packages check` obligatorio

Cosas de begonia, en pmaports:

- `pmaports/device/testing/device-xiaomi-begonia`, `firmware-xiaomi-begonia` y
  `linux-postmarketos-mediatek-mt6785` (nuestro paquete de kernel es ese, pineado)
- MR !8852 de Dinolek, "begonia tianma" (kernel 7.1 + split CSOT/Tianma)

Cosas del driver de conectividad, que **no son nuestras** (de ahí vienen los 7 blobs y el
forward-port, y de ahí el crédito):

- Kernel: `https://gitlab.postmarketos.org/mt6785-mainline/linux`, MR **!2** *"Draft: begonia
  (MT6785): conn/WiFi vendor forward-port"*, de **minorum**, MR *cross-fork*: rama
  `begonia-conn-wifi` en el fork `https://gitlab.postmarketos.org/minorum/linux` (id 1492) →
  `6.16` en el upstream (id 780). La cabeza de esa rama, `3a1ea76942`, es lo que compila nuestro
  `linux/mt6785`; el `6.16` del fork se quedó en `203a993f`, que es justo el tag base de pmaports
  (y por eso el paquete de pmaports solo no trae el stack de conectividad)
- Firmware: `https://gitlab.postmarketos.org/mt6785-mainline/firmware`, MR **!1** *"Draft: begonia
  (MT6785): connectivity firmware blobs"*, del mismo autor
- Para contrastar con otro SoC del mismo connsys: `github.com/hataketsu/mt6768-mainline-notes`
  (Redmi 9 / MT6768), donde el fwport de gen4m compila pero nunca se ha ejecutado