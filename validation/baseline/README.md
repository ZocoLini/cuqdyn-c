# Baseline MATLAB → C

Referencia generada con el MATLAB original (`CUQDyn1_Plus/`) para validar la
transpilación C, pensada para un reparto de trabajo concreto:

- **David** (tiene MATLAB, local y drago.cesga.es): genera los exports una vez.
- **Compañeros** (sin MATLAB): reciben los exports como ficheros de texto plano
  y comparan contra el C con `ctest` y un script Python. **Nada de esta
  carpeta requiere MATLAB para consumirse.**

Complementa a `validation/` (capa 1: kernels de álgebra lineal, ya en verde).
Aquí se cubren las capas 3, 4 y 5 de la tabla de `validation/README.md`.

## Qué compara cada capa

| Capa | Qué se compara | Ruido de optimizador | Quién la ejecuta |
|---|---|---|---|
| 3 | ODE + sensibilidades a **parámetros fijos** (ode15s + paso complejo vs CVODES) | ninguno | ctest (`test_baseline`) |
| 4 | Solo la etapa de UQ: θ̂ y el ensemble LOO de MATLAB **se inyectan** en `conformal_bands()` / `delta_method_bands()` | ninguno | ctest (`test_baseline`) |
| 5 | Pipeline completo, N semillas por lado, comparación de **distribuciones** | dominante (es lo que se mide) | `run_c_seeds.sh` + `compare_baseline.py` |

La capa 3 es la que responde al TODO «verificar que las sensitivities estén
bien»: MATLAB deriva con paso complejo (exacto) y el C con CVODES forward
sensitivities (diferencias finitas internas para el RHS sensible). La capa 4
aísla la matemática de bandas del ruido de eSS. La capa 5 es lo único que
ejercita sacess/eSS de verdad, y por eso es informe y no gate.

Modelos: `lv2` (Lotka-Volterra parcialmente observado — verificado que datos,
cotas y orden de parámetros son idénticos entre
`EXAMPLES/LV/run_LV2_CUQDyn1_Plus_partobs_example.m` y
`example-files/lv2_partobs_*`) y `nfkb` (15 estados / 29 parámetros / 10
observados, FIM casi singular — el caso duro; mismo dataset en ambos lados).

> **Aviso**: no usar `example-files/lotka_volterra_cuqdyn_config.xml` para
> comparar con MATLAB. Su modelo compilado Rust (`lotka-volterra` en
> `modules/cuqdyn-rs/src/models.rs`) tiene **p3 y p4 intercambiados** respecto
> a `prob_mod_dynamics_LV.m`. El baseline usa `lv2_partobs_*`, que define la
> ODE por expresiones y sí coincide. El `nfkb` compilado está verificado
> término a término y es correcto.

## Parte de David (MATLAB)

Requisitos: MATLAB R2020a+, Optimization Toolbox (lsqnonlin dentro de MEIGO).
MEIGO64 se toma de `$MEIGO64_PATH` o de `CUQDyn/Matlab/MEIGO64-master` del
propio repo.

### Local (capas 3 y 4; minutos para lv2, más para nfkb)

```matlab
cd validation/baseline
gen_baseline('lv2')          % capas 3 y 4
gen_baseline('nfkb')
```

### drago.cesga.es (capa 5, y nfkb en general)

```bash
ssh darope@drago.cesga.es
cd <repo>
sbatch --export=ALL,MODEL=nfkb,LAYERS="[3 4]" validation/baseline/drago_baseline.sbatch
sbatch --array=1-10 --export=ALL,MODEL=lv2,LAYERS=5  validation/baseline/drago_baseline.sbatch
sbatch --array=1-20 --export=ALL,MODEL=nfkb,LAYERS=5 validation/baseline/drago_baseline.sbatch
```

Cada tarea del array corre una semilla en su propio `seed_<k>/`, así que se
puede relanzar sin repetir lo hecho. Si el módulo de MATLAB de drago no se
llama `matlab` a secas, añadir `MATLAB_MODULE=matlab/R20xxa` al `--export`
(consultar con `module spider matlab`).

### Entregar a los compañeros

