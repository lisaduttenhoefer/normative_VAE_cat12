#!/bin/bash
################################################################################
# SALD DATASET DOWNLOAD - COMPLETE STEP-BY-STEP GUIDE
# Downloads raw T1-weighted MRI from Southwest University Adult Lifespan Dataset
################################################################################

# ============================================================================
# KONFIGURATION
# ============================================================================
TARGET_DIR="/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals/new_hc_data/SALD"
S3_BASE="s3://fcp-indi/data/Projects/INDI/SALD/RawData_BIDS"

DECOMPRESS=false      # true = .nii (30MB/file), false = .nii.gz (10MB/file)
FLATTEN=true         # true = alle Dateien in einem Ordner
MAX_SUBJECTS=0       # 0 = alle, 5 = nur erste 5 zum Testen

echo "════════════════════════════════════════════════════════════════"
echo "  SALD DATASET DOWNLOAD"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Zielordner:        $TARGET_DIR"
echo "Dekomprimieren:    $DECOMPRESS"
echo "Max. Probanden:    $([ $MAX_SUBJECTS -eq 0 ] && echo "alle" || echo $MAX_SUBJECTS)"
echo ""

# ============================================================================
# VORAUSSETZUNGEN PRÜFEN
# ============================================================================
echo "════════════════════════════════════════════════════════════════"
echo "  Voraussetzungen prüfen"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Verfügbarer Speicherplatz:"
df -h $(dirname "$TARGET_DIR") | awk 'NR==1 {print "  " $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5} NR==2 {print "  " $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5}'
echo ""

if command -v aws &> /dev/null; then
    echo "✓ AWS CLI gefunden: $(aws --version)"
else
    echo "✗ AWS CLI nicht gefunden!"
    echo ""
    echo "Installation mit: pip install awscli --user"
    exit 1
fi

# ============================================================================
# AWS KONFIGURIEREN
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  AWS für anonymen Zugriff konfigurieren"
echo "════════════════════════════════════════════════════════════════"

aws configure set default.s3.signature_version s3v4
aws configure set default.region us-east-1
echo "✓ AWS konfiguriert"

# ============================================================================
# ZIELORDNER ERSTELLEN
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Zielordner erstellen"
echo "════════════════════════════════════════════════════════════════"

mkdir -p "$TARGET_DIR"
echo "✓ Ordner erstellt: $TARGET_DIR"

# ============================================================================
# PROBANDENLISTE ABRUFEN
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Probandenliste von S3 abrufen"
echo "════════════════════════════════════════════════════════════════"

TEMP_LIST="/tmp/sald_subjects_$(date +%s).txt"

echo "Verbinde mit S3..."
aws s3 ls $S3_BASE/ --no-sign-request 2>/dev/null | grep "PRE sub-" | awk '{print $2}' | sed 's/\///' > "$TEMP_LIST"

if [ ! -s "$TEMP_LIST" ]; then
    echo "✗ Fehler: Keine Probanden gefunden"
    exit 1
fi

TOTAL_SUBJECTS=$(wc -l < "$TEMP_LIST")
echo "✓ ${TOTAL_SUBJECTS} Probanden gefunden"

if [ $MAX_SUBJECTS -gt 0 ] && [ $MAX_SUBJECTS -lt $TOTAL_SUBJECTS ]; then
    head -n $MAX_SUBJECTS "$TEMP_LIST" > "${TEMP_LIST}.limited"
    mv "${TEMP_LIST}.limited" "$TEMP_LIST"
    TOTAL_SUBJECTS=$MAX_SUBJECTS
    echo "  → Limitiert auf erste $MAX_SUBJECTS Probanden (Test-Modus)"
fi

echo ""
echo "Erste 5 Probanden:"
head -n 5 "$TEMP_LIST" | while read subj; do echo "  - $subj"; done

# ============================================================================
# DATEIEN HERUNTERLADEN
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  T1-Dateien herunterladen"
echo "════════════════════════════════════════════════════════════════"
echo ""

COUNTER=0
SUCCESS=0
FAILED=0
SKIPPED=0

LOGFILE="$TARGET_DIR/download_log_$(date +%Y%m%d_%H%M%S).txt"
echo "Download gestartet: $(date)" > "$LOGFILE"
echo "Logfile: $LOGFILE"
echo ""

