# LINKod Admin Application

Flutter desktop application for barangay administrators to manage users, announcements, and send targeted push notifications.

## Overview

The LINKod Admin app provides administrators with:
- **User Management**: Create, edit, approve, and manage resident accounts
- **Announcement Management**: Create announcements with AI-assisted text refinement
- **Targeted Notifications**: Send push notifications to specific demographic groups
- **Dashboard**: View statistics and recent activity
- **Audience Recommendation**: Rule-based audience suggestions for announcements

## Features

- ✅ AI-powered text refinement (Ollama LLaMA 3.2 3B)
- ✅ Rule-based audience recommendation
- ✅ Demographic-based push notification targeting
- ✅ User approval workflow
- ✅ Draft announcement management
- ✅ Real-time Firestore synchronization

## Prerequisites

- Flutter SDK 3.9.2 or higher
- Dart SDK 3.9.2 or higher
- Python 3.9+ (for backend)
- Ollama installed and running
- Firebase project configured
- Firebase Admin SDK service account JSON

## Setup

### 1. Install Flutter Dependencies

```bash
cd linkod-admincodebase
flutter pub get
```

### 2. Setup Backend API

```bash
cd backend
pip install -r requirements.txt

# Install and start Ollama
ollama pull llama3.2:3b
ollama serve
```

### 3. Configure Firebase Admin SDK

Place your Firebase service account JSON file in the `backend/` directory and set:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=./backend/serviceAccount.json
```

**Important:** Do not commit the service account JSON to git.

### 4. Run Backend

```bash
cd backend
uvicorn main:app --host 0.0.0.0 --port 8000
```

Or use the provided script:
```bash
cd backend
./run.ps1  # Windows PowerShell
```

### 5. Run Admin App

```bash
flutter run
```

The admin app will connect to the backend API at `http://localhost:8000`.

## Project Structure

```
linkod-admincodebase/
├── lib/
│   ├── main.dart
│   ├── screens/
│   │   ├── dashboard_screen.dart
│   │   ├── user_management_screen.dart
│   │   └── announcements_screen.dart
│   ├── api/
│   │   └── announcement_backend_api.dart
│   └── widgets/
├── backend/
│   ├── main.py                      # FastAPI application
│   ├── services/
│   │   ├── ai_refinement.py        # AI text refinement
│   │   ├── audience_rules.py       # Rule-based recommendations
│   │   └── fcm_notifications.py   # Push notification sending
│   └── config/
│       └── audience_rules.json     # Audience recommendation rules
└── firestore.rules
```

## Backend API Endpoints

### POST /refine
Refines raw announcement text using AI.

### POST /recommend-audiences
Suggests target audiences based on announcement content.

### POST /send-announcement-push
Sends targeted push notifications to matching users.

### POST /send-account-approval
Sends account approval notification to a single user.

See `backend/README.md` for detailed API documentation.

## User Management

### Creating Users
1. Navigate to User Management
2. Click "Add User"
3. Fill in user details
4. Select demographic categories (important for targeting)
5. Save - user document is created with both `category` (string) and `categories` (array)

### Approving Users
1. View pending users in "Awaiting Approval"
2. Review user information
3. Click "Approve"
4. User receives push notification (if FCM token available)

## Announcement Management

### Creating Announcements
1. Navigate to Announcements
2. Enter title and content
3. (Optional) Click "Refine with AI" for text improvement
4. (Optional) Click "Suggest Audiences" for demographic recommendations
5. Select target audiences
6. Choose:
   - **Post only**: Saves to Firestore without sending push
   - **Post and send push**: Saves and sends notifications to matching users

### Push Notification Targeting

Users receive notifications if:
- Role is "resident"
- Account is approved and active
- User's `categories` array matches at least one selected audience
- User has FCM token registered

## Building for Production

### Windows
```bash
flutter build windows --release
```

### macOS
```bash
flutter build macos --release
```

### Linux
```bash
flutter build linux --release
```

## Troubleshooting

### Backend not responding
- Verify Ollama is running: `ollama list`
- Check backend is running on port 8000
- Verify Firebase Admin SDK credentials are set

### "No residents matched" error
- Ensure users have `categories` array set (not just `category` string)
- Check user role is "resident"
- Verify user is approved and active

### AI refinement timeout
- Ensure Ollama is running: `ollama serve`
- Verify model is pulled: `ollama pull llama3.2:3b`
- First request may take 60-90 seconds

## Configuration

### Audience Rules
Edit `backend/config/audience_rules.json` to customize audience recommendation rules.

Example:
```json
{
  "keywords": ["health", "checkup", "medical"],
  "audiences": ["Senior", "PWD", "Parent"]
}
```

## Documentation

- Backend API: See `backend/README.md`
- Complete System Documentation: See `../../LINKOD_SYSTEM_DOCUMENTATION.md`

## License

[Your License Here]