```bash
tar czf baseline_lv2.tar.gz  -C validation/baseline/matlab lv2
tar czf baseline_nfkb.tar.gz -C validation/baseline/matlab nfkb
```

o, mejor, **commitear `validation/baseline/matlab/`** al repo: es texto plano
con formato `filas cols` + `%.17g` (el mismo de `validation/golden/`), pesa
poco (lv2 ~1 MB; nfkb algo más por `media_matrix`) y así el baseline queda
versionado junto al código que valida.

## Parte de los compañeros (sin MATLAB)

### 0. Tener los exports

Descomprimir el tar (o hacer pull) de forma que exista
`validation/baseline/matlab/lv2/` y/o `.../nfkb/`.

### 1. Capas 3 y 4 — ctest

Esta rama no toca nada fuera de `validation/`, así que el único paso de
integración es añadir **una línea** al `CMakeLists.txt` raíz (tras
`add_subdirectory(tests)`):

```cmake
add_subdirectory(validation)
```

Y a partir de ahí, build normal:

```bash
mkdir -p build-serial && cd build-serial
cmake -DCMAKE_TOOLCHAIN_FILE=../toolchains/serial_toolchain.cmake ..
make -j
ctest -R baseline --output-on-failure
```

Notas de autocontención: el ejemplo AP parcialmente observado (datos + configs)
vive en este directorio porque `example-files/` solo trae el alpha-pinene
totalmente observado; y `nfkb_cuqdyn_fullsigma.xml` es el config NF-kB con los
`<sigma>` a precisión completa (los de `example-files/` están truncados y
fallan el cross-check a 1e-9). Mover ambos a `example-files/` es razonable como
cambio aparte.

Si los exports no están, los tests salen como **SKIP**, no como fallo. Para
la tabla completa por comprobación:

```bash
./validation/baseline/test_baseline ../validation/baseline/matlab/lv2 \
    ../example-files/lv2_partobs_cuqdyn_config.xml \
    ../example-files/lv2_partobs_paper_data.txt
```

### 2. Capa 5 — semillas C + informe

```bash
validation/baseline/run_c_seeds.sh lv2 10      # SACESS_SEED=1..10
validation/baseline/run_c_seeds.sh nfkb 20     # tarda; ideal en ft3/drago
python3 validation/baseline/compare_baseline.py lv2
```

`compare_baseline.py` escribe `report_<modelo>.md` con: mediana e IQR de cada
parámetro en ambos lados, ratio C/MATLAB, solape de IQRs, anchura de bandas
por estado y cobertura empírica de la trayectoria verdadera. Con matplotlib
instalado añade un boxplot por parámetro. **Es un informe, no un gate**: aquí
el ruido del optimizador es parte de lo que se mide.

## Tolerancias y cómo leer un fallo

Las tolerancias van en `matlab/<modelo>/tol.txt` (las escribe
`gen_baseline.m`, se pueden editar sin regenerar nada):

| Clave | lv2 | nfkb | Por qué |
|---|---|---|---|
| `layer3_traj` | 1e-4 | 5e-4 | ambos integran a RelTol 1e-6; dos solvers correctos coinciden a ese orden |
| `layer3_sens` | 5e-3 | 1e-2 | el paso complejo es exacto, CVODES usa diferencias internas; es la capa determinista más floja |
| `layer4_conformal` | 1e-9 | 1e-9 | entradas idénticas + mismo algoritmo de cuantiles: cualquier cosa mayor es bug de transpilación |
| `layer4_delta` | 1e-2 | 1e-1 | hereda el error de sensibilidades a través de la inversa de la FIM; en nfkb (cond ~6e8) la covarianza está dominada por la regularización |

Guía de diagnóstico:

- **Falla `conformal q_low/q_up`** → bug en `conformal_bands.c` o
  `matlab.c:quantile`. Es la señal más limpia posible: entradas idénticas.
- **Falla `trajectory` pero no las sensibilidades** → tolerancias/config del
  integrador (comparar el XML con `opts.ode`), o la ODE misma (orden de
  parámetros — ver el aviso de lotka-volterra).
