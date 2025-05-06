import sys
from pathlib import Path

import matplotlib.pyplot as plt

def read_data(filepath):
    with open(filepath) as f:
        lines = [line.strip() for line in f if line.strip()]

    sections = {}
    i = 0
    while i < len(lines):
        line = lines[i]

        if line.startswith('[') and line.endswith(']'):
            section = line[1:-1]
            i += 1

            dims = list(map(int, lines[i].split(" ")))
            i += 1

            rows = dims[0]
            cols = dims[1] if len(dims) > 1 else 1

            if len(dims) == 1:
                tmp = cols
                cols = rows
                rows = tmp

            matrix = []
            for _ in range(rows):
                values = list(map(float, lines[i].split(" ")))
                assert len(values) == cols, f"Expected {cols} columns but got {len(values)} for section {section}."
                matrix.append(values if cols > 1 else values[0])
                i += 1

            sections[section] = {
                "shape": (rows, cols),
                "data": matrix
            }
        else:
            i += 1

    return sections

if len(sys.argv) < 2:
    print("Usage: python plot.py <data_file>")
    sys.exit(1)

data_file = sys.argv[1]

ruta = Path(data_file)
if not ruta.is_file():
    print(f"File {ruta} does not exist.")
    sys.exit(1)

data = read_data(ruta)

params = data["Params"]["data"]
data_matrix = data["Data"]["data"]
q_low = data["Q_low"]["data"]
q_up = data["Q_up"]["data"]
times = data["Times"]["data"]

# Crear carpeta de salida
output_folder = ruta.parent

plt.figure(figsize=(8, 6))

plt.xlabel("Times")
plt.ylabel("Values")
plt.legend()
plt.grid(True)

num_colums = len(data_matrix[0])

for j in range(num_colums):
    plt.figure(figsize=(8, 6))

    plt.title(f"Data Plot for y{j}")
    plt.xlabel("Times")
    plt.ylabel("Values")

    plt.plot(range(0, len(data_matrix)), [row[j] for row in data_matrix], '-', label=f"Median y{j}")
    plt.plot(range(0, len(data_matrix)), [row[j] for row in q_low], '--', label=f"Q_low y{j}")
    plt.plot(range(0, len(data_matrix)), [row[j] for row in q_up], '--', label=f"Q_up y{j}")

    plt.legend()
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(f"{output_folder}/y{j}.png", dpi=300)
    plt.close()
