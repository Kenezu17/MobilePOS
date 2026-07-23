# BrewPOS Mobile

BrewPOS Mobile is a mobile Point of Sale (POS) application designed for coffee shops and small businesses. It helps employees and business owners manage sales, products, and inventory through a user-friendly mobile interface. The application uses a Spring Boot backend for business logic and Firebase for authentication and cloud data services.

## ✨ Features

- ☕ Mobile Point of Sale (POS)
- 📦 Inventory management
- 🛍️ Product management
- 🛒 Order processing
- 💳 Sales tracking
- 🧾 Digital receipt generation
- 📊 Sales reports
- 🔍 Product search
- 🔐 Secure user authentication
- ☁️ Cloud-based data synchronization

## 🛠️ Tech Stack

### Mobile Application
- Flutter
- Dart
- Provider / Riverpod
- HTTP

### Backend
- Spring Boot
- Java
- Spring Security
- REST API

### Cloud Services
- Firebase Authentication
- Cloud Firestore
- Firebase Storage

## 📁 Project Structure

```
BrewPOS/
├── mobile/
│   ├── lib/
│   ├── assets/
│   ├── android/
│   ├── ios/
│   └── pubspec.yaml
│
├── backend/
│   ├── src/
│   ├── pom.xml
│   └── application.properties
│
└── README.md
```

## 🚀 Getting Started

### Prerequisites

- Flutter SDK
- Android Studio
- Java 17+
- Maven
- Firebase Project

### Backend Setup

```bash
cd backend

mvn spring-boot:run
```

The backend runs at:

```
http://localhost:8080
```

### Mobile Setup

```bash
cd mobile

flutter pub get

flutter run
```

## 🔧 Configuration

Configure the backend API URL in your Flutter project.

```dart
const String baseUrl = "http://YOUR_SERVER_IP:8080/api";
```

Add your Firebase configuration files:

- **Android:** `android/app/google-services.json`
- **iOS:** `ios/Runner/GoogleService-Info.plist`

## 📦 Core Modules

- User Authentication
- Point of Sale
- Product Management
- Inventory Management
- Sales Transactions
- Receipt Management
- Reporting

## ☁️ Firebase Services

- Firebase Authentication for secure user login
- Cloud Firestore for real-time application data
- Firebase Storage for storing product images and receipts

## 🔒 Security

- Firebase Authentication
- JWT-secured REST APIs
- Role-based access control
- Secure communication between the mobile app and backend

## 🚧 Future Improvements

- Barcode scanner integration
- QR code payments
- Offline mode with synchronization
- Push notifications
- Customer loyalty program
- Multi-branch support
- Advanced analytics dashboard

## 📄 License

This project is licensed under the MIT License.

---

Built with ❤️ using Flutter, Spring Boot, and Firebase.
