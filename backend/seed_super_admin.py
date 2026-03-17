import argparse
import os

import firebase_admin
from firebase_admin import auth, credentials, firestore


def init_firebase(service_account_path: str | None) -> firestore.Client:
    if firebase_admin._apps:
        return firestore.client()

    if service_account_path:
        cred = credentials.Certificate(service_account_path)
        firebase_admin.initialize_app(cred)
    else:
        firebase_admin.initialize_app()

    return firestore.client()


def ensure_super_admin(db: firestore.Client, email: str, password: str, full_name: str) -> str:
    try:
        user = auth.get_user_by_email(email)
    except auth.UserNotFoundError:
        user = auth.create_user(
            email=email,
            password=password,
            display_name=full_name,
            email_verified=True,
        )

    db.collection('users').document(user.uid).set(
        {
            'userId': user.uid,
            'fullName': full_name,
            'email': email,
            'role': 'super_admin',
            'userType': 'admin',
            'status': 'approved',
            'accountStatus': 'active',
            'isApproved': True,
            'isActive': True,
            'updatedAt': firestore.SERVER_TIMESTAMP,
            'createdAt': firestore.SERVER_TIMESTAMP,
        },
        merge=True,
    )

    return user.uid


def main() -> None:
    parser = argparse.ArgumentParser(description='Seed or recover a super admin account.')
    parser.add_argument('--email', default='dev@system.com')
    parser.add_argument('--password', required=True)
    parser.add_argument('--full-name', default='System Developer')
    parser.add_argument(
        '--service-account',
        default=os.getenv('GOOGLE_APPLICATION_CREDENTIALS', ''),
        help='Path to Firebase service account JSON. Optional if ADC is configured.',
    )

    args = parser.parse_args()
    email = args.email.strip().lower()
    password = args.password.strip()
    full_name = args.full_name.strip()
    service_account = args.service_account.strip() or None

    if len(password) < 8:
        raise ValueError('Password must be at least 8 characters.')

    db = init_firebase(service_account)
    uid = ensure_super_admin(db, email, password, full_name)
    print(f'Super admin ready: uid={uid}, email={email}')


if __name__ == '__main__':
    main()
