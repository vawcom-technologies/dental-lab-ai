from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import (
    create_access_token,
    get_current_user,
    hash_password,
    verify_password,
)
from app.models import User, ActivityLog
from app.schemas import (
    PasswordChange,
    TokenOut,
    UserOut,
    UserRegister,
    UserUpdate,
)

router = APIRouter()


def _token_for(user: User) -> TokenOut:
    token = create_access_token(subject=user.email, role=user.role)
    return TokenOut(
        access_token=token,
        user_id=user.id,
        role=user.role,
        name=user.name,
        email=user.email,
        clinic_name=user.clinic_name,
        phone=user.phone,
    )


@router.post("/register", response_model=TokenOut, status_code=status.HTTP_201_CREATED)
def register(payload: UserRegister, db: Session = Depends(get_db)):
    email = payload.email.lower().strip()
    if db.query(User).filter(User.email == email).first():
        raise HTTPException(status_code=400, detail="Email already registered")
    user = User(
        email=email,
        name=payload.name.strip(),
        role=payload.role,
        password_hash=hash_password(payload.password),
        clinic_name=(payload.clinic_name or "").strip() or None,
        phone=(payload.phone or "").strip() or None,
    )
    db.add(user)
    db.flush()
    db.add(
        ActivityLog(
            user_id=user.id,
            action="register",
            target_type="user",
            target_id=user.id,
        )
    )
    db.commit()
    db.refresh(user)
    return _token_for(user)


@router.post("/login", response_model=TokenOut)
def login(
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(User.email == form_data.username.lower().strip()).first()
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
    db.refresh(user)
    return _token_for(user)


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)):
    return user


@router.patch("/me", response_model=UserOut)
def update_me(
    payload: UserUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    data = payload.model_dump(exclude_unset=True)
    if "email" in data and data["email"] is not None:
        new_email = str(data["email"]).lower().strip()
        if new_email != user.email:
            exists = (
                db.query(User)
                .filter(User.email == new_email, User.id != user.id)
                .first()
            )
            if exists:
                raise HTTPException(status_code=400, detail="Email already in use")
            data["email"] = new_email
    if "name" in data and data["name"] is not None:
        data["name"] = data["name"].strip()
    if "clinic_name" in data and data["clinic_name"] is not None:
        data["clinic_name"] = data["clinic_name"].strip() or None
    if "phone" in data and data["phone"] is not None:
        data["phone"] = data["phone"].strip() or None

    for key, value in data.items():
        setattr(user, key, value)

    db.add(
        ActivityLog(
            user_id=user.id,
            action="profile.update",
            target_type="user",
            target_id=user.id,
        )
    )
    db.commit()
    db.refresh(user)
    return user


@router.post("/me/password")
def change_password(
    payload: PasswordChange,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not verify_password(payload.current_password, user.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    if payload.current_password == payload.new_password:
        raise HTTPException(
            status_code=400,
            detail="New password must be different from the current password",
        )
    user.password_hash = hash_password(payload.new_password)
    db.add(
        ActivityLog(
            user_id=user.id,
            action="password.change",
            target_type="user",
            target_id=user.id,
        )
    )
    db.commit()
    return {"ok": True, "note": "Password updated"}
