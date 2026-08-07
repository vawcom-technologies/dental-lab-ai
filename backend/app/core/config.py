from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "Dental Lab AI"
    supabase_url: str = ""
    supabase_anon_key: str = ""
    supabase_service_role_key: str = ""
    # Where Supabase sends users after they click the password-reset email link
    password_reset_redirect_url: str = ""

    resend_api_key: str = ""
    resend_from_email: str = "onboarding@resend.dev"
    resend_welcome_to_email: str = "hamza.naxeed@gmail.com"

    # Cloudflare R2 (S3-compatible) for chat media
    r2_account_id: str = ""
    r2_access_key_id: str = ""
    r2_secret_access_key: str = ""
    r2_voice_bucket: str = ""
    r2_voice_public_url: str = ""
    r2_documents_bucket: str = ""
    r2_documents_public_url: str = ""


settings = Settings()
