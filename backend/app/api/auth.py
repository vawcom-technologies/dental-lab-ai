from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import (
    create_access_token,
    get_current_user,
    verify_password,
)
from app.models import User, ActivityLog
from app.schemas import TokenOut, UserOut

router = APIRouter()


@router.post("/login", response_model=TokenOut)
def login(
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(User.email == form_data.username).first()
    if not user or not verify_password(form_data.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
        )
    user.last_login = datetime.utcnow()
    db.add(
        ActivityLog(
            user_id=user.id,
            action="login",
            target_type="user",
            target_id=user.id,
        )
    )
    db.commit()
    token = create_access_token(subject=user.email, role=user.role)
    return TokenOut(
        access_token=token,
        role=user.role,
        name=user.name,
        email=user.email,
    )


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)):
    return user