while read SUBJECT; do
    ((COUNTER++))
    
    PERCENT=$((COUNTER * 100 / TOTAL_SUBJECTS))
    printf "[%3d%%] [%4d/%4d] %s ... " "$PERCENT" "$COUNTER" "$TOTAL_SUBJECTS" "$SUBJECT"
    
    if [ "$FLATTEN" = true ]; then
        OUTPUT_FILE="$TARGET_DIR/${SUBJECT}_T1w.nii"
        TEMP_FILE="$TARGET_DIR/${SUBJECT}_T1w.nii.gz"
    else
        SUBJECT_DIR="$TARGET_DIR/$SUBJECT/anat"
        mkdir -p "$SUBJECT_DIR"
        OUTPUT_FILE="$SUBJECT_DIR/${SUBJECT}_T1w.nii"
        TEMP_FILE="$SUBJECT_DIR/${SUBJECT}_T1w.nii.gz"
    fi
    
    if [ -f "$OUTPUT_FILE" ] || ([ "$DECOMPRESS" = false ] && [ -f "$TEMP_FILE" ]); then
        echo "bereits vorhanden ✓"
        ((SKIPPED++))
        echo "$SUBJECT: bereits vorhanden" >> "$LOGFILE"
        continue
    fi
    
    if aws s3 cp "${S3_BASE}/${SUBJECT}/anat/${SUBJECT}_T1w.nii.gz" "$TEMP_FILE" --no-sign-request --quiet 2>/dev/null; then
        if [ "$DECOMPRESS" = true ]; then
            if gunzip -f "$TEMP_FILE" 2>/dev/null; then
                if [ -f "$OUTPUT_FILE" ]; then
                    echo "heruntergeladen & dekomprimiert ✓"
                    ((SUCCESS++))
                    echo "$SUBJECT: erfolgreich (dekomprimiert)" >> "$LOGFILE"
                else
                    echo "Fehler beim Dekomprimieren ✗"
                    ((FAILED++))
                    echo "$SUBJECT: Fehler beim Dekomprimieren" >> "$LOGFILE"
                fi
            else
                echo "Dekomprimierung fehlgeschlagen ✗"
                ((FAILED++))
                echo "$SUBJECT: Dekomprimierung fehlgeschlagen" >> "$LOGFILE"
            fi
        else
            echo "heruntergeladen ✓"
            ((SUCCESS++))
            echo "$SUBJECT: erfolgreich" >> "$LOGFILE"
        fi
    else
        echo "Download fehlgeschlagen ✗"
        ((FAILED++))
        echo "$SUBJECT: Download fehlgeschlagen" >> "$LOGFILE"
    fi
    
done < "$TEMP_LIST"

# ============================================================================
# ZUSAMMENFASSUNG
# ============================================================================
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ZUSAMMENFASSUNG"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Gesamt:         $TOTAL_SUBJECTS Probanden"
echo "Erfolgreich:    $SUCCESS"
echo "Übersprungen:   $SKIPPED"
echo "Fehlgeschlagen: $FAILED"
echo ""
echo "Speicherort:    $TARGET_DIR"
echo "Logfile:        $LOGFILE"
echo ""

TOTAL_SIZE=$(du -sh "$TARGET_DIR" 2>/dev/null | cut -f1)
echo "Gesamtgröße:    $TOTAL_SIZE"
echo ""

echo "Beispiel-Dateien:"
if [ "$FLATTEN" = true ]; then
    ls -lh "$TARGET_DIR"/*.nii* 2>/dev/null | head -5 | awk '{print "  " $9 " (" $5 ")"}'
else
    find "$TARGET_DIR" -name "*T1w.nii*" 2>/dev/null | head -5 | while read f; do
        SIZE=$(ls -lh "$f" | awk '{print $5}')
        echo "  $(basename $f) ($SIZE)"
    done
fi

echo ""
echo "════════════════════════════════════════════════════════════════"

if [ $SUCCESS -gt 0 ]; then
    echo "✓ Download abgeschlossen!"
    echo ""
    echo "Nächster Schritt: CAT12-Processing"
else
    echo "✗ Keine Dateien erfolgreich heruntergeladen"
    echo "Bitte Log-Datei überprüfen: $LOGFILE"
fi

echo "════════════════════════════════════════════════════════════════"

rm -f "$TEMP_LIST"
exit 0
