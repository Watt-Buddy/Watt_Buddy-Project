import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import random

def generate_energy_dataset(days=365, output_file='synthetic_training_data.csv'):
    """
    Generate synthetic energy consumption data for ML training
    Creates realistic patterns with anomalies
    """
    
    print("🔄 Generating synthetic energy dataset...")
    
    # Initialize lists
    dates = []
    times = []
    global_active_power = []
    voltage = []
    global_intensity = []
    sub_metering_1 = []
    sub_metering_2 = []
    sub_metering_3 = []
    sub_metering_4 = []
    seasons = []
    anomaly_flags = []
    
    # Start date
    start_date = datetime(2024, 1, 1)
    
    # Season mapping (for India/Kerala)
    def get_season(date):
        month = date.month
        if month in [1, 2]:
            return 'winter'
        elif month in [3, 4, 5]:
            return 'summer'
        elif month in [6, 7, 8, 9]:
            return 'monsoon'
        else:  # 10, 11, 12
            return 'autumn'
    
    # Generate data for each day
    for day in range(days):
        current_date = start_date + timedelta(days=day)
        season = get_season(current_date)
        
        # Generate 96 readings per day (15-minute intervals)
        for interval in range(96):
            # Time calculation
            hour = interval // 4
            minute = (interval % 4) * 15
            
            dates.append(current_date.strftime('%d-%m-%Y'))
            times.append(f"{hour:02d}:{minute:02d}")
            
            # Base power consumption patterns
            base_load = 0.3  # Always-on devices (fridge, etc.)
            
            # Daily pattern (lower at night, peak during day)
            if 6 <= hour < 9:  # Morning peak
                daily_pattern = 1.8
            elif 9 <= hour < 18:  # Day time (reduced peak)
                daily_pattern = 1.2
            elif 18 <= hour < 22:  # Evening peak
                daily_pattern = 2.0
            else:  # Night (lowest)
                daily_pattern = 0.6
            
            # Weekly pattern (weekday vs weekend)
            if current_date.weekday() < 5:  # Weekday
                weekly_pattern = 1.0
            else:  # Weekend
                weekly_pattern = 0.85
            
            # Seasonal adjustment
            if season == 'summer':
                seasonal_pattern = 1.3  # Higher AC usage
            elif season == 'monsoon':
                seasonal_pattern = 0.95
            elif season == 'winter':
                seasonal_pattern = 1.1
            else:  # autumn
                seasonal_pattern = 1.0
            
            # Random variations
            random_noise = np.random.normal(1.0, 0.15)
            
            # Calculate power
            power = base_load + (daily_pattern * weekly_pattern * seasonal_pattern * random_noise)
            power = max(0.1, power)  # Ensure positive
            power_rounded = round(power * 1000, 0)  # Convert to watts
            
            # Voltage (mostly stable around 230V)
            voltage_value = 230 + np.random.normal(0, 2)
            voltage_value = max(200, min(250, voltage_value))
            
            # Current intensity
            intensity = power_rounded / voltage_value
            
            # Sub-metering breakdown (realistic distribution)
            sub1 = power_rounded * 0.35  # Kitchen & lights
            sub2 = power_rounded * 0.30  # HVAC
            sub3 = power_rounded * 0.25  # Water heater
            sub4 = power_rounded * 0.10  # Other appliances
            
            # Anomaly injection (5% of data)
            is_anomaly = 0
            if random.random() < 0.05:
                is_anomaly = 1
                # Create anomalies: sudden spikes or drops
                anomaly_type = random.choice(['spike', 'drop'])
                if anomaly_type == 'spike':
                    power_rounded *= random.uniform(2.5, 4.0)  # 2.5-4x increase
                else:
                    power_rounded *= random.uniform(0.1, 0.3)  # 70-90% decrease
                
                # Adjust sub-metering proportionally
                factor = power_rounded / (power * 1000)
                sub1 *= factor
                sub2 *= factor
                sub3 *= factor
                sub4 *= factor
            
            # Append data
            global_active_power.append(round(power_rounded / 1000, 2))
            voltage.append(round(voltage_value, 1))
            global_intensity.append(round(intensity, 2))
            sub_metering_1.append(round(sub1, 0))
            sub_metering_2.append(round(sub2, 0))
            sub_metering_3.append(round(sub3, 0))
            sub_metering_4.append(round(sub4, 0))
            seasons.append(season)
            anomaly_flags.append(is_anomaly)
    
    # Create DataFrame
    df = pd.DataFrame({
        'Date': dates,
        'Time': times,
        'Global_active_power': global_active_power,
        'Voltage': voltage,
        'Global_intensity': global_intensity,
        'Sub_metering_1': sub_metering_1,
        'Sub_metering_2': sub_metering_2,
        'Sub_metering_3': sub_metering_3,
        'Sub_metering_4': sub_metering_4,
        'Season': seasons,
        'Anomaly_flag': anomaly_flags,
    })
    
    # Save to CSV
    df.to_csv(output_file, index=False)
    
    print(f"✅ Dataset generated successfully!")
    print(f"📊 Total records: {len(df)}")
    print(f"📅 Date range: {dates[0]} to {dates[-1]}")
    print(f"⚠️  Anomalies: {df['Anomaly_flag'].sum()} ({df['Anomaly_flag'].mean()*100:.1f}%)")
    print(f"💾 Saved to: {output_file}")
    print(f"\nDataset Statistics:")
    print(df[['Global_active_power', 'Voltage', 'Global_intensity']].describe())
    
    return df


