# Kupfer Linux for Xiaomi Redmi Note 8 Pro (begonia)

Port: **pmOS (Alpine) → Kupfer Linux (Arch)** para Xiaomi Redmi Note 8 Pro (`xiaomi-begonia`,
SoC MediaTek **MT6785**). **Primer dispositivo MediaTek soportado por Kupfer** (hasta ahora los 24
dispositivos son Qualcomm: msm8916/8953/sdm670/sdm845).

Kupfer: *"to Arch what postmarketOS is to Alpine"* — derivada de Arch Linux ARM, infraestructura
heredada de pmOS (`deviceinfo`, `kupferbootstrap`), boot vía Android boot.img (`aboot`).

Base elegida: rama **`dev`** de `gitlab.com/kupfer/packages/pkgbuilds`, no `main`. Motivo: `main` no
tiene el flavour `flavour-plasma-mobile` ni el split de paneles, que es justamente lo que se quiere
flashar. `dev` es la rama donde upstream desarrolla, así que este port va a corde con lo que la
comunidad.mergea primero.

---

## Estado

| Etapa | Estado |
|---|---|
| Investigación (arquitectura Kupfer + datos del device) | ✅ |
| Investigación de precedentes MTK / no-Qualcomm en Kupfer | ✅ |
| PKGBUILDs de device / kernel / firmware | ✅ |
| Parche `update-bootimg.sh` (header v2 + recovery_dtbo) | ✅ |
| Toolchain de cruce en el build (lo que faltaba) | ✅ |
| `mkbootimg` con la división entera arreglada (sin esto no sale `aboot.img`) | ✅ |
| Build imagen Plasma Mobile (GHA, base `dev`) | ⏳ en curso |
| Flasheo y verificación en device | ⏳ pendiente |

## Investigación: no hay ningún port MediaTek que nos preceda

Se revisó el estado real del proyecto antes de escribir nada, para saber si existía una guía:

- **24 dispositivos** en `dev`, **todos Qualcomm** (msm8916, msm8953, sdm670, sdm845).
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
| `firmware/firmware-mediatek-mt6785` | `firmware/` | blobs conectividad MTK + novatek + rtl |

Sobre el parche a `boot/android-bootimg-updater`: hace falta, y hace falta más de lo que parecía.
`dev` sí trae el branching por `header_version` en `update-bootimg.sh`, pero **no menciona `dtbo` en
absoluto** (0 coincidencias en todo el repo), así que la rama header v2 construye el bootimg sin
`--recovery_dtbo`. El overlay añade ese flag. Detalle en "El overlay del boot updater" más abajo.

### Gaps detectados (todo el detalle en `docs/PORT.md`)

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
   depender de él. Ver `overlay/linux-mt6785/extra_config` para reactivarlo.
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

## Notas de CI

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

## Build en GitHub Actions

Ver `.github/workflows/build.yaml` + `docs/CI.md`. Runs bajo demanda (`workflow_dispatch`).
Los builds pesados van a GHA (evita OOM en la máquina local).

## Roadmap

- [ ] Port PKGBUILDs y overlay de boot-img (rama `begonia` del fork pkgbuilds)
- [ ] Build imagen Plasma Mobile en GHA (base `dev`)
- [ ] Flasheo + verificación (panel Tianma, touch, WiFi/Bluetooth dongles, Plasma)
- [ ] MR upstream a `kupfer/packages/pkgbuilds` (rama `dev`) — **con informe de qué funciona, qué
      no, y qué no se probó**, que es lo que pide la contribución
- [ ] Replicar método táctil tianma (pmOS) documentado

## Referencias

- https://kupfer.gitlab.io / https://gitlab.com/kupfer/kupferbootstrap
- https://gitlab.com/kupfer/packages/pkgbuilds
- pmOS begonia: `pmaports/device/testing/device-xiaomi-begonia`
- MR Dinolek "begonia tianma": pmaports MR !8852 (kernel 7.1 + split CSOT/Tianma)
- Fork kernel: `https://gitlab.postmarketos.org/minorum/linux` @ `3a1ea769` (begonia-conn-wifi)
- Fork firmware: `mt6785-mainline/firmware` @ `33aa9fe1` (conectividad)