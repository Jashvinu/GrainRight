# Kalsubai Farms Information Architecture

This document defines the structural taxonomy, routing configurations, and interactive user flows of the Kalsubai Farms platform.

---

## 1. Application Navigation Flow (Shell Routing)

The platform is designed around a 5-tab persistent Bottom Navigation bar with GoRouter nested shell routes.

```mermaid
graph TD
    Root[App Startup / GoRouter Root] -->|Session Exists| Shell[Persistent Shell Scaffold]
    Root -->|No Session| Auth[Auth Flow]
    
    Shell --> Tab1[Home Tab / Home Route]
    Shell --> Tab2[Farm Tab / Diagnosis Route]
    Shell --> Tab3[Market Tab / Marketplace Route]
    Shell --> Tab4[AI Tab / Krishi Mitra Chat Route]
    Shell --> Tab5[Profile Tab / Profile Route]
    
    Tab1 --> HomeDetails[Quick Stats, Daily Tasks, Weather Summary]
    Tab2 --> DiagDetails[Image Scan, Disease Results, Remediation Guide]
    Tab3 --> MarketDetails[Categories, Search/Filter, Product Details, Orders]
    Tab4 --> AIDetails[Krishi Mitra Chat Interface, Dynamic Recommendations]
    Tab5 --> ProfileDetails[Farmer Stats, Achievements/Badges, App Settings]
```

---

## 2. Authentication Flow

Supports OTP-based logins for farmers and email/social login for consumers via Supabase.

```mermaid
sequenceDiagram
    autonumber
    actor User as Farmer / Consumer
    participant UI as Login Screen
    participant Auth as Auth Controller
    participant SB as Supabase Auth DB
    
    User->>UI: Enter Phone Number / Credentials
    UI->>Auth: Request OTP / Submit login
    Auth->>SB: Send OTP / Verify Auth
    SB-->>Auth: OTP Sent / Validation result
    Auth-->>UI: Show OTP Verification Field
    User->>UI: Enter OTP Code
    UI->>Auth: Verify Code
    Auth->>SB: Verify Session
    SB-->>Auth: Session Tokens & User Profile Role
    Auth->>UI: Route to Home Screen based on Role
```

---

## 3. Crop Diagnosis Flow (Krishi Mitra AI)

Provides instant crop disease scanning with organic treatment recommendations.

```mermaid
flowchart TD
    Start[Open Diagnosis Tab] --> SelectSource{Capture or Upload?}
    SelectSource -->|Camera| Camera[Open Camera Capture]
    SelectSource -->|Gallery| Gallery[Open Image Gallery Picker]
    
    Camera --> Preview[Show Leaf Image Preview]
    Gallery --> Preview
    
    Preview --> Confirm[Upload & Analyze Image]
    Confirm --> Loader[Show Loading Mascot "Kalu Thinking"]
    
    Loader --> API[Request CropScan AI Endpoint]
    API --> Results{Disease Detected?}
    
    Results -->|Yes| DiseaseCard[Display Disease Detection Card]
    Results -->|No| HealthyCard[Display Healthy Leaf Confirmation]
    
    DiseaseCard --> Remedy[Load Organic Treatments & Prevention Guide]
    Remedy --> BuyInput[Action: Order Remedy from Marketplace]
    Remedy --> ShareInput[Action: Share to Community Forum]
```

---

## 4. Marketplace Flow

A clean direct-sales agriculture e-commerce flow.

```mermaid
flowchart LR
    Browse[Browse Marketplace] --> Filter[Filter by Category / Millet / Vegetable]
    Filter --> Search[Search Grains / Seeds]
    Search --> ProdCard[Click Product Card]
    ProdCard --> ProdDetails[View Product & Farmer Details]
    ProdDetails --> Cart[Add to Cart]
    Cart --> Checkout[Submit Order / Payment Method]
    Checkout --> Status[Confirm Order: Show "Kalu Success"]
```

---

## 5. Community Forum Flow

Combines social features with collaborative agricultural advice.

```mermaid
flowchart TD
    Feed[Open Community Feed] --> PostList[List Posts by Topic]
    PostList --> Details[Read Comments & Like]
    PostList --> Create[Write New Post / Ask Question]
    Create --> Upload[Attach Crop Scan / Farm Image]
    Upload --> Submit[Submit Post to Supabase DB]
    Submit --> Refresh[Auto-Refresh Community Feed]
```

---

## 6. Weather Forecast & Recommendation Flow

Hyperlocal meteorological support tailored for mountain elevations.

```mermaid
flowchart TD
    WHome[Open Weather Page] --> Current[View Current Temperature & Wind]
    Current --> Hourly[Hourly Precipitation Timeline]
    Hourly --> Weekly[7-Day Sahyadri Weather Trend]
    Weekly --> Advisory[Load Agri-Advisory Recommendations]
    Advisory --> Action{Alert Triggered?}
    Action -->|Yes: Frost/Rain warning| PushNotify[Send Alert Notification to Farmer]
    Action -->|No| NormalTask[Add standard crop watering task to Daily List]
```
