import json
import pandas as pd
import numpy as np
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import KMeans
import joblib
import os
from datetime import datetime, timedelta
import sys

class EnergyMLEngine:
    """
    Adaptive ML engine for energy anomaly detection and pattern learning
    """
    
    def __init__(self, user_id):
        self.user_id = user_id
        self.model_dir = f"models/user_{user_id}"
        self.ensure_model_dir()
        
        self.anomaly_model = None
        self.scaler = None
        self.pattern_model = None
        self.feature_names = [
            'Global_active_power',
            'Global_intensity', 
            'Voltage',
            'Sub_metering_1',
            'Sub_metering_2',
            'Sub_metering_3',
            'Sub_metering_4'
        ]
    
    def ensure_model_dir(self):
        """Create model directory if not exists"""
        if not os.path.exists(self.model_dir):
            os.makedirs(self.model_dir, exist_ok=True)
    
    def load_or_train_model(self, training_data=None):
        """Load pre-trained model or train from data"""
        model_path = os.path.join(self.model_dir, 'anomaly_model.pkl')
        scaler_path = os.path.join(self.model_dir, 'scaler.pkl')
        
        # Try to load existing model
        if os.path.exists(model_path) and os.path.exists(scaler_path):
            self.anomaly_model = joblib.load(model_path)
            self.scaler = joblib.load(scaler_path)
            return True
        
        # Train new model if data provided
        if training_data is not None:
            return self._train_model(training_data)
        
        # Fallback: use default model
        return self._train_default_model()
    
    def _train_default_model(self):
        """Train model on default historical data"""
        try:
            df = pd.read_csv("kerala_energy_1year.csv")
            return self._train_model(df)
        except Exception as e:
            print(f"Error training default model: {e}", file=sys.stderr)
            return False
    
    def _train_model(self, df):
        """Train Isolation Forest model on data"""
        try:
            X = df[self.feature_names].fillna(0)
            
            # Normalize data
            self.scaler = StandardScaler()
            X_scaled = self.scaler.fit_transform(X)
            
            # Train anomaly detector
            self.anomaly_model = IsolationForest(
                n_estimators=150,
                contamination=0.05,
                random_state=42,
                max_samples='auto',
                n_jobs=-1
            )
            self.anomaly_model.fit(X_scaled)
            
            # Save model
            model_path = os.path.join(self.model_dir, 'anomaly_model.pkl')
            scaler_path = os.path.join(self.model_dir, 'scaler.pkl')
            joblib.dump(self.anomaly_model, model_path)
            joblib.dump(self.scaler, scaler_path)
            
            return True
        except Exception as e:
            print(f"Error training model: {e}", file=sys.stderr)
            return False
    
    def detect_anomalies(self, power_data):
        """
        Detect anomalies in power consumption data
        Returns: {anomalies, scores, severity}
        """
        if not self.anomaly_model or not self.scaler:
            self.load_or_train_model()
        
        try:
            # Convert to DataFrame
            if isinstance(power_data, list):
                df = pd.DataFrame({
                    'Global_active_power': power_data,
                    'Global_intensity': [x * 0.5 for x in power_data],
                    'Voltage': [230] * len(power_data),
                    'Sub_metering_1': [x * 0.3 for x in power_data],
                    'Sub_metering_2': [x * 0.3 for x in power_data],
                    'Sub_metering_3': [x * 0.2 for x in power_data],
                    'Sub_metering_4': [x * 0.2 for x in power_data],
                })
            else:
                df = pd.DataFrame(power_data)
            
            # Normalize
            X_scaled = self.scaler.transform(df.fillna(0))
            
            # Predict
            predictions = self.anomaly_model.predict(X_scaled)
            scores = self.anomaly_model.score_samples(X_scaled)
            
            # Convert predictions (-1 = anomaly, 1 = normal)
            anomalies = [1 if x == -1 else 0 for x in predictions]
            
            # Calculate severity (0-100)
            severity = self._calculate_severity(scores, anomalies)
            
            return {
                'anomalies': anomalies,
                'scores': scores.tolist(),
                'severity': severity,
                'is_anomaly': any(a == 1 for a in anomalies),
            }
        except Exception as e:
            print(f"Error detecting anomalies: {e}", file=sys.stderr)
            return {'error': str(e)}
    
    def _calculate_severity(self, scores, anomalies):
        """Calculate severity of anomalies (0-100)"""
        try:
            anomaly_indices = [i for i, a in enumerate(anomalies) if a == 1]
            if not anomaly_indices:
                return 0
            
            anomaly_scores = [scores[i] for i in anomaly_indices]
            # Normalize scores to 0-100
            min_score = np.min(scores)
            max_score = np.max(scores)
            
            if max_score == min_score:
                return 50
            
            normalized = [(s - min_score) / (max_score - min_score) * 100 
                         for s in anomaly_scores]
            return int(np.mean(normalized))
        except:
            return 50
    
    def get_usage_pattern(self, historical_data):
        """
        Identify usage patterns (peak hours, baseline, etc.)
        Returns pattern statistics
        """
        try:
            df = pd.DataFrame(historical_data)
            
            if df.empty:
                return {}
            
            return {
                'average_usage': float(df['Global_active_power'].mean()) if 'Global_active_power' in df else 0,
                'peak_usage': float(df['Global_active_power'].max()) if 'Global_active_power' in df else 0,
                'min_usage': float(df['Global_active_power'].min()) if 'Global_active_power' in df else 0,
                'std_dev': float(df['Global_active_power'].std()) if 'Global_active_power' in df else 0,
                'variance': float(df['Global_active_power'].var()) if 'Global_active_power' in df else 0,
            }
        except Exception as e:
            print(f"Error calculating pattern: {e}", file=sys.stderr)
            return {}
    
    def generate_suggestions(self, current_usage, pattern, anomaly_data):
        """
        Generate personalized energy-saving suggestions
        Returns: list of suggestions with priority
        """
        suggestions = []
        
        try:
            avg_usage = pattern.get('average_usage', 0)
            peak_usage = pattern.get('peak_usage', 0)
            std_dev = pattern.get('std_dev', 0)
            
            # Check if current usage is unusually high
            if current_usage > avg_usage + (2 * std_dev):
                suggestions.append({
                    'title': 'High Usage Detected',
                    'message': f'Your current usage ({current_usage:.1f} kW) is significantly higher than usual ({avg_usage:.1f} kW)',
                    'action': 'Check for devices running unexpectedly',
                    'priority': 'high',
                    'savings_potential': int((current_usage - avg_usage) * 10),
                })
            
            # Check for anomalies
            if anomaly_data.get('is_anomaly'):
                severity = anomaly_data.get('severity', 0)
                suggestions.append({
                    'title': 'Anomaly in Usage Pattern',
                    'message': f'Unusual energy consumption detected (severity: {severity}%)',
                    'action': 'Review appliances and check for malfunctions',
                    'priority': 'critical' if severity > 75 else 'high',
                    'savings_potential': int(severity * 0.5),
                })
            
            # Time-based suggestions
            current_hour = datetime.now().hour
            if current_hour >= 18 and current_hour <= 22:  # Peak hours
                suggestions.append({
                    'title': 'Peak Hours Alert',
                    'message': 'You\'re currently in peak electricity pricing hours',
                    'action': 'Shift non-essential loads to off-peak hours',
                    'priority': 'medium',
                    'savings_potential': 15,
                })
            
            # Comparative analysis
            if avg_usage > 2:  # kW
                suggestions.append({
                    'title': 'Optimize High Consumption',
                    'message': f'Your average usage ({avg_usage:.1f} kW) is high',
                    'action': 'Consider LED lights, efficient appliances, or adjusting thermostat',
                    'priority': 'medium',
                    'savings_potential': 25,
                })
            
            # Sort by priority
            priority_order = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3}
            suggestions.sort(key=lambda x: priority_order.get(x['priority'], 4))
            
            return suggestions
        except Exception as e:
            print(f"Error generating suggestions: {e}", file=sys.stderr)
            return []


