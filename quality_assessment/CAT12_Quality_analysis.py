#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CAT12 Quality Metrics Analysis
Analysiert Qualitätsmetriken aus CAT12 XML-Dateien über mehrere Kohorten
mit statistischen Tests für Kohorten-Unterschiede
"""

import os
import xml.etree.ElementTree as ET
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from pathlib import Path
from typing import Dict, List
from scipy import stats
import warnings
warnings.filterwarnings('ignore')

# Plotting Style
plt.style.use('seaborn-v0_8-darkgrid')
sns.set_palette("husl")

#%% ========== KONFIGURATION ==========

# Basispfad zu den MRI-Daten (READ-ONLY)
BASE_PATH = Path("/net/data.isilon/ag-cherrmann/stumrani/mri_prep")

# Output-Pfad für Ergebnisse
OUTPUT_PATH = Path("/net/data.isilon/ag-cherrmann/lduttenhoefer/project/CAT12_newvals")

# Kohorten, die analysiert werden sollen
COHORTS = ['ixinii', 'ixiiii', 'mcicnii', 'cobrenii', 'NSSnii', 'NUdatanii', 'SRBPSnii', 'whitecatnii']

# Metriken mit Richtung (höher/niedriger = besser)
# Wir verwenden die NORMALISIERTEN Rating-Werte aus <qualityratings> für Qualitätsvergleiche
METRICS_INFO = {
    'IQR_rating': {'label': 'Image Quality Rating', 'better': 'lower', 'unit': '', 
                   'description': 'Gesamtbewertung der Bildqualität (niedriger = besser, ~1-2 = gut)'},
    'SIQR_rating': {'label': 'Surface IQR Rating', 'better': 'lower', 'unit': '',
                    'description': 'Oberflächenqualität (niedriger = besser, ~2 = gut)'},
    'SurfaceEulerNumber_rating': {'label': 'Surface Euler Number (Rating)', 'better': 'lower', 'unit': '',
                                   'description': 'Topologische Qualität normalisiert (~1-2 = gut, >3 = problematisch)'},
    'SurfaceDefectArea_rating': {'label': 'Surface Defect Area (Rating)', 'better': 'lower', 'unit': '',
                                  'description': 'Defektfläche normalisiert (niedriger = besser)'},
    'SurfaceIntensityRMSE': {'label': 'Surface Intensity RMSE', 'better': 'lower', 'unit': '',
                             'description': 'Fehler der Intensitätswerte an Gewebegrenzen'},
    'SurfacePositionRMSE': {'label': 'Surface Position RMSE', 'better': 'lower', 'unit': '',
                            'description': 'Räumlicher Fehler der Oberflächenpositionierung'},
    'NCR': {'label': 'Noise-to-Contrast Ratio', 'better': 'lower', 'unit': '',
            'description': 'Rauschen relativ zum Kontrast (<0.1 = sehr gut)'},
    'ICR': {'label': 'Inhomogeneity-to-Contrast Ratio', 'better': 'lower', 'unit': '',
            'description': 'Feldinhomogenitäten relativ zum Kontrast (<0.2 = gut)'},
    'contrast': {'label': 'Contrast (absolute)', 'better': 'higher', 'unit': '',
                 'description': 'Absoluter Kontrast zwischen Gewebeklassen (höher = besser)'},
    'contrastr': {'label': 'Contrast Ratio (normalized)', 'better': 'higher', 'unit': '',
                  'description': 'Normalisierter Kontrast (0.2-0.4 = typisch)'},
}

#%% ========== FUNKTIONEN ==========

def parse_xml_file(xml_path: Path) -> Dict:
    """
    Parst eine CAT12 XML-Datei und extrahiert relevante Metriken
    """
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        
        data = {
            'filename': xml_path.name,
            'filepath': str(xml_path)
        }
        
        # Qualitätsmessungen (qualitymeasures) - ROHE WERTE
        qm = root.find('qualitymeasures')
        if qm is not None:
            for metric in ['SurfaceEulerNumber', 'SurfaceDefectArea', 'SurfaceDefectNumber',
                          'SurfaceIntensityRMSE', 'SurfacePositionRMSE', 'NCR', 'ICR',
                          'contrast', 'contrastr']:
                elem = qm.find(metric)
                if elem is not None and elem.text:
                    try:
                        # Verwende die ROHEN Werte aus qualitymeasures
                        data[metric] = float(elem.text)
                    except ValueError:
                        data[metric] = np.nan
                else:
                    data[metric] = np.nan
        
        # Qualitätsbewertungen (qualityratings)
        qr = root.find('qualityratings')
        if qr is not None:
            for metric in ['IQR', 'SIQR', 'SurfaceEulerNumber', 'SurfaceDefectArea']:
                elem = qr.find(metric)
                if elem is not None and elem.text:
                    try:
                        data[f'{metric}_rating'] = float(elem.text)
                    except ValueError:
                        data[f'{metric}_rating'] = np.nan
        
        # Subject measures
        sm = root.find('subjectmeasures')
        if sm is not None:
            for metric in ['vol_TIV', 'surf_TSA']:
                elem = sm.find(metric)
                if elem is not None and elem.text:
                    try:
                        data[metric] = float(elem.text)
                    except ValueError:
                        data[metric] = np.nan
                else:
                    data[metric] = np.nan
        
        return data
        
    except Exception as e:
        print(f"Fehler beim Parsen von {xml_path}: {e}")
        return None


def collect_data_from_cohorts(base_path: Path, cohorts: List[str]) -> pd.DataFrame:
    """Sammelt Daten aus allen Kohorten"""
    all_data = []
    
    for cohort in cohorts:
        cohort_path = base_path / cohort / 'report'
        
        if not cohort_path.exists():
            print(f"Warnung: Pfad existiert nicht: {cohort_path}")
            continue
        
        xml_files = list(cohort_path.glob('cat_*.xml'))
        
        if not xml_files:
            print(f"Warnung: Keine XML-Dateien in {cohort_path}")
            continue
        
        print(f"Verarbeite {cohort}: {len(xml_files)} Dateien gefunden")
        
        for xml_file in xml_files:
            data = parse_xml_file(xml_file)
            if data:
                data['cohort'] = cohort
                all_data.append(data)
    
    if not all_data:
        print("Keine Daten gefunden!")
        return pd.DataFrame()
    
    df = pd.DataFrame(all_data)
    print(f"\nInsgesamt {len(df)} Datensätze aus {df['cohort'].nunique()} Kohorten geladen")
    
    return df


def perform_statistical_tests(df: pd.DataFrame, metric: str) -> pd.DataFrame:
    """
    Führt statistische Tests durch, um signifikante Unterschiede zwischen Kohorten zu finden
    
    Returns:
    --------
    pd.DataFrame mit Testergebnissen
    """
    # Kruskal-Wallis Test (non-parametrisch, besser für nicht-normale Verteilungen)
    cohorts_data = [group[metric].dropna().values for name, group in df.groupby('cohort')]
    
    if len(cohorts_data) < 2:
        return None
    
    # Entferne leere Gruppen
    cohorts_data = [data for data in cohorts_data if len(data) > 0]
    
    if len(cohorts_data) < 2:
        return None
    
    try:
        h_stat, p_value = stats.kruskal(*cohorts_data)
        
        # Paarweise Post-hoc Tests (Mann-Whitney U)
        cohort_names = df['cohort'].unique()
        posthoc_results = []
        
        for i, cohort1 in enumerate(cohort_names):
            for cohort2 in cohort_names[i+1:]:
                data1 = df[df['cohort'] == cohort1][metric].dropna()
                data2 = df[df['cohort'] == cohort2][metric].dropna()
                
                if len(data1) > 0 and len(data2) > 0:
                    u_stat, p_val = stats.mannwhitneyu(data1, data2, alternative='two-sided')
                    
                    posthoc_results.append({
                        'Cohort_1': cohort1,
                        'Cohort_2': cohort2,
                        'U_statistic': u_stat,
                        'p_value': p_val,
                        'significant': 'Ja' if p_val < 0.05 else 'Nein',
                        'mean_1': data1.mean(),
                        'mean_2': data2.mean(),
                        'median_1': data1.median(),
                        'median_2': data2.median()
                    })
        
        posthoc_df = pd.DataFrame(posthoc_results)
        posthoc_df = posthoc_df.sort_values('p_value')
        
        return {
            'kruskal_h': h_stat,
            'kruskal_p': p_value,
            'significant_overall': 'Ja' if p_value < 0.05 else 'Nein',
            'posthoc': posthoc_df
        }
    
    except Exception as e:
        print(f"Fehler bei statistischen Tests für {metric}: {e}")
        return None


def print_statistical_summary(df: pd.DataFrame, output_path: Path):
    """
    Erstellt eine umfassende statistische Zusammenfassung mit Tests
    """
    print("\n" + "="*80)
    print("STATISTISCHE ANALYSE DER KOHORTEN-UNTERSCHIEDE")
    print("="*80)
    
    results_summary = []
    
    for metric, info in METRICS_INFO.items():
        if metric not in df.columns:
            continue
        
        print(f"\n{'='*80}")
        print(f"Metrik: {info['label']} ({metric})")
        print(f"Besser ist: {info['better']}")
        print(f"{'='*80}")
        
        # Deskriptive Statistik pro Kohorte
        desc_stats = df.groupby('cohort')[metric].agg(['count', 'mean', 'std', 'median', 'min', 'max'])
        print("\nDeskriptive Statistik pro Kohorte:")
        print(desc_stats.round(4))
        
        # Statistische Tests
        test_results = perform_statistical_tests(df, metric)
        
        if test_results:
            print(f"\nKruskal-Wallis Test:")
            print(f"  H-Statistik: {test_results['kruskal_h']:.4f}")
            print(f"  p-Wert: {test_results['kruskal_p']:.6f}")
            print(f"  Signifikant unterschiedlich: {test_results['significant_overall']}")
            
            if test_results['significant_overall'] == 'Ja':
                print(f"\nSignifikante paarweise Unterschiede (p < 0.05):")
                sig_pairs = test_results['posthoc'][test_results['posthoc']['significant'] == 'Ja']
                
                if len(sig_pairs) > 0:
                    for _, row in sig_pairs.iterrows():
                        print(f"  {row['Cohort_1']} vs {row['Cohort_2']}: p={row['p_value']:.6f}")
                        print(f"    Mean: {row['mean_1']:.4f} vs {row['mean_2']:.4f}")
                        print(f"    Median: {row['median_1']:.4f} vs {row['median_2']:.4f}")
                else:
                    print("  Keine signifikanten paarweisen Unterschiede nach Bonferroni-Korrektur")
            
            # Für Zusammenfassung
            results_summary.append({
                'Metric': info['label'],
                'Better_is': info['better'],
                'Overall_p_value': test_results['kruskal_p'],
                'Significant': test_results['significant_overall'],
                'N_significant_pairs': len(test_results['posthoc'][test_results['posthoc']['significant'] == 'Ja']),
                'Best_cohort': desc_stats['mean'].idxmin() if info['better'] == 'lower' else desc_stats['mean'].idxmax(),
                'Worst_cohort': desc_stats['mean'].idxmax() if info['better'] == 'lower' else desc_stats['mean'].idxmin()
            })
    
    # Zusammenfassung speichern
    summary_df = pd.DataFrame(results_summary)
    summary_df.to_csv(output_path / 'statistical_summary.csv', index=False)
    print(f"\nStatistische Zusammenfassung gespeichert: {output_path / 'statistical_summary.csv'}")
    
    return summary_df


def identify_problematic_scans(df: pd.DataFrame, output_path: Path, severity_threshold: int = 2):
    """
    Identifiziert problematische Scans basierend auf Qualitätsmetriken
    
    Parameters:
    -----------
    severity_threshold : int
        Mindestanzahl von Problemen, damit ein Scan als problematisch gilt (default: 2)
    """
    print("\n" + "="*80)
    print("IDENTIFIKATION PROBLEMATISCHER SCANS")
    print("="*80)
    print(f"\nKriterien (Scan ist problematisch wenn >= {severity_threshold} Kriterien erfüllt):")
    print("  1. SurfaceEulerNumber_rating > 4.0 (topologische Qualität)")
    print("  2. SurfaceDefectArea_rating > 2.5 (Oberflächendefekte)")
    print("  3. IQR_rating > 3.0 (Gesamtqualität)")
    print("  4. NCR > 0.20 (Rauschen)")
    print("  5. ICR > 1.0 (Feldinhomogenität)")
    
    problems = []
    
    for idx, row in df.iterrows():
        issues = []
        severity_scores = []
        
        # 1. Euler Number Rating (Grenzwert: 4.0)
        if pd.notna(row.get('SurfaceEulerNumber_rating')):
            euler = row['SurfaceEulerNumber_rating']
            if euler > 5.0:
                issues.append(f"Euler Rating sehr hoch ({euler:.2f})")
                severity_scores.append(2)  # Doppelt gewichtet bei >5
            elif euler > 4.0:
                issues.append(f"Euler Rating erhöht ({euler:.2f})")
                severity_scores.append(1)
        
        # 2. Defekt-Area Rating (Grenzwert: 2.5)
        if pd.notna(row.get('SurfaceDefectArea_rating')):
            defect = row['SurfaceDefectArea_rating']
            if defect > 2.5:
                issues.append(f"Defekt-Area Rating hoch ({defect:.2f})")
                severity_scores.append(1)
        
        # 3. IQR (Grenzwert: 3.0)
        if pd.notna(row.get('IQR_rating')):
            iqr = row['IQR_rating']
            if iqr > 3.5:
                issues.append(f"IQR sehr niedrig ({iqr:.2f})")
                severity_scores.append(2)
            elif iqr > 3.0:
                issues.append(f"IQR niedrig ({iqr:.2f})")
                severity_scores.append(1)
        
        # 4. NCR - Rauschen (Grenzwert: 0.20)
        if pd.notna(row.get('NCR')):
            ncr = row['NCR']
            if ncr > 0.25:
                issues.append(f"Sehr hohes Rauschen (NCR={ncr:.3f})")
                severity_scores.append(2)
            elif ncr > 0.20:
                issues.append(f"Hohes Rauschen (NCR={ncr:.3f})")
                severity_scores.append(1)
        
        # 5. ICR - Inhomogenität (Grenzwert: 1.0)
        if pd.notna(row.get('ICR')):
            icr = row['ICR']
            if icr > 1.5:
                issues.append(f"Sehr hohe Inhomogenität (ICR={icr:.3f})")
                severity_scores.append(2)
            elif icr > 1.0:
                issues.append(f"Hohe Inhomogenität (ICR={icr:.3f})")
                severity_scores.append(1)
        
        # Scan ist nur problematisch, wenn genug Issues vorhanden
        total_severity = sum(severity_scores)
        if total_severity >= severity_threshold:
            problems.append({
                'filename': row['filename'],
                'cohort': row['cohort'],
                'n_issues': len(issues),
                'severity_score': total_severity,
                'issues': '; '.join(issues),
                'IQR_rating': row.get('IQR_rating', np.nan),
                'SurfaceEulerNumber_rating': row.get('SurfaceEulerNumber_rating', np.nan),
                'ICR': row.get('ICR', np.nan),
                'NCR': row.get('NCR', np.nan)
            })
    
    if not problems:
        print("\n✓ Keine problematischen Scans gefunden mit diesen Kriterien!")
        problems_df = pd.DataFrame()
    else:
        problems_df = pd.DataFrame(problems)
        problems_df = problems_df.sort_values('severity_score', ascending=False)
        
        print(f"\nGefundene problematische Scans: {len(problems_df)}")
        print(f"Das sind {len(problems_df)/len(df)*100:.1f}% aller Scans")
        
        # Verteilung nach Severity
        print("\nVerteilung nach Severity Score:")
        severity_counts = problems_df['severity_score'].value_counts().sort_index()
        for score, count in severity_counts.items():
            print(f"  Severity {score}: {count} Scans")
        
        print("\nTop 10 problematischste Scans:")
        display_cols = ['filename', 'cohort', 'severity_score', 'n_issues', 'issues']
        print(problems_df.head(10)[display_cols])
    
    # Nach Kohorte
    if not problems_df.empty:
        print("\nProblematische Scans pro Kohorte:")
        cohort_problems = problems_df.groupby('cohort').size()
        cohort_total = df.groupby('cohort').size()
        cohort_pct = (cohort_problems / cohort_total * 100).round(1)
        
        problem_summary = pd.DataFrame({
            'Problematic': cohort_problems,
            'Total': cohort_total,
            'Percentage': cohort_pct
        }).sort_values('Percentage', ascending=False)
        
        print(problem_summary)
        
        # Speichern
        problems_df.to_csv(output_path / 'problematic_scans.csv', index=False)
        problem_summary.to_csv(output_path / 'problematic_scans_by_cohort.csv')
        
        print(f"\nProblematische Scans gespeichert: {output_path / 'problematic_scans.csv'}")
    
    # Zusätzliche Statistik: Schwellenwert-Analyse
    print("\n" + "-"*80)
    print("SCHWELLENWERT-ANALYSE")
    print("-"*80)
    
    thresholds_summary = []
    
    # Zähle wie viele Scans jeden einzelnen Schwellenwert überschreiten
    if 'SurfaceEulerNumber_rating' in df.columns:
        euler_4 = (df['SurfaceEulerNumber_rating'] > 4.0).sum()
        euler_5 = (df['SurfaceEulerNumber_rating'] > 5.0).sum()
        thresholds_summary.append({
            'Metric': 'SurfaceEulerNumber_rating',
            'Threshold': '> 4.0',
            'Count': euler_4,
            'Percentage': f"{euler_4/len(df)*100:.1f}%"
        })
        thresholds_summary.append({
            'Metric': 'SurfaceEulerNumber_rating',
            'Threshold': '> 5.0',
            'Count': euler_5,
            'Percentage': f"{euler_5/len(df)*100:.1f}%"
        })
    
    if 'ICR' in df.columns:
        icr_1 = (df['ICR'] > 1.0).sum()
        icr_15 = (df['ICR'] > 1.5).sum()
        thresholds_summary.append({
            'Metric': 'ICR',
            'Threshold': '> 1.0',
            'Count': icr_1,
            'Percentage': f"{icr_1/len(df)*100:.1f}%"
        })
        thresholds_summary.append({
            'Metric': 'ICR',
            'Threshold': '> 1.5',
            'Count': icr_15,
            'Percentage': f"{icr_15/len(df)*100:.1f}%"
        })
    
    if 'NCR' in df.columns:
        ncr_2 = (df['NCR'] > 0.20).sum()
        ncr_25 = (df['NCR'] > 0.25).sum()
        thresholds_summary.append({
            'Metric': 'NCR',
            'Threshold': '> 0.20',
            'Count': ncr_2,
            'Percentage': f"{ncr_2/len(df)*100:.1f}%"
        })
        thresholds_summary.append({
            'Metric': 'NCR',
            'Threshold': '> 0.25',
            'Count': ncr_25,
            'Percentage': f"{ncr_25/len(df)*100:.1f}%"
        })
    
    if 'IQR_rating' in df.columns:
        iqr_3 = (df['IQR_rating'] > 3.0).sum()
        iqr_35 = (df['IQR_rating'] > 3.5).sum()
        thresholds_summary.append({
            'Metric': 'IQR_rating',
            'Threshold': '> 3.0',
            'Count': iqr_3,
            'Percentage': f"{iqr_3/len(df)*100:.1f}%"
        })
        thresholds_summary.append({
            'Metric': 'IQR_rating',
            'Threshold': '> 3.5',
            'Count': iqr_35,
            'Percentage': f"{iqr_35/len(df)*100:.1f}%"
        })
    
    thresholds_df = pd.DataFrame(thresholds_summary)
    print("\nAnzahl Scans über verschiedenen Schwellenwerten:")
    print(thresholds_df.to_string(index=False))
    thresholds_df.to_csv(output_path / 'threshold_analysis.csv', index=False)


def create_visualizations(df: pd.DataFrame, output_path: Path):
    """Erstellt Visualisierungen mit statistischen Annotationen"""
    output_path.mkdir(parents=True, exist_ok=True)
    
    # 1. IQR Distribution mit statistischen Tests
    print("\nErstelle Visualisierung 1: IQR Verteilung mit Statistik...")
    fig, axes = plt.subplots(2, 1, figsize=(14, 10))
    
    if 'IQR_rating' in df.columns:
        # Boxplot mit Signifikanz-Markierungen
        df.boxplot(column='IQR_rating', by='cohort', ax=axes[0])
        axes[0].set_title('IQR (Image Quality Rating) pro Kohorte\n(Niedriger = Besser)', 
                         fontsize=14, fontweight='bold')
        axes[0].set_xlabel('Kohorte', fontsize=12)
        axes[0].set_ylabel('IQR Rating', fontsize=12)
        plt.sca(axes[0])
        plt.xticks(rotation=45, ha='right')
        
        # Statistik durchführen
        test_results = perform_statistical_tests(df, 'IQR_rating')
        if test_results and test_results['significant_overall'] == 'Ja':
            axes[0].text(0.02, 0.98, f"Kruskal-Wallis p={test_results['kruskal_p']:.4f} *", 
                        transform=axes[0].transAxes, verticalalignment='top',
                        bbox=dict(boxstyle='round', facecolor='yellow', alpha=0.5))
        
        # Violin plot
        sns.violinplot(data=df, x='cohort', y='IQR_rating', ax=axes[1])
        axes[1].set_title('IQR Verteilung (Violin Plot)', fontsize=14, fontweight='bold')
        axes[1].set_xlabel('Kohorte', fontsize=12)
        axes[1].set_ylabel('IQR Rating', fontsize=12)
        axes[1].tick_params(axis='x', rotation=45)
    
    plt.tight_layout()
    plt.savefig(output_path / '01_IQR_distribution.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 2. Surface Quality Metrics
    print("Erstelle Visualisierung 2: Surface Quality Metriken...")
    fig, axes = plt.subplots(2, 2, figsize=(16, 12))
    
    surface_metrics = [
        ('SurfaceEulerNumber_rating', 'Surface Euler Number Rating\n(Niedriger = Besser, ~1-2 = gut)'),
        ('SurfaceDefectArea_rating', 'Surface Defect Area Rating\n(Niedriger = Besser)'),
        ('SurfaceIntensityRMSE', 'Surface Intensity RMSE\n(Niedriger = Besser)'),
        ('SurfacePositionRMSE', 'Surface Position RMSE\n(Niedriger = Besser)')
    ]
    
    for idx, (metric, title) in enumerate(surface_metrics):
        if metric in df.columns:
            ax = axes[idx // 2, idx % 2]
            df.boxplot(column=metric, by='cohort', ax=ax)
            ax.set_title(title, fontsize=11, fontweight='bold')
            ax.set_xlabel('Kohorte', fontsize=10)
            ax.set_ylabel(metric, fontsize=10)
            ax.tick_params(axis='x', rotation=45)
            
            # Statistik
            test_results = perform_statistical_tests(df, metric)
            if test_results and test_results['significant_overall'] == 'Ja':
                ax.text(0.02, 0.98, f"p={test_results['kruskal_p']:.4f} *", 
                       transform=ax.transAxes, verticalalignment='top',
                       bbox=dict(boxstyle='round', facecolor='yellow', alpha=0.5),
                       fontsize=8)
    
    plt.tight_layout()
    plt.savefig(output_path / '02_surface_quality_metrics.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 3. Noise and Contrast Metrics
    print("Erstelle Visualisierung 3: Noise und Contrast Metriken...")
    fig, axes = plt.subplots(1, 3, figsize=(18, 5))
    
    contrast_metrics = [
        ('NCR', 'Noise-to-Contrast Ratio\n(Niedriger = Besser)'),
        ('ICR', 'Inhomogeneity-to-Contrast Ratio\n(Niedriger = Besser)'),
        ('contrast', 'Contrast\n(Höher = Besser)')
    ]
    
    for idx, (metric, title) in enumerate(contrast_metrics):
        if metric in df.columns:
            df.boxplot(column=metric, by='cohort', ax=axes[idx])
            axes[idx].set_title(title, fontsize=11, fontweight='bold')
            axes[idx].set_xlabel('Kohorte', fontsize=10)
            axes[idx].set_ylabel(metric, fontsize=10)
            axes[idx].tick_params(axis='x', rotation=45)
            
            # Statistik
            test_results = perform_statistical_tests(df, metric)
            if test_results and test_results['significant_overall'] == 'Ja':
                axes[idx].text(0.02, 0.98, f"p={test_results['kruskal_p']:.4f} *", 
                              transform=axes[idx].transAxes, verticalalignment='top',
                              bbox=dict(boxstyle='round', facecolor='yellow', alpha=0.5),
                              fontsize=8)
    
    plt.tight_layout()
    plt.savefig(output_path / '03_noise_contrast_metrics.png', dpi=300, bbox_inches='tight')
    plt.close()
    
    # 4. Cohort Comparison Heatmap
    print("Erstelle Visualisierung 4: Kohorten-Vergleich Heatmap...")
    metrics_for_heatmap = ['IQR_rating', 'SurfaceEulerNumber_rating', 'SurfaceDefectArea_rating', 
                           'NCR', 'ICR', 'SurfaceIntensityRMSE']
    available = [m for m in metrics_for_heatmap if m in df.columns]
    
    if available:
        cohort_means = df.groupby('cohort')[available].mean()
        
        fig, ax = plt.subplots(figsize=(12, 8))
        sns.heatmap(cohort_means.T, annot=True, fmt='.3f', cmap='RdYlGn_r', 
                   ax=ax, cbar_kws={'label': 'Wert'})
        ax.set_title('Durchschnittswerte pro Kohorte\n(Je nach Metrik: Rot = Schlechter, Grün = Besser)', 
                    fontsize=13, fontweight='bold')
        ax.set_xlabel('Kohorte', fontsize=11)
        ax.set_ylabel('Metrik', fontsize=11)
        plt.tight_layout()
        plt.savefig(output_path / '04_cohort_comparison_heatmap.png', dpi=300, bbox_inches='tight')
        plt.close()
    
    # 5. Distribution Overview
    print("Erstelle Visualisierung 5: Verteilungsübersicht...")
    key_metrics = ['IQR_rating', 'SurfaceEulerNumber_rating', 'NCR', 'ICR']
    available_metrics = [m for m in key_metrics if m in df.columns]
    
    if available_metrics:
        fig, axes = plt.subplots(2, 2, figsize=(14, 10))
        axes = axes.flatten()
        
        for idx, metric in enumerate(available_metrics[:4]):
            df[metric].hist(bins=30, ax=axes[idx], edgecolor='black', alpha=0.7)
            axes[idx].set_title(f'Verteilung: {metric}', fontsize=11, fontweight='bold')
            axes[idx].set_xlabel(metric, fontsize=10)
            axes[idx].set_ylabel('Häufigkeit', fontsize=10)
            axes[idx].axvline(df[metric].mean(), color='red', linestyle='--', 
                            linewidth=2, label=f'Mean: {df[metric].mean():.2f}')
            axes[idx].axvline(df[metric].median(), color='green', linestyle='--', 
                            linewidth=2, label=f'Median: {df[metric].median():.2f}')
            axes[idx].legend()
        
        plt.tight_layout()
        plt.savefig(output_path / '05_distribution_overview.png', dpi=300, bbox_inches='tight')
        plt.close()
    
    print("Alle Visualisierungen gespeichert!")


def save_summary_tables(df: pd.DataFrame, output_path: Path):
    """Speichert Zusammenfassungstabellen"""
    print("\nSpeichere Zusammenfassungstabellen...")
    
    # 1. Komplette Daten
    df.to_csv(output_path / 'complete_data.csv', index=False)
    print(f"  Komplette Daten: {output_path / 'complete_data.csv'}")
    
    # 2. Statistik pro Kohorte
    numeric_cols = df.select_dtypes(include=[np.number]).columns
    summary_stats = df.groupby('cohort')[numeric_cols].agg(['mean', 'median', 'std', 'min', 'max', 'count'])
    summary_stats.to_csv(output_path / 'summary_by_cohort.csv')
    print(f"  Statistik pro Kohorte: {output_path / 'summary_by_cohort.csv'}")
    
    # 3. Gesamtstatistik
    overall_stats = df[numeric_cols].describe()
    overall_stats.to_csv(output_path / 'overall_statistics.csv')
    print(f"  Gesamtstatistik: {output_path / 'overall_statistics.csv'}")
    
    # 4. Kohorten-Übersicht
    cohort_overview = pd.DataFrame({
        'Kohorte': df['cohort'].value_counts().index,
        'Anzahl_Patienten': df['cohort'].value_counts().values
    })
    cohort_overview.to_csv(output_path / 'cohort_overview.csv', index=False)
    print(f"  Kohorten-Übersicht: {output_path / 'cohort_overview.csv'}")
    
    print("Alle Tabellen gespeichert!")


#%% ========== HAUPTPROGRAMM ==========

if __name__ == "__main__":
    print("="*80)
    print("CAT12 QUALITÄTSMETRIKEN ANALYSE MIT STATISTISCHEN TESTS")
    print("="*80)
    print(f"\nBasispfad (READ-ONLY): {BASE_PATH}")
    print(f"Output-Pfad: {OUTPUT_PATH}")
    print(f"Kohorten: {', '.join(COHORTS)}")
    
    # Erstelle Output-Verzeichnis
    OUTPUT_PATH.mkdir(parents=True, exist_ok=True)
    
    # Sammle Daten
    print("\n" + "="*80)
    print("DATEN SAMMELN")
    print("="*80)
    df = collect_data_from_cohorts(BASE_PATH, COHORTS)
    
    if df.empty:
        print("\nKeine Daten gefunden. Programm wird beendet.")
        exit(1)
    
    # Statistische Analyse
    summary_df = print_statistical_summary(df, OUTPUT_PATH)
    
    # Problematische Scans identifizieren (mit Severity-Schwellenwert 2)
    identify_problematic_scans(df, OUTPUT_PATH, severity_threshold=2)
    
    # Visualisierungen erstellen
    print("\n" + "="*80)
    print("VISUALISIERUNGEN ERSTELLEN")
    print("="*80)
    create_visualizations(df, OUTPUT_PATH)
    
    # Tabellen speichern
    print("\n" + "="*80)
    print("TABELLEN SPEICHERN")
    print("="*80)
    save_summary_tables(df, OUTPUT_PATH)
    
    print("\n" + "="*80)
    print("ANALYSE ABGESCHLOSSEN!")
    print("="*80)
    print(f"\nErgebnisse in: {OUTPUT_PATH}")
    print("\nErstellt Dateien:")
    print("  • complete_data.csv - Alle Daten")
    print("  • summary_by_cohort.csv - Statistiken pro Kohorte")
    print("  • overall_statistics.csv - Gesamtstatistiken")
    print("  • statistical_summary.csv - Statistische Tests zwischen Kohorten")
    print("  • problematic_scans.csv - Liste problematischer Scans (Severity >= 2)")
    print("  • problematic_scans_by_cohort.csv - Probleme pro Kohorte")
    print("  • threshold_analysis.csv - Schwellenwert-Analyse")
    print("  • cohort_overview.csv - Übersicht")
    print("  • 01-05 PNG-Grafiken mit statistischen Annotationen")
    print("\n" + "="*80)
    print("WICHTIGE SCHWELLENWERTE IN DIESEM SCRIPT:")
    print("="*80)
    print("Scan gilt als problematisch wenn Severity Score >= 2:")
    print("  • SurfaceEulerNumber_rating > 4.0 (Severity +1, >5.0 = +2)")
    print("  • SurfaceDefectArea_rating > 2.5 (Severity +1)")
    print("  • IQR_rating > 3.0 (Severity +1, >3.5 = +2)")
    print("  • NCR > 0.20 (Severity +1, >0.25 = +2)")
    print("  • ICR > 1.0 (Severity +1, >1.5 = +2)")