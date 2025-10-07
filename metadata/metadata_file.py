import pandas as pd
import numpy as np
import re

# Dateipfade
input_path = '/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/metadata/merged_metadata.csv'
output_path = '/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/metadata/merged_metadata_processed.csv'

# Daten einlesen
print("Lade merged metadata...")
df = pd.read_csv(input_path)
print(f"Daten geladen: {len(df)} Zeilen, {len(df.columns)} Spalten")

# ==================== STEP 1: Usage_original entfernen ====================
print("\n" + "="*60)
print("STEP 1: Entferne Usage_original Spalte")
print("="*60)

if 'Usage_original' in df.columns:
    df = df.drop(columns=['Usage_original'])
    print("✓ Usage_original Spalte entfernt")
else:
    print("Info: Usage_original Spalte nicht vorhanden")

# ==================== STEP 2: Sex_int erstellen ====================
print("\n" + "="*60)
print("STEP 2: Erstelle Sex_int (0.0=female, 1.0=male)")
print("="*60)

df['Sex_int'] = df['Sex'].apply(lambda x: 
    0.0 if pd.notna(x) and str(x).strip().lower() in ['female', 'f'] 
    else (1.0 if pd.notna(x) and str(x).strip().lower() in ['male', 'm'] 
    else np.nan)
)
print("✓ Sex_int Spalte erstellt")
print(f"  Female (0.0): {(df['Sex_int'] == 0.0).sum()}")
print(f"  Male (1.0): {(df['Sex_int'] == 1.0).sum()}")
print(f"  Missing: {df['Sex_int'].isna().sum()}")

# ==================== STEP 3: ICD10 Codes auswerten ====================
print("\n" + "="*60)
print("STEP 3: Werte ICD10 Codes aus")
print("="*60)

def evaluate_icd10_to_codiagnosis(code):
    """
    Wertet ICD10 Codes aus für Co_Diagnosis:
    F20-F25: SCHZ
    F31: BP
    F32-F34: MDD
    Andere F-Codes: FSCOREMISSING
    Kein Wert: leer lassen
    """
    if pd.isna(code):
        return None
    
    # Code als String behandeln
    code_str = str(code).strip().upper()
    
    # Prüfe auf F31 (inkl. F31.x)
    if code_str.startswith('F31'):
        return 'BP'
    
    # Extrahiere F-Code Nummer
    match = re.match(r'F(\d+)', code_str)
    if not match:
        return None
    
    f_number = int(match.group(1))
    
    if 20 <= f_number <= 25:
        return 'SCHZ'
    elif 32 <= f_number <= 34:
        return 'MDD'
    else:
        return 'FSCOREMISSING'

# Erstelle Co_Diagnosis Spalte falls nicht vorhanden
if 'Co_Diagnosis' not in df.columns:
    df['Co_Diagnosis'] = ''

# Werte ICD10 Codes aus und schreibe in Co_Diagnosis
icd_processed = 0
for idx in df.index:
    icd_code = df.loc[idx, 'ICD10_Code']
    
    # Nur verarbeiten wenn ICD10_Code vorhanden
    if pd.notna(icd_code):
        codiagnosis = evaluate_icd10_to_codiagnosis(icd_code)
        if codiagnosis:
            df.loc[idx, 'Co_Diagnosis'] = codiagnosis
            icd_processed += 1

print(f"✓ {icd_processed} ICD10 Codes ausgewertet und in Co_Diagnosis geschrieben")

# Zeige Co_Diagnosis Verteilung
print("\nCo_Diagnosis Verteilung:")
codiag_counts = df[df['Co_Diagnosis'] != '']['Co_Diagnosis'].value_counts()
print(codiag_counts)

# ==================== STEP 4: CTT Patienten verarbeiten ====================
print("\n" + "="*60)
print("STEP 4: Verarbeite CTT Patienten")
print("="*60)

# Identifiziere CTT Patienten
ctt_mask = df['Diagnosis'] == 'CTT'
ctt_count = ctt_mask.sum()

print(f"Gefundene CTT Patienten: {ctt_count}")

if ctt_count > 0:
    updated_count = 0
    for idx in df[ctt_mask].index:
        codiagnosis = df.loc[idx, 'Co_Diagnosis']
        
        if pd.notna(codiagnosis) and codiagnosis != '':
            # Setze Diagnosis auf CTT-{Codiagnosis}
            df.loc[idx, 'Diagnosis'] = f'CTT-{codiagnosis}'
            updated_count += 1
            print(f"  Patient {idx}: CTT → CTT-{codiagnosis} (Co_Diagnosis: {codiagnosis})")
    
    print(f"\n✓ {updated_count} CTT Patienten mit Co_Diagnosis aktualisiert")
    
    # Zeige CTT Patienten ohne Co_Diagnosis
    ctt_no_codiag = df[(df['Diagnosis'] == 'CTT') & ((df['Co_Diagnosis'] == '') | df['Co_Diagnosis'].isna())]
    if len(ctt_no_codiag) > 0:
        print(f"\nWarnung: {len(ctt_no_codiag)} CTT Patienten haben keine Co_Diagnosis")
else:
    print("Keine CTT Patienten gefunden")

# ==================== SPEICHERN ====================
print("\n" + "="*60)
print("SPEICHERN")
print("="*60)

print(f"\nSpeichere verarbeitete Daten nach: {output_path}")
df.to_csv(output_path, index=False)

print("\n✓ Fertig!")

# ==================== ZUSAMMENFASSUNG ====================
print("\n" + "="*60)
print("ZUSAMMENFASSUNG")
print("="*60)
print(f"Gesamt Patienten: {len(df)}")
print(f"\nDiagnose-Verteilung:")
print(df['Diagnosis'].value_counts())
print(f"\nCo_Diagnosis Verteilung (nicht leer):")
print(df[df['Co_Diagnosis'] != '']['Co_Diagnosis'].value_counts())
print(f"\nSex_int Verteilung:")
print(df['Sex_int'].value_counts())