def generate_user_specific_dataset(user_type='residential', days=90, output_file='user_training_data.csv'):
    """
    Generate user-specific datasets based on consumption patterns
    
    user_type options:
    - 'residential_low': Low-consumption household (500-1500W avg)
    - 'residential_medium': Medium-consumption household (1500-3000W avg)
    - 'residential_high': High-consumption household (3000-5000W avg)
    - 'commercial': Commercial building (5000-20000W avg)
    """
    
    print(f"🔄 Generating {user_type} user dataset...")
    
    # Configuration by user type
    config = {
        'residential_low': {
            'base_load': 0.15,
            'peak_multiplier': 1.2,
            'daily_variance': 0.1,
        },
        'residential_medium': {
            'base_load': 0.4,
            'peak_multiplier': 1.8,
            'daily_variance': 0.15,
        },
        'residential_high': {
            'base_load': 0.8,
            'peak_multiplier': 2.5,
            'daily_variance': 0.2,
        },
        'commercial': {
            'base_load': 2.0,
            'peak_multiplier': 3.5,
            'daily_variance': 0.25,
        },
    }
    
    cfg = config.get(user_type, config['residential_medium'])
    
    dates = []
    times = []
    power_data = []
    anomaly_flags = []
    
    start_date = datetime.now() - timedelta(days=days)
    
    for day in range(days):
        current_date = start_date + timedelta(days=day)
        
        # More volatile weekday vs weekend patterns
        if current_date.weekday() < 5:  # Weekday
            day_intensity = 1.1
        else:  # Weekend
            day_intensity = 0.8
        
        for interval in range(96):
            hour = interval // 4
            minute = (interval % 4) * 15
            
            dates.append(current_date.strftime('%d-%m-%Y'))
            times.append(f"{hour:02d}:{minute:02d}")
            
            # Time-based consumption
            if 0 <= hour < 6:
                hourly_pattern = 0.5
            elif 6 <= hour < 8:
                hourly_pattern = 1.3
            elif 8 <= hour < 12:
                hourly_pattern = 1.8 if user_type == 'commercial' else 1.0
            elif 12 <= hour < 14:
                hourly_pattern = 1.5
            elif 14 <= hour < 18:
                hourly_pattern = 1.2
            elif 18 <= hour < 22:
                hourly_pattern = 2.0
            else:
                hourly_pattern = 0.6
            
            power = cfg['base_load'] * hourly_pattern * day_intensity * cfg['peak_multiplier']
            power += np.random.normal(0, cfg['daily_variance'])
            power = max(0.05, power)
            
            # Anomalies (3%)
            is_anomaly = 0
            if random.random() < 0.03:
                is_anomaly = 1
                power *= random.choice([random.uniform(0.05, 0.2), random.uniform(2.0, 3.5)])
            
            power_data.append(round(power, 3))
            anomaly_flags.append(is_anomaly)
    
    df = pd.DataFrame({
        'Date': dates,
        'Time': times,
        'Power': power_data,
        'Anomaly': anomaly_flags,
    })
    
    df.to_csv(output_file, index=False)
    
    print(f"✅ {user_type} dataset generated!")
    print(f"📊 Total records: {len(df)}")
    print(f"💡 Average power: {df['Power'].mean():.3f} kW")
    print(f"⚠️  Anomalies: {df['Anomaly'].sum()} ({df['Anomaly'].mean()*100:.1f}%)")
    print(f"💾 Saved to: {output_file}\n")
    
    return df


if __name__ == '__main__':
    # Generate main training dataset (1 year of data)
    df_main = generate_energy_dataset(
        days=365,
        output_file='synthetic_training_data.csv'
    )
    
    print("\n" + "="*60 + "\n")
    
    # Generate user-specific datasets for different consumption patterns
    df_low = generate_user_specific_dataset(
        user_type='residential_low',
        days=90,
        output_file='user_training_low.csv'
    )
    
    df_medium = generate_user_specific_dataset(
        user_type='residential_medium',
        days=90,
        output_file='user_training_medium.csv'
    )
    
    df_high = generate_user_specific_dataset(
        user_type='residential_high',
        days=90,
        output_file='user_training_high.csv'
    )
    
    df_commercial = generate_user_specific_dataset(
        user_type='commercial',
        days=90,
        output_file='user_training_commercial.csv'
    )
    
    print("\n" + "="*60)
    print("✅ All datasets generated successfully!")
    print("="*60)
