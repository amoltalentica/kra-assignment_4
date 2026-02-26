"""
Secure API Platform - User Service
FastAPI microservice with JWT authentication and SQLite database
"""
from fastapi import FastAPI, Depends, HTTPException, status, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, EmailStr
from typing import Optional, List
import jwt
import bcrypt
import sqlite3
import os
from datetime import datetime, timedelta
from contextlib import contextmanager
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
SECRET_KEY = os.getenv("JWT_SECRET_KEY", "your-secret-key-change-in-production")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30
DATABASE_PATH = os.getenv("DATABASE_PATH", "/app/data/users.db")
# Kong JWT plugin uses key_claim_name: iss to look up the consumer.
# KONG_JWT_ISS_KEY must equal the 'key' field of the Kong consumer's jwt_secret.
KONG_JWT_ISS_KEY = os.getenv("KONG_JWT_ISS_KEY", "kong-jwt-key")

app = FastAPI(
    title="Secure User Service API",
    description="Production-grade API with JWT authentication",
    version="1.0.0"
)

security = HTTPBearer()

# Pydantic Models
class UserCreate(BaseModel):
    username: str
    email: EmailStr
    password: str

class UserLogin(BaseModel):
    username: str
    password: str

class UserResponse(BaseModel):
    id: int
    username: str
    email: str
    created_at: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"

class VerifyResponse(BaseModel):
    valid: bool
    username: Optional[str] = None
    message: str

# Database Connection Manager
@contextmanager
def get_db_connection():
    """Context manager for database connections"""
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    except Exception as e:
        conn.rollback()
        raise e
    finally:
        conn.close()

def init_database():
    """Initialize SQLite database with users table"""
    os.makedirs(os.path.dirname(DATABASE_PATH), exist_ok=True)
    
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                email TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        
        # Create a default test user if table is empty
        cursor.execute("SELECT COUNT(*) FROM users")
        if cursor.fetchone()[0] == 0:
            test_password = bcrypt.hashpw("testpassword".encode('utf-8'), bcrypt.gensalt())
            cursor.execute(
                "INSERT INTO users (username, email, password_hash) VALUES (?, ?, ?)",
                ("testuser", "test@example.com", test_password.decode('utf-8'))
            )
            logger.info("Created default test user: testuser / testpassword")

# Authentication Functions
def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    """Create JWT access token"""
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    
    to_encode.update({"exp": expire, "iat": datetime.utcnow()})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Verify JWT token and return payload"""
    token = credentials.credentials
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authentication credentials",
                headers={"WWW-Authenticate": "Bearer"},
            )
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except jwt.PyJWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

def authenticate_user(username: str, password: str) -> Optional[dict]:
    """Authenticate user against database"""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT id, username, email, password_hash FROM users WHERE username = ?",
            (username,)
        )
        row = cursor.fetchone()
        
        if not row:
            return None
        
        if bcrypt.checkpw(password.encode('utf-8'), row['password_hash'].encode('utf-8')):
            return {
                "id": row['id'],
                "username": row['username'],
                "email": row['email']
            }
        return None

# API Endpoints

# Public APIs (No Authentication Required)
@app.get("/health", tags=["Public"])
async def health_check():
    """Health check endpoint - no authentication required"""
    return {
        "status": "healthy",
        "service": "user-service",
        "timestamp": datetime.utcnow().isoformat()
    }

@app.get("/verify", response_model=VerifyResponse, tags=["Public"])
async def verify_endpoint(request: Request):
    """Public verify endpoint - no authentication required"""
    # This endpoint can be used by Kong or other services to verify JWT
    # But it's publicly accessible without authentication
    auth_header = request.headers.get("Authorization")
    
    if not auth_header or not auth_header.startswith("Bearer "):
        return VerifyResponse(
            valid=False,
            message="No token provided"
        )
    
    token = auth_header.split(" ")[1]
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return VerifyResponse(
            valid=True,
            username=payload.get("sub"),
            message="Token is valid"
        )
    except jwt.ExpiredSignatureError:
        return VerifyResponse(valid=False, message="Token has expired")
    except jwt.PyJWTError:
        return VerifyResponse(valid=False, message="Invalid token")

# Authentication APIs
@app.post("/login", response_model=TokenResponse, tags=["Authentication"])
async def login(user_login: UserLogin):
    """Authenticate user and return JWT token"""
    user = authenticate_user(user_login.username, user_login.password)
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    access_token = create_access_token(
        data={
            "sub": user["username"],
            "email": user["email"],
            # 'iss' claim is used by Kong JWT plugin (key_claim_name: iss)
            # to identify which consumer's secret to use for verification.
            "iss": KONG_JWT_ISS_KEY,
        },
        expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    
    logger.info(f"User {user['username']} logged in successfully")
    
    return TokenResponse(access_token=access_token)

# Protected APIs (JWT Authentication Required)
@app.get("/users", response_model=List[UserResponse], tags=["Users"])
async def get_users(payload: dict = Depends(verify_token)):
    """Get all users - requires JWT authentication"""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT id, username, email, created_at FROM users")
        rows = cursor.fetchall()
        
        users = [
            UserResponse(
                id=row['id'],
                username=row['username'],
                email=row['email'],
                created_at=row['created_at']
            )
            for row in rows
        ]
        
        return users

@app.post("/users", response_model=UserResponse, tags=["Users"], status_code=status.HTTP_201_CREATED)
async def create_user(user: UserCreate, payload: dict = Depends(verify_token)):
    """Create a new user - requires JWT authentication"""
    password_hash = bcrypt.hashpw(user.password.encode('utf-8'), bcrypt.gensalt())
    
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                "INSERT INTO users (username, email, password_hash) VALUES (?, ?, ?)",
                (user.username, user.email, password_hash.decode('utf-8'))
            )
            user_id = cursor.lastrowid
            
            cursor.execute(
                "SELECT id, username, email, created_at FROM users WHERE id = ?",
                (user_id,)
            )
            row = cursor.fetchone()
            
            return UserResponse(
                id=row['id'],
                username=row['username'],
                email=row['email'],
                created_at=row['created_at']
            )
    except sqlite3.IntegrityError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Username or email already exists"
        )

# Startup event
@app.on_event("startup")
async def startup_event():
    """Initialize database on startup"""
    logger.info("Initializing database...")
    init_database()
    logger.info("Database initialized successfully")
    logger.info(f"API server starting on port 8000")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
