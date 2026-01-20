# ML System Architecture & Data Flow

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     WATTBUDDY APP (Flutter)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────┐      ┌──────────────────────────┐    │
│  │   Dashboard Screen   │      │   AI Insights Screen      │    │
│  ├──────────────────────┤      ├──────────────────────────┤    │
│  │ • Display usage      │      │ • Show anomalies         │    │
│  │ • Show alerts        │      │ • Energy patterns        │    │
│  │ • Call ML service    │──→   │ • Suggestions            │    │
│  │ • Navigate to        │      │ • Priority levels        │    │
│  │   insights           │      │ • Savings potential      │    │
│  └──────────────────────┘      └──────────────────────────┘    │
│           │                              │                       │
│           │        ┌──────────────────────┘                      │
│           │        │                                              │
│           └────────┼──────────────────────────┐                 │
│                    ▼                          ▼                  │
│           ┌─────────────────────────────────────────┐            │
│           │     ML Service (ml_service.dart)        │            │
│           ├─────────────────────────────────────────┤            │
│           │ • analyzeEnergy()                       │            │
│           │ • detectAnomalies()                     │            │
│           │ • getInsights()                         │            │
│           └─────────────────────────────────────────┘            │
│                    │                                              │
└────────────────────┼──────────────────────────────────────────────┘
                     │
                     │ HTTP Requests
                     │ (JSON over REST)
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                    BACKEND SERVER (Node.js)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │        ML Routes (/api/ml/*)                             │   │
│  ├──────────────────────────────────────────────────────────┤   │
│  │ POST   /analyze           - Full analysis + suggestions   │   │
│  │ POST   /detect-anomalies  - Quick anomaly detection       │   │
│  │ GET    /insights/:userId  - Retrieve user insights       │   │
│  │ POST   /retrain           - Retrain model                │   │
│  └──────────────────────────────────────────────────────────┘   │
│           │                                                       │
│           ▼                                                       │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │    ML Controller (mlController.js)                       │   │
│  ├──────────────────────────────────────────────────────────┤   │
│  │ • Execute Python ML engine                               │   │
│  │ • Save analysis to database                              │   │
│  │ • Create notifications for anomalies                     │   │
│  │ • Handle request/response                                │   │
│  └──────────────────────────────────────────────────────────┘   │
│           │                                                       │
│           ├──────────────────────────┬─────────────────────┐     │
│           │                          ▼                     ▼     │
│           │              ┌──────────────┐      ┌──────────────┐ │
│           │              │ PostgreSQL   │      │ Python ML    │ │
│           │              │ Database     │      │ Engine       │ │
│           │              └──────────────┘      └──────────────┘ │
│           │                   ▲                        ▲          │
│           │                   │                        │          │
│           └───────────────────┴────────────────────────┘          │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
                     ▲
                     │ Subprocess
                     │ (stdin/stdout)
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ML ENGINE (Python)                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  EnergyMLEngine Class                                            │
│  ├─ load_or_train_model()                                        │
│  │  ├─ Load cached models (joblib)                              │
│  │  └─ Train on historical data if needed                       │
│  │                                                               │
│  ├─ detect_anomalies(power_data)                                │
│  │  ├─ Isolation Forest prediction                              │
│  │  ├─ Anomaly scoring                                          │
│  │  └─ Severity calculation                                     │
│  │                                                               │
│  ├─ get_usage_pattern(historical_data)                          │
│  │  ├─ Average usage                                            │
│  │  ├─ Peak usage                                               │
│  │  ├─ Standard deviation                                       │
│  │  └─ Variance                                                 │
│  │                                                               │
│  └─ generate_suggestions(usage, pattern, anomaly)               │
│     ├─ High usage alerts                                        │
│     ├─ Anomaly warnings                                         │
│     ├─ Peak hour tips                                           │
│     └─ Optimization recommendations                             │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Flow Diagram

### Complete Request/Response Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. USER INITIATES REQUEST                                       │
└─────────────────────────────────────────────────────────────────┘
                    │
                    │ User opens AI Insights screen
                    │ or Dashboard calls analyzeEnergy()
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. FLUTTER SERVICE PREPARES DATA                                │
│    (ml_service.dart)                                            │
└─────────────────────────────────────────────────────────────────┘
    Input:
    ┌────────────────────────┐
    │ userId: "user123"      │
    │ powerData: [1.5, 2.3]  │
    │ historicalData: [...]  │
    └────────────────────────┘
                    │
                    │ HTTP POST with JSON
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. BACKEND RECEIVES REQUEST                                     │
│    (mlController.js)                                            │
└─────────────────────────────────────────────────────────────────┘
    ├─ Validate input
    ├─ Prepare Python subprocess
    └─ Pass data via stdin
                    │
                    │ JSON via stdin
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. PYTHON ML ENGINE PROCESSES                                   │
│    (ml_engine.py)                                               │
└─────────────────────────────────────────────────────────────────┘
    ├─ Create EnergyMLEngine instance
    ├─ Load or train model
    │   └─ Check for cached models
    │   └─ If not cached, train on CSV data
    │   └─ Save to disk
    │
    ├─ Detect anomalies
    │   ├─ Convert power data to DataFrame
    │   ├─ Normalize with StandardScaler
    │   ├─ Predict with Isolation Forest
    │   └─ Calculate severity score
    │
    ├─ Analyze patterns
    │   ├─ Calculate average, peak, min
    │   ├─ Calculate std dev & variance
    │   └─ Return pattern statistics
    │
    └─ Generate suggestions
        ├─ Compare current vs average
        ├─ Check anomaly severity
        ├─ Add time-based alerts
        ├─ Calculate savings potential
        └─ Sort by priority
                    │
                    │ JSON via stdout
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. BACKEND PROCESSES RESPONSE                                   │
│    (mlController.js)                                            │
└─────────────────────────────────────────────────────────────────┘
    ├─ Parse Python JSON output
    ├─ Save to database
    │   └─ INSERT INTO energy_analysis
    │   └─ INSERT INTO notifications (if anomaly)
    │
    └─ Return to client
                    │
                    │ HTTP 200 with JSON
                    ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. FLUTTER RECEIVES & DISPLAYS                                  │
│    (ai_insights_screen.dart)                                    │
└─────────────────────────────────────────────────────────────────┘
    Output Display:
    ┌─────────────────────────────────────────┐
    │ Anomaly Status                          │
    │ ├─ Is Anomaly: true/false               │
    │ └─ Severity: 0-100%                     │
    │                                         │
    │ Usage Patterns                          │
    │ ├─ Average: 1.65 kW                     │
    │ ├─ Peak: 2.8 kW                         │
    │ ├─ Min: 1.2 kW                          │
    │ └─ Variability: 0.45σ                   │
    │                                         │
    │ Suggestions                             │
    │ ├─ [CRITICAL] Anomaly detected          │
    │ ├─ [HIGH] High usage alert              │
    │ └─ [MEDIUM] Peak hours optimization     │
    └─────────────────────────────────────────┘
                    │
                    │ Display to user
                    ▼
        ┌─────────────────┐
        │  USER SEES UI   │
        │  with insights  │
        └─────────────────┘
```

---

## Database Schema

```
users (existing)
├─ id (PK)
├─ username
├─ email
├─ consumer_number
├─ password
└─ created_at

energy_analysis (NEW)
├─ id (PK)
├─ user_id (FK → users.id)
├─ anomaly_data (JSONB)
│  ├─ anomalies: [0, 1, 0, ...]
│  ├─ is_anomaly: true/false
│  └─ severity: 0-100
├─ suggestions (JSONB)
│  └─ Array of suggestion objects
└─ created_at

notifications (NEW)
├─ id (PK)
├─ user_id (FK → users.id)
├─ type: "anomaly_alert"
├─ title
├─ message
├─ severity: "critical", "high", "medium"
├─ data (JSONB)
├─ is_read: boolean
└─ created_at

energy_readings (NEW)
├─ id (PK)
├─ user_id (FK → users.id)
├─ power_consumption: float
├─ recorded_at: timestamp
└─ created_at

anomaly_alerts (NEW)
├─ id (PK)
├─ user_id (FK → users.id)
├─ anomaly_data (JSONB)
├─ power_data (JSONB)
└─ created_at

Indexes:
├─ idx_anomaly_user_created: anomaly_alerts(user_id, created_at DESC)
├─ idx_energy_analysis_user: energy_analysis(user_id, created_at DESC)
└─ idx_notifications_user: notifications(user_id, created_at DESC)
```

---

## Model Training & Prediction Flow

### First Run (Model Training)

```
User Request
    ▼
Check for existing model
    ├─ Found? → Load from disk
    │          └─ Use for prediction
    │
    └─ Not found? → Train new model
                    ├─ Load kerala_energy_1year.csv
                    ├─ Extract features (7 columns)
                    ├─ Normalize with StandardScaler
                    ├─ Train Isolation Forest (150 trees)
                    ├─ Save model to models/user_{id}/anomaly_model.pkl
                    ├─ Save scaler to models/user_{id}/scaler.pkl
                    └─ Use for prediction
```

### Subsequent Runs (Model Reuse)

```
User Request
    ▼
Load cached model & scaler
    ▼
Use for prediction (FAST - milliseconds)
    ▼
Return results
```

---

## Anomaly Detection Algorithm

```
Input: power_data = [1.5, 2.3, 1.8, 2.1]

Step 1: Data Preparation
├─ Convert to DataFrame
└─ Create feature columns
    ├─ Global_active_power: [1.5, 2.3, 1.8, 2.1]
    ├─ Global_intensity: [0.75, 1.15, 0.9, 1.05]
    ├─ Voltage: [230, 230, 230, 230]
    └─ ... sub_metering fields

Step 2: Normalization
├─ StandardScaler.fit_transform()
├─ Mean = 0, Std = 1 for each feature
└─ Output: X_scaled (normalized)

Step 3: Anomaly Detection
├─ model.predict(X_scaled)
│  ├─ Return: -1 (anomaly), 1 (normal)
│  └─ Output: [1, -1, 1, 1]
│
└─ model.score_samples(X_scaled)
   ├─ Return: anomaly scores
   └─ Output: [-0.5, -1.2, -0.3, -0.4]

Step 4: Severity Calculation
├─ Extract anomaly scores
├─ Normalize to 0-100%
├─ Higher score = more anomalous
└─ Output: severity = 78%

Step 5: Return Results
└─ {
     "anomalies": [0, 1, 0, 0],
     "scores": [-0.5, -1.2, -0.3, -0.4],
     "severity": 78,
     "is_anomaly": true
   }
```

---

## Suggestion Generation Logic

```
Input: current_usage, pattern, anomaly_data

┌─ Check 1: High Usage?
│  └─ if current > average + (2 × std_dev)
│     └─ Add "High Usage Detected" suggestion (HIGH priority)
│
├─ Check 2: Anomalies Detected?
│  └─ if is_anomaly == true
│     └─ Add anomaly warning (severity-based priority)
│
├─ Check 3: Peak Hours?
│  └─ if current_hour >= 18 && current_hour <= 22
│     └─ Add "Peak Hours Alert" (MEDIUM priority)
│
└─ Check 4: High Baseline Usage?
   └─ if average_usage > 2 kW
      └─ Add "Optimize High Consumption" (MEDIUM priority)

Final: Sort by priority and return
```

---

## Performance Metrics

```
Operation               Time        Note
─────────────────────────────────────────────
Model Load (cached)     ~50ms       Fast
Model Train (first)     ~5-10s      One-time cost
Anomaly Detection       ~200ms      Quick
Pattern Analysis        ~100ms      Fast
Suggestion Gen          ~150ms      Fast
Total API Response      ~500ms      Normal
─────────────────────────────────────────────
```

---

## Error Handling Flow

```
Request Received
    ▼
Validate Input
    ├─ Empty/invalid? → Return 400 Bad Request
    └─ Valid? → Continue
    
Execute ML Engine
    ├─ Timeout? → Return timeout error
    ├─ Python error? → Return error details
    └─ Success? → Continue

Parse Result
    ├─ Invalid JSON? → Return parse error
    └─ Valid? → Continue

Database Operations
    ├─ Failed? → Log error (non-blocking)
    └─ Success? → Return response

Client Response
    ├─ Success → 200 OK with data
    └─ Error → 500 Internal Server Error with message
```

---

This architecture provides:
- ✅ Scalability: Per-user model caching
- ✅ Performance: Minimal API latency
- ✅ Reliability: Error handling throughout
- ✅ Maintainability: Clean separation of concerns
- ✅ Extensibility: Easy to add new features
