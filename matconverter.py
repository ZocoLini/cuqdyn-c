import sys
import scipy.io

def mat_to_txt(mat_file, txt_file):
    # Cargar el archivo .mat
    data = scipy.io.loadmat(mat_file)

    # Abrir el archivo de salida
    with open(txt_file, "w") as f:
        for key, value in data.items():
            # Saltar metadatos de MATLAB
            if key.startswith("__"):
                continue
            f.write(f"Variable: {key}\n")
            f.write(f"Contenido:\n{value}\n\n")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Uso: python mat_to_txt.py entrada.mat salida.txt")
    else:
        mat_file = sys.argv[1]
        txt_file = sys.argv[2]
        mat_to_txt(mat_file, txt_file)
        print(f"Archivo {mat_file} convertido en {txt_file}")
