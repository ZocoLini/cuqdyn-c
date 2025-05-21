#!/bin/bash

#SBATCH --mem=12G
#SBATCH -n 30
#SBATCH --time=1:00:00
#SBATCH --exclusive -m cyclic:cyclic:fcyclic

if [ -d "/home/cesga" ]; then
    module load cesga/2020
fi

bash build.sh

# === CONFIGURATION ===
VARIANTS=("mpi" "mpi2" "serial")
PROCS_LIST=(2 3 5 6 10 15 30)
REPEATS=3

# === OUTPUT ===
mkdir -p "output/scalability"
OUT_FILE="output/scalability_results.csv"
echo "Variant,Procs,Iteration,Metric,Value,Unit" > "$OUT_FILE"

# === MAIN LOOP ===
for VARIANT in "${VARIANTS[@]}"; do
  echo "Testing variant: $VARIANT"

  # If variant is serial, only run with 1 process
  if [[ "$VARIANT" == "serial" ]]; then
    echo "  Serial run (1 proc only)..."
    for (( R=1; R<="$REPEATS"; R++ )); do
      mkdir -p "output/scalability/$VARIANT/$R"
      START_TIME=$(date +%s.%N)

      ./build-"$VARIANT"/modules/cli/cli solve \
        -c example-files/lotka_volterra_cuqdyn_config.xml \
        -s example-files/lotka_volterra_ess_"$VARIANT"_config.xml \
        -d example-files/lotka_volterra_paper_data.txt \
        -o "output/scalability/$VARIANT/$R"

      END_TIME=$(date +%s.%N)
      ELAPSED_TIME=$(echo "$END_TIME - $START_TIME" | bc)

      echo "$VARIANT,1,$R,wall-time,$ELAPSED_TIME,s" >> "$OUT_FILE"
    done
  else
    for PROCS in "${PROCS_LIST[@]}"; do
      echo "  Running with $PROCS processes..."
      for (( R=1; R<="$REPEATS"; R++ )); do
        mkdir -p "output/scalability/$VARIANT/$PROCS/$R"
        START_TIME=$(date +%s.%N)

        srun ./build-"$VARIANT"/modules/cli/cli solve \
          -c example-files/lotka_volterra_cuqdyn_config.xml \
          -s example-files/lotka_volterra_ess_"$VARIANT"_config.xml \
          -d example-files/lotka_volterra_paper_data.txt \
          -o "output/scalability/$VARIANT/$PROCS/$R"

        END_TIME=$(date +%s.%N)
        ELAPSED_TIME=$(echo "$END_TIME - $START_TIME" | bc)

        echo "$VARIANT,$PROCS,$R,wall-time,$ELAPSED_TIME,s" >> "$OUT_FILE"
      done
    done
  fi

done

echo "✅ Scalability test finished. Results in: $OUT_FILE"
