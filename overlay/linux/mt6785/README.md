# Parches de batería para begonia (fuel gauge GM30 del PMIC MT6359)

## Por qué existen

El begonia (Xiaomi Redmi Note 8 Pro, MT6785) **no tiene fuel gauge en mainline**.
En Linux no existe ningún driver de gauge para Mediatek: el chip real es el
**GM30**, un contador coulomb propietario de MTK que vive dentro del PMIC
**MT6359**, y su árbol de dispositivos (`mediatek,bat_gm30`) no está en el DTS de
mainline. Por eso hasta ahora `/sys/class/power_supply/` sólo mostraba
`mt6360-chg.1.auto` (el cargador, que sí es upstream: `mt6360_charger.c`) y
`tcpm-source-psy-mt6360-tcpc.4.auto`: **ninguna** `power_supply` de tipo
Battery. Sin porcentaje, sin voltaje, sin apagado por batería baja.

La solución la escribió **Dinolek** en la rama suelta **`battery-downstream`**
de `gitlab.postmarketos.org/mt6785-mainline/linux` (commit `fad73078`,
2025-08-28, *"arm64: dts: mediatek: mt6785-xiaomi-begonia: Enable pmic fuel
gauge and battery manager"*). Importa el stack de batería del **kernel
downstream de Android** (Xiaomi) al mainline: `mt6359-gauge` más la familia
`mtk_battery*`.

Esa rama **no tiene MR** y nunca se integró. Y no se puede usar tal cual: se
sakó de un punto anterior de `6.16` y **no lleva el forward-port de WiFi**, que
vive en nuestra rama `begonia-conn-wifi` (MR !2, commit `3a1ea769`). Usarla
directamente mataría el WiFi, que hoy sí funciona.

Por eso estos parches son el **diff del estado final de `battery-downstream`
contra nuestro pin**, no la serie de commits original. Ventajas: se aplican
limpio sobre `3a1ea769` sin depender del orden, y el WiFi del DTS se conserva.

## Cómo se generaron

Sin clonar el kernel. Con la API de GitLab se bajaron las 12 rutas que cambian
en las dos versiones y se generaron los diff con `diff -u`. Comprobado: los 12
aplican con **cero offset y cero fuzz**, o sea que nuestro pin es byte-idéntico
a la base de `battery-downstream` en esas rutas.

## Los 10 parches van PLANOS en este directorio, no en un subdirectorio

Restricción real de Kupfer, aprendida a base de un build fallido (run `36355197902`):
al resolver `source=`, makepkg **reduce cada entrada a su basename y la busca en la
raíz del directorio de build**. Un `patches/0101-...patch` no se encuentra, y el
error lo dice sin el prefijo, lo que despista:

```
==> ERROR: 0101-power-supply-mtk-battery-import.patch was not found in the build directory and is not a URL.
```

Los ficheros planos del paquete (`extra_config`, `linux.preset`, los dos hooks) sí
se encontraban, en las cuatro líneas anteriores del mismo log. Así que **no los
muevas a `patches/`** sin comprobar antes que Kupfer lo soporta.

## Contenido de cada parche

| # | parche | qué hace |
|---|---|---|
| 0101 | `power-supply-mtk-battery-import` | Los 11 ficheros nuevos verbatim: `mt6359-gauge.c` (el gauge), `mtk_battery{,.h,_algo,_coulomb_service,_daemon,_daemon.h,_interface,_manager,_table.h}`, `mtk_gauge.h`. |
| 0102 | `power-supply-kconfig-makefile` | `config BATTERY_MT6359` en `drivers/power/supply/Kconfig` (`depends on MFD_MT6397`) y las 3 líneas del `Makefile`. **Una sola opción lo enciende todo**: `obj-$(CONFIG_BATTERY_MT6359) += mtk-battery-manager.o mt6359_battery.o`. |
| 0103 | `mfd-mt6397-core-gauge-irqs` | **Sólo 2 de los 8 hunks** del diff original: el array `mt6359_gauge_resources` con los 12 `DEFINE_RES_IRQ_NAMED` del gauge y la `mfd_cell` `mt6359-gauge`. |
| 0104 | `mfd-mt6359-registers` | `include/linux/mfd/mt6359/registers.h`: los defines `MT6359_IRQ_*` que necesita 0103. |
| 0105 | `rtc-mt6397-nvmem` | `include/linux/mfd/mt6397/rtc.h` + `drivers/rtc/rtc-mt6397.c`: nvmem, para que el gauge tenga sus dos `nvmem-cells`. |
| 0106 | `iio-adc-mt6359-auxadc-processed` | Exponer `IIO_CHAN_INFO_PROCESSED` y calcular mV en `read()`. |
| 0107 | `psupply-mt6360-charger-supplied-to` | `supplied_to = { "battery" }`: sin esto el cargador no publica nada a la batería. |
| 0108 | `irq-irqdesc-export-irq_to_desc` | Ver "La única concession" más abajo. |
| 0109 | `dts-mt6359-fuel-gauge-node` | Nodo `mt6359_gauge: fuel-gauge` (`status = "disabled"`) y `fg_init`/`fg_soc` dentro de `mt6359rtc`. |
| 0110 | `dts-begonia-battery-manager` | Las 4 ediciones del DTS de begonia (ver abajo). 593 líneas, de las que ~550 son las tablas de perfil. |

## Las 4 ediciones del DTS de begonia (0110)

1. Añade `#include <dt-bindings/iio/adc/mediatek,mt6359-auxadc.h>`. Se
   **mantienen** los includes de `arm-gic.h` e `irq.h` que ya teníamos.
2. En la raíz, antes de `chosen {`, el nodo `battery-manager`
   (`compatible = "mediatek,battery-manager"`, `gauge1 = <&mt6359_gauge>`,
   `power-supplies = <&mt6360_charger>`), y `chosen:` pasa a tener label.
3. Etiqueta el nodo del cargador como `mt6360_charger:` (lo necesita el
   `power-supplies` de arriba).
4. Inserta el bloque `&mt6359_gauge { status = "okay"; ... }`: `io-channels`,
   ~35 parámetros de ajuste y las **15 tablas de perfil** del fabricante
   (`battery{0,1,2}_profile_t{0..4}`, 100 puntos cada una, voltaje en µV y
   corriente en µA) más 4 tablas `g-*` de 4×10. Son las curvas reales del
   fabricante; sin ellas el gauge daría porcentajes sin sentido.

### Lo que se descartó a propósito

- **El diff de `mt6785.dtsi` entero.** En `battery-downstream` ese fichero
  **borra 128 líneas** —`wifi@18000000`, `consys@18002000`, `btif@1100c000`,
  `wmac@18000000` y los `#include` de clk/gic/irq— **sin readdición**: allí el
  WiFi no está en ese fichero. Aplicarlo mataría el WiFi. El WiFi de nuestro pin
  se deja **intacto** (verificado con `cmp`: `mt6785.dtsi` queda byte-idéntico
  al pin).
- **El diff de `begonia.dts` entero**, por lo mismo (quita `consys@18002000` y
  `connectivity_combo`).
- **6 de los 8 hunks de `mt6397-core.c`**: renombran `mt63xx-keys` →
  `mtk-pmic-keys`. No son de batería y reverse-matearían el renombrado que ya
  tenemos.
- **El 5º canal de IIO, `<&auxadc 5>` / `"bat_id"`**, y con él el nodo
  `auxadc@11001000` de `mt6785.dtsi`. El compatible `mediatek,mt6785-auxadc` no
  tiene driver en nuestro pin, así que esa referencia no resolvería nunca. Es
  un fallo blando (`fgauge_get_profile_id()` cae a `battery_id = 0`, que es una
  curva real del fabricante), pero es una referencia muerta y se quita.
- **`&cci { proc-supply = <&mt6359_vproc2_buck_reg>; }`**: ya existe en nuestro
  pin, no se duplica.

## Config

Tres símbolos en `overlay/linux/mt6785/extra_config`:

```
CONFIG_BATTERY_MT6359=y
CONFIG_RTC_DRV_MT6397=y
CONFIG_MEDIATEK_MT6359_AUXADC=y
```

Los tres van con `=y` a propósito, no `=m`. Los referencia el DT y el orden de
probe entre módulos no está garantizado: el primer `devm_iio_channel_get()` de
`mt6359-gauge.c` es un punto **duro** de probe (`dev_err` + `return
-EPROBE_DEFER`), y el nvmem del RTC es de donde salen sus dos `nvmem-cells`. Como
módulos, un probe en diferido no siempre se reintenta. Como built-in no hay
carrera. Por eso el paso de verificación del CI mira `modules.builtin` y **no**
la presencia de `.ko`.

## La única concesión: 0108 re-exporta `irq_to_desc`

`kernel/irq/irqdesc.c` tiene hoy:

```c
#ifdef CONFIG_KVM_BOOK3S_64_HV_MODULE
EXPORT_SYMBOL_GPL(irq_to_desc);
#endif
```

0104/0103/0101 necesitan ese símbolo fuera de KVM. La solución de Dinolek —y la
nuestra— es quitarle el `#ifdef`, dejando el `EXPORT_SYMBOL_GPL` para todos.

**Qué significa:** `irq_to_desc` pasa a ser exportable por cualquier módulo con
licencia GPL. Sigue necesitando `EXPORT_SYMBOL_GPL`, así que no se abre a
código no-GPL, y el find de "todo lo que ve el kernel" crece en un símbolo. En un
móvil con Android, donde el modelo de amenazas esapps de terceros, un módulo del
kernel que enxute cualquier IRQ es más alcance del que tiene en un portátil. En
un kernel compilado a medida para tu propio dispositivo, el riesgo es bajo y es
el mismo que lleva anyendo la rama de Dinolek. Se documenta aquí en vez de
esconderse. Lo que **no** se ha hecho es reimplementar el stack del gauge para
evitarlo.

## Qué está verificado y qué no

**Verificado en el build:**
- Los 10 parches aplican limpios (22 ficheros, sin offset ni fuzz) sobre una
  copia de las 12 rutas tal cual están en `3a1ea769`.
- `mt6785.dtsi` queda byte-idéntico al pin: el WiFi (`wifi@1800000`,
  `consys@18002000`, `btif@1100c000`, `wmac@18000000`) intacto.
- El DTS parcheado compila con `dtc` de verdad: DTB de 23135 B, sin warnings del
  bloque de batería. Decompilado, los 3 phandles del `battery-manager` resuelven
  y `io-channels` da las celdas 1, 0, 8, 12 = BAT_TEMP, BATADC, VBIF, VBAT.
- Los índices del enum de `mediatek,mt6359-auxadc.h` **son** las posiciones del
  array `mt6359_auxadc_channels[]`, y la IIO core empareja por
  `io-channel-names` del consumidor + índice, no por `chan->name`. Por eso
  funciona aunque el driver no rellene `.name`.
- El kernel entero compila. GHA run `36359217206` (sha `11637f4`), 25 pasos
  verdes en 55 min 32 s, incluido el paso `Verify battery stack`.

**Verificado en el begonia real** (run `36359217206` flasheado solo en `boot`,
28-09-2026):

- El kernel que corre es el construido en GHA, no el anterior:
  `Linux version 6.16.4 (kupfer@runnervmtr4k5) ... #1 SMP PREEMPT Mon Sep 28
  00:12:27 UTC 2026`, con `CONFIG_BATTERY_MT6359=y`, `CONFIG_MFD_MT6397=y`,
  `CONFIG_RTC_DRV_MT6397=y` y `CONFIG_MEDIATEK_MT6359_AUXADC=y` en
  `/proc/config.gz`.
- Los 8 dispositivos del PMIC se registran en `sysfs`: `battery-manager`,
  `mt6359-gauge`, `mt6359-auxadc`, `mt6359-rtc`, `mt6359-accdet`,
  `mt6359-keys`, `mt6359-regulator`, `mt6359-sound`.
- **El gauge lee corriente de verdad**, no devuelve ceros ni valores fijos:
  `fgauge:[get_ptim_current]ptim current:10821` repetido cada 10 s, y el daemon
  escribe `fgauge:[fgauge] car[-15,218,-218,437,-219] tmp:27 soc:4 vbat:3837
  ibat:2764 baton:777 algo:1 ...` — `algo:1` es conteo de culombios.
- **No hay ni un `probe deferral` ni un `probe fail`** en todo el `dmesg`. Era el
  riesgo real de la serie: `mt6359-gauge.c` devuelve `-EPROBE_DEFER` en el primer
  `devm_iio_channel_get()`, y como los cuatro drivers van `=y` no hay carrera de
  orden de probe. Se confirma en hardware.
- `/dev/rtc0` existe y la fecha del sistema es correcta.
- Hay un `power_supply` de tipo `Battery` con `capacity`, `voltage_now`,
  `current_now`, `temp`, `charge_full` y `cycle_count`.

**Lo que se midió de la lectura del 4%**, porque es donde las tablas sin
calibrar podían fallar y no fallaron: `capacity=4` con `voltage_now=3840000` µV
(3,84 V), `temp=270` (27 °C), `charge_full = charge_full_design = 2946000` µAh,
`cycle_count=1`. El SOC que calcula el gauge por conteo de culombios y su propio
voltaje dicen los dos 4%, así que la tabla no está inventándose nada: 3,84 V en
una celda Li-ion es de verdad el final. `capacity_level=Low` es correcto ahí.

**No verificado:**
- Un ciclo completo de carga/descarga. La lógica de "shutdown por batería baja"
  (`pmic-min-vol = 33500`, `shutdown-gauge0-voltage = 34000`) decide cuándo
  apagar el móvil: mal calibrada, puede apagarse antes de tiempo. No se ha
  probado a llegar al umbral, y es lo primero que hay que mirar.
- La precisión del porcentaje a medio ciclo. `cycle_count=1` significa que el
  gauge todavía no ha aprendido una capacidad de carga completa distinta de la
  de diseño.
- La carga rápida. Se mide `mt6360-chg.2.auto` con `online=1` pero
  `usb_type=Unknown [SDP] DCP CDP`, y el TCPC con `current_max=0`: **el USB-PD
  no negocia contrato**, así que entra a ~150-200 mA sobre 2946 mAh. Con un
  cargador de pared que negocie PD sube, pero eso no se ha probado.

## Procedencia

- `gitlab.postmarketos.org/mt6785-mainline/linux`, rama `battery-downstream`
  (head `fad73078`, Dinolek, 2025-08-28, sin MR).
- Nuestro pin: `_commit=3a1ea769`, rama `begonia-conn-wifi` (MR !2, forward-port
  de conectividad/WiFi de Mediatek).
- El diff de `mt6785-xiaomi-begonia.dts` **editado a mano**, no aplicado tal
  cual. El fichero resultante está en
  `battery-extract/final/arch/arm64/boot/dts/mediatek/`.
