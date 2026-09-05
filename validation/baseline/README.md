# Baseline MATLAB → C (capas 2, 3 y 4)

Referencia generada con el MATLAB original (`CUQDyn1_Plus/`) para validar la
transpilación C. Cubre los 4 modelos del preprint: `lv2` (Lotka-Volterra
parcialmente observado), `ap` (alpha-pinene, y5 oculto), `sir` (solo
infectados observados) y `nfkb` (15 estados, 10 observados, FIM casi
singular). **Nada de esta carpeta requiere MATLAB para consumirse**: las
referencias están exportadas a texto plano en `matlab/<modelo>/`.

Complementa a `validation/golden/` (capa 1: kernels de álgebra). La
numeración de capas es:

| Capa | Nombre | Dónde |
|---|---|---|
| 1 | Kernels de álgebra | `validation/golden/` |
| 2 | Integración y sensibilidades | aquí, `matlab/<m>/layer2/` |
| 3 | Replay de la etapa de UQ | aquí, `matlab/<m>/layer3/` |
| 4 | End-to-end estadístico | aquí, `matlab/<m>/layer4/` + `run_c_seeds.sh` |

## Qué compara exactamente cada capa

**Capa 2 — integración y sensibilidades (determinista).**
MATLAB integra la ODE con `ode15s` a los parámetros VERDADEROS del modelo y
calcula dy/dθ por paso complejo (exacto); ambos se exportan. El arnés C
(`test_baseline.c`) integra la misma ODE con CVODES y calcula las
sensibilidades con CVODES forward sensitivity, y compara ambas cosas punto a
punto. No interviene ningún optimizador: un fallo aquí es un problema del
integrador, del RHS de la ODE (p. ej. orden de parámetros) o de las
sensibilidades. Checks: `trajectory` + un `sens dtheta_k` por parámetro.

**Capa 3 — replay de la etapa de UQ (determinista).**
MATLAB ejecuta UNA vez el pipeline completo con semilla fija y exporta todo
lo que produce el optimizador: θ̂ (`theta_hat.txt`), el ensemble LOO completo
(`loo_params.txt`, `media_matrix.txt`, `resid_loo.txt`), la trayectoria de
mejor ajuste (`media_tot.txt`) y las bandas resultantes. El arnés C **inyecta
esas entradas en el código C de bandas** (`conformal_bands()` +
`delta_method_bands()`) y compara su salida con las bandas MATLAB. Como las
entradas son idénticas, el optimizador queda fuera de la ecuación: un fallo
es un bug en la matemática de bandas. Checks: `conformal q_low/q_up` (deben
ser exactas), `delta q_low/q_up` de estados ocultos, `cov_p`, `std_y`, y dos
cross-checks de configuración (`alp`, `sigma XML vs MATLAB`).

**Capa 2.5 — replay del coste sobre una búsqueda real (determinista).**
Materializa la idea del "generador de números aleatorios compartido": TODA la
aleatoriedad vive en MATLAB. `cost_replay/gen_cost_replay.m` corre UN ajuste
MEIGO/eSS sembrado con el coste envuelto en un grabador, y congela cada punto
θ_k que el optimizador decidió evaluar (≈2e4 puntos que cubren exactamente la
región que visita una búsqueda real) junto con su coste MATLAB J_k. El arnés
C (`cost_replay/test_cost_replay.c`, ctest `cost_replay_lv2`) re-evalúa el
coste C (CVODES + `cuqdyn_residual_weight`) en la MISMA secuencia y compara J
punto a punto — sin optimizador en C, así que es 100% determinista. Con esto
queda validada la función de coste *dentro del bucle de optimización*, que
era la única pieza que las capas 2-3 no cubrían. (Un puente vivo C→MEIGO vía
Engine no sería determinista: los costes difieren a nivel de redondeo y una
sola comparación volteada divergiría la búsqueda sin haber bug; congelar la
secuencia da la misma cobertura sin ese canal de divergencia.)
Resultado actual (lv2): **20.126/20.126 evaluaciones dentro de 1e-3** (media
4.2e-5, máx 5.2e-4, 0 fallos de integración).

