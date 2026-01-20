import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import IsolationForest

def analyze_dataset(filename, title='Dataset Analysis'):
    """Analyze and visualize dataset"""
    
    print(f"\n📊 Analyzing: {filename}")
    print("="*60)
    
    try:
        df = pd.read_csv(filename)
    except FileNotFoundError:
        print(f"❌ File not found: {filename}")
        return
    
    print(f"Shape: {df.shape}")
    print(f"\nColumns: {list(df.columns)}")
    print(f"\nFirst few rows:")
    print(df.head())
    print(f"\nStatistics:")
    print(df.describe())
    
    # Check for anomalies
    if 'Anomaly_flag' in df.columns:
        anomaly_count = df['Anomaly_flag'].sum()
        print(f"\n⚠️  Anomalies: {anomaly_count} ({anomaly_count/len(df)*100:.2f}%)")
    elif 'Anomaly' in df.columns:
        anomaly_count = df['Anomaly'].sum()
        print(f"\n⚠️  Anomalies: {anomaly_count} ({anomaly_count/len(df)*100:.2f}%)")
    
    # Detect anomalies using Isolation Forest
    if 'Global_active_power' in df.columns:
        X = df[['Global_active_power']].fillna(df['Global_active_power'].mean())
        iso_forest = IsolationForest(contamination=0.05, random_state=42)
        df['detected_anomaly'] = iso_forest.fit_predict(X)
        detected = (df['detected_anomaly'] == -1).sum()
        print(f"🔍 Detected anomalies: {detected} ({detected/len(df)*100:.2f}%)")
    
    print("="*60)


def visualize_datasets():
    """Create visualizations for all datasets"""
    
    datasets = [
        ('synthetic_training_data.csv', 'Main Training Dataset (1 Year)'),
        ('user_training_low.csv', 'Low Consumption User (90 Days)'),
        ('user_training_medium.csv', 'Medium Consumption User (90 Days)'),
        ('user_training_high.csv', 'High Consumption User (90 Days)'),
        ('user_training_commercial.csv', 'Commercial User (90 Days)'),
    ]
    
    fig, axes = plt.subplots(len(datasets), 1, figsize=(14, 12))
    
    for idx, (filename, title) in enumerate(datasets):
        try:
            df = pd.read_csv(filename)
            
            # Get power column
            if 'Global_active_power' in df.columns:
                power = df['Global_active_power']
            else:
                power = df['Power']
            
            ax = axes[idx] if len(datasets) > 1 else axes
            
            # Plot power consumption
            ax.plot(power, label='Power Consumption', color='blue', alpha=0.7)
            
            # Highlight anomalies
            if 'Anomaly_flag' in df.columns:
                anomalies = df[df['Anomaly_flag'] == 1].index
                ax.scatter(anomalies, power[anomalies], color='red', label='Anomalies', s=50)
            elif 'Anomaly' in df.columns:
                anomalies = df[df['Anomaly'] == 1].index
                ax.scatter(anomalies, power[anomalies], color='red', label='Anomalies', s=50)
            
            ax.set_title(title, fontsize=12, fontweight='bold')
            ax.set_xlabel('Time Index')
            ax.set_ylabel('Power (kW)')
            ax.legend()
            ax.grid(True, alpha=0.3)
            
        except FileNotFoundError:
            ax = axes[idx] if len(datasets) > 1 else axes
            ax.text(0.5, 0.5, f'File not found: {filename}',
                   ha='center', va='center', transform=ax.transAxes)
    
    plt.tight_layout()
    plt.savefig('dataset_analysis.png', dpi=300, bbox_inches='tight')
    print("\n📈 Visualization saved: dataset_analysis.png")
    plt.show()


if __name__ == '__main__':
    # Analyze all datasets
    datasets_to_analyze = [
        'synthetic_training_data.csv',
        'user_training_low.csv',
        'user_training_medium.csv',
        'user_training_high.csv',
        'user_training_commercial.csv',
    ]
    
    print("\n" + "="*60)
    print("📊 DATASET ANALYSIS")
    print("="*60)
    
    for dataset in datasets_to_analyze:
        analyze_dataset(dataset)
    
    # Create visualizations
    print("\n🎨 Creating visualizations...")
    visualize_datasets()
    
    print("\n✅ Analysis complete!")