- **Fallan `sens dtheta_k` para algunos k** → precisión de las sensibilidades
  CVODES en esos parámetros. En nfkb mirar qué parámetros son: si coinciden
  con los de escala minúscula (~1e-7), es el escalado `pbar`.
- **Falla solo `cov_p`/`std_y`/`delta`** con capa 3 en verde → la diferencia
  se amplifica en la FIM: mirar el `rank` y `condition number` que imprime el
  harness (via `delta_bands.c`) antes de sospechar del código.
- **Falla `sigma XML vs MATLAB`** → el `<sigma>` del XML no coincide con el
  que MATLAB deriva de la trayectoria verdadera; todo lo demás fallará en
  cascada. Corregir el XML primero.

## Reproducibilidad

- MATLAB: `rng(semilla,'twister')` antes de cada run y LOO **secuencial**
  (`use_parallel=false`; con parfor el stream de rng se reparte entre workers
  y el run no es repetible). Capa 4 usa la semilla fija 20260819; capa 5 las
  semillas 1..N.
- C: `SACESS_SEED=<k>` (lo fija `run_c_seeds.sh`).
- Las semillas de un lado no se corresponden con las del otro — por eso la
  capa 5 compara distribuciones.
- Presupuesto del optimizador igualado a `maxeval=2e4` en ambos lados (el
  ejemplo MATLAB de LV usa 2000 por defecto; el baseline lo sube para casar
  con `lv2_partobs_ess_serial_config.xml`).

## Formatos de fichero

Todo es `filas cols` en la primera línea y valores `%.17g` después (round-trip
exacto de doubles). Excepciones con cabecera propia:

- `layer3/sens.txt`: `m nstates n_params`, luego `n_params` bloques de
  `m x nstates` (bloque k = dy/dθ_k).
- `layer4/media_matrix.txt`: `n_loo m nstates`, luego `n_loo` bloques de
  `m x nstates` (bloque k = trayectoria del refit LOO k).
- `observed_idx.txt` está en **1-based** (convención MATLAB); el harness C
  convierte.
- `meta.txt`, `meta4.txt`, `tol.txt`: pares `clave valor`.

## Comparación rápida en `test_cuqdyn_algo` (propuesta de Borja)

Además de las capas anteriores hay un camino más simple, integrado en el test
existente: `tests/test_cuqdyn_algo.c` compara la ejecución completa del caso
`lv2_partobs` contra una referencia MATLAB si existe
`tests/data/lv2_partobs_expected_output.txt`.

- **Generar la referencia** (una vez, con MATLAB):

  ```matlab
  cd validation/baseline
  write_expected_output
  ```

  Escribe `example-files/lv2_partobs_expected_output.txt` y
  `tests/data/lv2_partobs_expected_output.txt` — fuera de `validation/`, así
  que esta rama no los incluye; quien quiera activar esa comparación los
  genera con el comando de arriba (reutiliza el export de capa 4 que sí va en
  la rama). La comparación misma requiere además el cambio en
  `tests/test_cuqdyn_algo.c`, propuesto por separado por la misma razón.

- **Consumir** (sin MATLAB): nada que hacer — `ctest -R test_cuqdyn_algo` la
  usa automáticamente. Sin el fichero, el test pasa solo con sus asserts
  estructurales y lo dice por pantalla.

Los márgenes son errores **medios** (L1 relativo) deliberadamente generosos —
`0.25` parámetros / `0.15` trayectoria / `0.25` bandas, definidos como macros
al principio de `test_cuqdyn_algo.c` — porque cada lado corre su propio eSS
estocástico. Un bug de transpilación aparece como desviación sistemática muy
por encima de ese ruido; para afinar más, usar las capas 3 y 4, que no tienen
ruido de optimizador.

## Qué NO cubre este baseline

- El camino MPI (sharding del bucle LOO) — sigue pendiente, ver TODO.
- `uq_method=hybridcov` end-to-end (la covarianza híbrida como kernel ya está
  en capa 1; añadir un run MATLAB con `CUQDyn1_Plus_HybridCov` sería la
  extensión natural de la capa 4).
- El bootstrap trayectorial (no portado a C).