**Experimento híbrido — optimizador compartido (hybrid/).**
El MEIGO de MATLAB corre dos veces con la misma semilla: una evaluando el
coste MATLAB (objeto `ode` con `cvodesstiff`, tolerancias del XML) y otra
evaluando el coste C real servido por TCP (`cost_server`, el mismo código del
CLI, que devuelve J y los residuos para que `lsqnonlin` también funcione).
Toda la aleatoriedad la genera MATLAB. Resultados en los 4 modelos
(`hybrid_report_<modelo>.txt`): los costes coinciden en el prefijo común a
1e-10 (lv2), 1.5e-9 (ap), 1e-6 (sir) y 3.7e-6 (nfkb), con lock-step de 123,
148, 74 y 656 evaluaciones respectivamente antes de que un redondeo voltee
una decisión discreta del eSS. Tras la divergencia, lv2/ap/sir aterrizan en
el mismo óptimo (θ̂ a 1e-7..3e-4); en nfkb los caminos acaban en cuencas
distintas del paisaje no identificable (J 914 vs 518 — el run con coste C
encontró la mejor), midiendo la multimodalidad del problema, no el código:
en el prefijo común sus costes coinciden a 3.7e-6.

**Capa 4 — end-to-end estadístico (con ruido, es lo que se mide).**
Cada lado corre el pipeline completo N veces con semillas distintas (MATLAB:
`gen_baseline(modelo, 4, 1:N)`; C: `run_c_seeds.sh modelo N`, que fija
`SACESS_SEED`). `compare_baseline.py` compara las DISTRIBUCIONES: mediana e
IQR por parámetro, ratio de anchuras de banda por estado y cobertura empírica
de la trayectoria verdadera. Es un informe para leer, no un gate: aquí dos
implementaciones correctas no coinciden ejecución a ejecución, solo en
distribución.

## Resultados actuales (capas 2+3)

**71/71 checks en verde** (lv2 12, ap 12, sir 10, nfkb 37): conformales
exactas a precisión de máquina en los 4 modelos, sensibilidades a 1e-7..1e-4,
bandas delta a 1e-5 (2.9% en nfkb, coherente con cond(FIM) ~ 3e8).

> **Aviso**: no usar `example-files/lotka_volterra_cuqdyn_config.xml` para
> comparar con MATLAB. Su modelo compilado Rust (`lotka-volterra` en
> `modules/cuqdyn-rs/src/models.rs`) tiene **p3 y p4 intercambiados** respecto
> a `prob_mod_dynamics_LV.m`. El baseline usa `lv2_partobs_*`, que define la
> ODE por expresiones y sí coincide. El `nfkb` compilado está verificado
> término a término y es correcto.

## Cómo ejecutar la comparación (sin MATLAB)

Único paso de integración: añadir una línea al `CMakeLists.txt` raíz, tras
`add_subdirectory(tests)`:

```cmake
add_subdirectory(validation)
```

Y build normal:

```bash
mkdir -p build-serial && cd build-serial
cmake -DCMAKE_TOOLCHAIN_FILE=../toolchains/serial_toolchain.cmake ..
make -j
ctest -R baseline --output-on-failure
```

Si faltan los exports MATLAB los tests salen como SKIP, no como fallo. Tabla
check a check:

```bash
./build-serial/validation/baseline/test_baseline validation/baseline/matlab/lv2 \
    example-files/lv2_partobs_cuqdyn_config.xml \
    example-files/lv2_partobs_paper_data.txt
```

Capa 4, lado C + informe:

```bash
validation/baseline/run_c_seeds.sh lv2 10      # SACESS_SEED=1..10
python3 validation/baseline/compare_baseline.py lv2
```

Notas de autocontención: el ejemplo AP parcialmente observado (datos +
configs `ap_partobs_*`) vive en este directorio porque `example-files/` solo
trae el alpha-pinene totalmente observado; `nfkb_cuqdyn_fullsigma.xml` es el
config NF-kB con los `<sigma>` a precisión completa (los de `example-files/`
están truncados y fallan el cross-check a 1e-9); y
`nfkb_ess_serial_2e4.xml` iguala el presupuesto del eSS C al del runner
MATLAB (2e4 frente al 1e5 del config estándar). Promocionarlos a
`example-files/` es razonable como cambio aparte.

## Regenerar las referencias (solo con MATLAB, solo si cambia la referencia)

Requisitos: MATLAB R2020a+ con Optimization Toolbox; MEIGO64 se toma de
`$MEIGO64_PATH` o de `CUQDyn/Matlab/MEIGO64-master` del repo.

```matlab
cd validation/baseline
gen_baseline('lv2')            % capas 2 y 3 (por defecto)
gen_baseline('nfkb', [2 3])
gen_baseline('sir', 4, 1:10)   % capa 4, semillas 1..10
```

