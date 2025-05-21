#!/bin/bash

bash build.sh

# === CONFIGURATION ===
VARIANTS=("mpi" "mpi2" "serial")
PROCS_LIST=(2 3 5 6 10 15 30)
REPEATS=3

# === OUTPUT ===
OUT_FILE="output/scalability_results.csv"
echo "Variant,Procs,Run,RealTime(s),UserTime(s),SysTime(s)" > $OUT_FILE

# === MAIN LOOP ===
for VARIANT in "${VARIANTS[@]}"; do
  echo "Testing variant: $VARIANT"

  # If variant is serial, only run with 1 process
  if [[ "$VARIANT" == "serial" ]]; then
    echo "  Serial run (1 proc only)..."
    for (( R=1; R<="$REPEATS"; R++ )); do
      /usr/bin/time -f "$VARIANT,1,$R,%e,%U,%S" -a -o "$OUT_FILE" \
        ./build-"$VARIANT"/modules/cli/cli solve \
          -c example-files/lotka_volterra_cuqdyn_config.xml \
          -s example-files/lotka_volterra_ess_"$VARIANT"_config.xml \
          -d example-files/lotka_volterra_paper_data.txt \
          -o output/
    done
  else
    for PROCS in "${PROCS_LIST[@]}"; do
      echo "  Running with $PROCS processes..."
      for (( R=1; R<="$REPEATS"; R++ )); do
        /usr/bin/time -f "$VARIANT,$PROCS,$R,%e,%U,%S" -a -o "$OUT_FILE" \
          mpirun -np "$PROCS" ./build-"$VARIANT"/modules/cli/cli solve \
            -c example-files/lotka_volterra_cuqdyn_config.xml \
            -s example-files/lotka_volterra_ess_"$VARIANT"_config.xml \
            -d example-files/lotka_volterra_paper_data.txt \
            -o output/
      done
    done
  fi

done

echo "✅ Scalability test finished. Results in: $OUT_FILE"