def process_request(request_data):
    """Main entry point for ML engine"""
    user_id = request_data.get('user_id', 'default')
    action = request_data.get('action', 'detect')
    
    engine = EnergyMLEngine(user_id)
    
    if action == 'detect':
        power_data = request_data.get('power_data', [])
        engine.load_or_train_model()
        return engine.detect_anomalies(power_data)
    
    elif action == 'analyze':
        power_data = request_data.get('power_data', [])
        historical_data = request_data.get('historical_data', [])
        
        engine.load_or_train_model()
        anomaly_data = engine.detect_anomalies(power_data)
        pattern = engine.get_usage_pattern(historical_data)
        suggestions = engine.generate_suggestions(
            current_usage=power_data[0] if power_data else 0,
            pattern=pattern,
            anomaly_data=anomaly_data
        )
        
        return {
            'anomalies': anomaly_data,
            'pattern': pattern,
            'suggestions': suggestions,
        }
    
    elif action == 'train':
        # Retrain model with new data
        training_data = request_data.get('training_data', [])
        if training_data:
            engine._train_model(pd.DataFrame(training_data))
            return {'success': True, 'message': 'Model retrained'}
        return {'error': 'No training data provided'}
    
    return {'error': 'Unknown action'}


if __name__ == '__main__':
    # Read input from stdin
    input_data = sys.stdin.read()
    request = json.loads(input_data)
    
    result = process_request(request)
    print(json.dumps(result, default=str))
