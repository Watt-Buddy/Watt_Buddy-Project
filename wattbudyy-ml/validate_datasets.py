import pandas as pd
import numpy as np
from datetime import datetime

def validate_dataset(filename):
    """Validate dataset integrity and quality"""
    
    print(f"\n✓ Validating: {filename}")
    
    try:
        df = pd.read_csv(filename)
    except Exception as e:
        print(f"❌ Error reading file: {e}")
        return False
    
    checks_passed = 0
    total_checks = 0
    
    # Check 1: No empty dataframe
    total_checks += 1
    if len(df) > 0:
        print(f"  ✓ Dataset not empty: {len(df)} records")
        checks_passed += 1
    else:
        print(f"  ✗ Dataset is empty")
    
    # Check 2: Required columns
    total_checks += 1
    power_col = None
    for col in ['Global_active_power', 'Power']:
        if col in df.columns:
            power_col = col
            break
    
    if power_col:
        print(f"  ✓ Power column found: {power_col}")
        checks_passed += 1
    else:
        print(f"  ✗ No power consumption column found")
    
    # Check 3: No null values in power
    total_checks += 1
    if power_col and df[power_col].isnull().sum() == 0:
        print(f"  ✓ No null values in power data")
        checks_passed += 1
    elif power_col:
        nulls = df[power_col].isnull().sum()
        print(f"  ⚠ {nulls} null values found ({nulls/len(df)*100:.2f}%)")
    
    # Check 4: Power values in reasonable range
    total_checks += 1
    if power_col:
        min_power = df[power_col].min()
        max_power = df[power_col].max()
        if 0 <= min_power and max_power < 1000:
            print(f"  ✓ Power range valid: {min_power:.2f} - {max_power:.2f} kW")
            checks_passed += 1
        else:
            print(f"  ⚠ Power range unusual: {min_power:.2f} - {max_power:.2f} kW")
    
    # Check 5: Anomaly distribution
    total_checks += 1
    anomaly_col = None
    for col in ['Anomaly_flag', 'Anomaly']:
        if col in df.columns:
            anomaly_col = col
            break
    
    if anomaly_col:
        anomaly_pct = df[anomaly_col].mean() * 100
        if 1 <= anomaly_pct <= 10:
            print(f"  ✓ Anomaly distribution good: {anomaly_pct:.2f}%")
            checks_passed += 1
        else:
            print(f"  ⚠ Anomaly distribution unusual: {anomaly_pct:.2f}%")
    
    # Check 6: Data continuity
    total_checks += 1
    if 'Date' in df.columns and 'Time' in df.columns:
        print(f"  ✓ Date/Time columns present")
        checks_passed += 1
    
    # Summary
    print(f"\n  Result: {checks_passed}/{total_checks} checks passed")
    return checks_passed == total_checks


if __name__ == '__main__':
    datasets = [
        'synthetic_training_data.csv',
        'user_training_low.csv',
        'user_training_medium.csv',
        'user_training_high.csv',
        'user_training_commercial.csv',
    ]
    
    print("\n" + "="*60)
    print("🔍 DATASET VALIDATION")
    print("="*60)
    
    all_valid = True
    for dataset in datasets:
        if not validate_dataset(dataset):
            all_valid = False
    
    print("\n" + "="*60)
    if all_valid:
        print("✅ All datasets valid and ready for training!")
    else:
        print("⚠️  Some datasets need attention")
    print("="*60)