En drago.cesga.es:

```bash
sbatch --export=ALL,MODEL=nfkb,LAYERS="[2 3]" validation/baseline/drago_baseline.sbatch
sbatch --array=1-20 --export=ALL,MODEL=nfkb,LAYERS=4 validation/baseline/drago_baseline.sbatch
```

Cada tarea del array corre una semilla en su propio `seed_<k>/` (re-lanzable;
las semillas hechas se saltan). Si el módulo no se llama `matlab` a secas:
`MATLAB_MODULE=matlab/R20xxa` en el `--export`.

## Tolerancias y cómo leer un fallo

En `matlab/<modelo>/tol.txt` (editables sin regenerar nada):

| Clave | lv2 | nfkb | Por qué |
|---|---|---|---|
| `layer2_traj` | 1e-4 | 5e-4 | ambos integran a RelTol 1e-6; dos solvers correctos coinciden a ese orden |
| `layer2_sens` | 5e-3 | 1e-2 | el paso complejo es exacto, CVODES usa diferencias internas |
| `layer3_conformal` | 1e-9 | 1e-9 | entradas idénticas + mismo algoritmo de cuantiles: más que esto es bug |
| `layer3_delta` | 1e-2 | 1e-1 | hereda el error de sensibilidades a través de la inversa de la FIM |
| `layer3_covp` | (=delta) | 1e3 | con cond(FIM)~3e8 la covarianza elemento a elemento está dominada por la regularización en ambos lados; lo comparable son las bandas y `std_y` |

Guía de diagnóstico:

- **Falla `conformal q_low/q_up`** → bug en `conformal_bands.c` o
  `matlab.c:quantile`. La señal más limpia posible: entradas idénticas.
- **Falla `trajectory` pero no las sensibilidades** → config del integrador
  (comparar el XML con `opts.ode`) o la ODE misma (orden de parámetros — ver
  el aviso de lotka-volterra).
- **Fallan `sens dtheta_k` para algunos k** → precisión de las sensibilidades
  CVODES en esos parámetros; si son los de escala minúscula, mirar `pbar`.
- **Falla solo `cov_p`/`std_y`/`delta`** con capa 2 en verde → la diferencia
  se amplifica en la FIM: leer el `rank` y `condition number` que imprime el
  harness antes de sospechar del código.
- **Falla `sigma XML vs MATLAB`** → el `<sigma>` del config no coincide con
  el que MATLAB deriva; todo lo demás fallará en cascada. Corregir el XML.

## Reproducibilidad

- MATLAB: `rng(semilla,'twister')` + LOO **secuencial** (`use_parallel=false`;
  con `parfor` el stream de rng se reparte entre workers y no es repetible).
  La capa 3 usa la semilla fija 20260819; la capa 4, las semillas 1..N.
- C: `SACESS_SEED=<k>` (lo fija `run_c_seeds.sh`).
- Las semillas de un lado no se corresponden con las del otro — por eso la
  capa 4 compara distribuciones.
- Presupuestos del optimizador igualados entre lados (`maxeval` en
  `gen_baseline.m` = `maxevaluation` del config eSS usado por el arnés).

## Figuras

Un par por modelo, mismo layout (banda + ajuste + datos; azul =
observado/conformal, naranja = oculto/delta):
`matlab_<modelo>_hybrid_uq_plot.png` y `c_<modelo>_seed1_hybrid_uq_plot.png`.
Cualquier `cuqdyn-results.txt` se redibuja igual con:

```bash
python3 validation/baseline/plot_c_results_matlab_style.py <results.txt> <datos.txt> <salida.png>
```

## La vía rápida en `test_cuqdyn_algo` (propuesta de Borja)

`write_expected_output.m` genera `example-files/lv2_partobs_expected_output.txt`
y `tests/data/lv2_partobs_expected_output.txt` a partir del export de capa 3.
Esos ficheros caen fuera de `validation/`, así que esta rama no los incluye;
la comparación en `tests/test_cuqdyn_algo.c` (margen medio generoso, dos eSS
independientes) se propone por separado por la misma razón.

## Qué NO cubre este baseline

- El camino MPI (sharding del bucle LOO).
- `uq_method=hybridcov` end-to-end (el kernel de la covarianza híbrida sí
  está cubierto en capa 1).
- El bootstrap trayectorial (sin portar a C).
