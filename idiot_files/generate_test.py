import pandas as pd
import io
import os

# Die ersten 5 Zeilen des von Ihnen bereitgestellten Metadaten-Screenshots,
# nach Korrektur des fehlerhaften ersten Spaltennamens ('Unnamed: 0').
metadata_data = """Unnamed: 0,Filename,Dataset,Diagnosis,Age,Sex,Usage_original,Sex_int
0,IXI426-IOP-1011-T1,IXI,HC,41.2,Female,training,0
1,IXI571-IOP-1154-T1,IXI,HC,56.6,Female,training,0
2,IXI170-Guys-0843-T1,IXI,HC,50.2,Female,training,0
3,IXI054-Guys-0707-T1,IXI,HC,60.8,Female,training,0
4,IXI196-Guys-0805-T1,IXI,HC,47.8,Female,training,0
"""

# Pfad zur Ausgabedatei
OUTPUT_DIR = "metadata"
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "test_patients_5.csv")

# DataFrame aus dem String erstellen
df = pd.read_csv(io.StringIO(metadata_data))

# Sicherstellen, dass der Output-Ordner existiert
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Wir wählen nur die ersten 5 Zeilen (Index 0 bis 4) aus und speichern sie
df_test = df.iloc[0:5].copy()

# Die erste unnötige Spalte entfernen und die Testdatei speichern
df_test = df_test.drop(columns=['Unnamed: 0'])
df_test.to_csv(OUTPUT_FILE, index=False)