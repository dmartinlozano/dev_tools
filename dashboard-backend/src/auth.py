import os
import requests
import json
import secrets
from fastapi import HTTPException, Response, Cookie, Header, Depends
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from src.api import app

class LoginRequest(BaseModel):
    username: str
    password: str

class PasswordChangeRequest(BaseModel):
    current_password: str
    new_password: str

@app.post("/api/auth/login")
async def login(request: LoginRequest, response: Response):
    try:
        realm = "master" if request.username == "admin" else "devtools"
        keycloak_url = "https://keycloak.dev-tools.svc.cluster.local"
        token_url = f"{keycloak_url}/realms/{realm}/protocol/openid-connect/token"

        print(f"Try login with user: {request.username}")
        
        data = {
            "grant_type": "password",
            "client_id": "admin-cli",
            "username": request.username,
            "password": request.password
        }
        
        keycloak_response = requests.post(
            token_url, 
            data=data,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            verify=False  # TODO: remove this in production
        )
        
        if keycloak_response.status_code != 200:
            print(f"Keycloak login failed: {keycloak_response.status_code} - {keycloak_response.text}")
            try:
                error_data = keycloak_response.json()
                if (error_data.get("error") == "invalid_grant" and 
                    error_data.get("error_description") == "Account is not fully set up"):
                    return JSONResponse(
                        content={"error": "redirect-to-change-password"},
                        status_code=401
                    )
            except:
                pass
            
            return JSONResponse(
                content={"error": "Incorrect credentials"},
                status_code=401
            )
        
        token_data = keycloak_response.json()        
        csrf_token = secrets.token_hex(32)
        response.set_cookie(
            key="access_token",
            value=token_data["access_token"],
            httponly=True,
            secure=True,
            samesite="strict",
            max_age=token_data.get("expires_in", 300)  #5 minutes
        )
        
        response.set_cookie(
            key="refresh_token",
            value=token_data["refresh_token"],
            httponly=True,
            secure=True, 
            samesite="strict",
            max_age=token_data.get("refresh_expires_in", 1800)  # 30 minutes
        )
        
        response.set_cookie(
            key="csrf_token",
            value=csrf_token,
            secure=True,
            samesite="strict",
            max_age=token_data.get("expires_in", 300)
        )
        print(f"Keycloak login ok.")
        return {"success": True, "username": request.username, "csrf_token": csrf_token}
        
    except Exception as e:
        error_msg = str(e)
        print(f"Error in login: {error_msg}")
        raise HTTPException(
            status_code=500,
            detail=f"Error: {error_msg}"
        )

# Endpoint to refresh the access token
@app.post("/api/auth/refresh")
async def refresh_token(
    response: Response, 
    refresh_token: str = Cookie(None, alias="refresh_token")
):
    if not refresh_token:
        raise HTTPException(
            status_code=401,
            detail="No refresh token provided"
        )
    
    try:
        keycloak_url = "https://keycloak.dev-tools.svc.cluster.local"
        realms = ["master", "devtools"]
        
        token_data = None
        for realm in realms:
            token_url = f"{keycloak_url}/realms/{realm}/protocol/openid-connect/token"
            
            print(f"Attempting token refresh with URL: {token_url}")
            
            # Prepare the request to refresh the token
            data = {
                "grant_type": "refresh_token",
                "client_id": "admin-cli",
                "refresh_token": refresh_token
            }
            
            keycloak_response = requests.post(
                token_url, 
                data=data,
                headers={"Content-Type": "application/x-www-form-urlencoded"},
                verify=False  # TODO: remove this in production
            )
            
            print(f"Keycloak refresh response status: {keycloak_response.status_code}")
            
            if keycloak_response.status_code == 200:
                token_data = keycloak_response.json()
                break
        
        if not token_data:
            raise HTTPException(
                status_code=401,
                detail="Could not refresh token in any realm"
            )
        
        csrf_token = secrets.token_hex(32)
        response.set_cookie(
            key="access_token",
            value=token_data["access_token"],
            httponly=True,
            secure=True,
            samesite="strict",
            max_age=token_data.get("expires_in", 300)
        )
        if "refresh_token" in token_data:
            response.set_cookie(
                key="refresh_token",
                value=token_data["refresh_token"],
                httponly=True,
                secure=True, 
                samesite="strict",
                max_age=token_data.get("refresh_expires_in", 1800)
            )
        response.set_cookie(
            key="csrf_token",
            value=csrf_token,
            secure=True,
            samesite="strict",
            max_age=token_data.get("expires_in", 300)
        )
        
        return {"success": True, "csrf_token": csrf_token}
        
    except Exception as e:
        error_msg = str(e)
        print(f"Error in token refresh: {error_msg}")
        raise HTTPException(
            status_code=500,
            detail=f"Error refreshing token: {error_msg}"
        )

# Dependency function to verify the CSRF token
def verify_csrf_token(
    csrf_token: str = Header(..., alias="X-CSRF-Token"),
    csrf_cookie: str = Cookie(..., alias="csrf_token")
):
    if csrf_token != csrf_cookie:
        raise HTTPException(status_code=403, detail="Invalid CSRF token")
    return csrf_token

# Example of an endpoint protected by CSRF
@app.post("/api/protected-action")
async def protected_action(csrf_token: str = Depends(verify_csrf_token)):
    # Your logic here
    return {"message": "Protected action executed successfully"}

@app.post("/api/auth/change-password")
async def change_password(
    request: PasswordChangeRequest, 
    response: Response,
    csrf_token: str = Depends(verify_csrf_token),
    access_token: str = Cookie(None, alias="access_token")
):
    if not access_token:
        raise HTTPException(
            status_code=401,
            detail="No access token provided"
        )
    
    try:
        # Extract user information from token
        user_info = get_user_info(access_token)
        username = user_info.get("preferred_username")
        realm = "master" if username == "admin" else "devtools"
        
        # Keycloak URL for password change
        keycloak_url = "https://keycloak.dev-tools.svc.cluster.local"
        
        # First authenticate the user with the current password to verify it
        token_url = f"{keycloak_url}/realms/{realm}/protocol/openid-connect/token"
        auth_data = {
            "grant_type": "password",
            "client_id": "admin-cli",
            "username": username,
            "password": request.current_password
        }
        
        auth_response = requests.post(
            token_url, 
            data=auth_data,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            verify=False
        )
        
        if auth_response.status_code != 200:
            return JSONResponse(
                content={"error": "The current password is incorrect"},
                status_code=401
            )
        
        # If authentication was successful, get the token for admin-cli
        admin_token = auth_response.json().get("access_token")
        
        # Get the user ID
        users_url = f"{keycloak_url}/admin/realms/{realm}/users"
        users_response = requests.get(
            users_url,
            headers={"Authorization": f"Bearer {admin_token}"},
            params={"username": username},
            verify=False
        )
        
        if users_response.status_code != 200:
            raise HTTPException(
                status_code=500,
                detail="Error getting user information"
            )
        
        users = users_response.json()
        if not users:
            raise HTTPException(
                status_code=404,
                detail="User not found"
            )
        
        user_id = users[0]["id"]
        
        # Change the password
        reset_url = f"{keycloak_url}/admin/realms/{realm}/users/{user_id}/reset-password"
        reset_data = {
            "type": "password",
            "value": request.new_password,
            "temporary": False
        }
        
        reset_response = requests.put(
            reset_url,
            headers={
                "Authorization": f"Bearer {admin_token}",
                "Content-Type": "application/json"
            },
            json=reset_data,
            verify=False
        )
        
        if reset_response.status_code not in [200, 204]:
            return JSONResponse(
                content={"error": "Could not change the password. Make sure it meets security requirements."},
                status_code=400
            )
        
        # Remove any pending required actions
        actions_url = f"{keycloak_url}/admin/realms/{realm}/users/{user_id}"
        actions_response = requests.put(
            actions_url,
            headers={
                "Authorization": f"Bearer {admin_token}",
                "Content-Type": "application/json"
            },
            json={"requiredActions": []},
            verify=False
        )
        
        # Generate new tokens for the user
        new_token_data = {
            "grant_type": "password",
            "client_id": "admin-cli",
            "username": username,
            "password": request.new_password
        }
        
        new_token_response = requests.post(
            token_url, 
            data=new_token_data,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            verify=False
        )
        
        if new_token_response.status_code != 200:
            return JSONResponse(
                content={"success": True, "message": "Password changed successfully. Please login again."},
                status_code=200
            )
        
        new_token_data = new_token_response.json()
        
        # Update cookies
        new_csrf_token = secrets.token_hex(32)
        response.set_cookie(
            key="access_token",
            value=new_token_data["access_token"],
            httponly=True,
            secure=True,
            samesite="strict",
            max_age=new_token_data.get("expires_in", 300)
        )
        
        response.set_cookie(
            key="refresh_token",
            value=new_token_data["refresh_token"],
            httponly=True,
            secure=True, 
            samesite="strict",
            max_age=new_token_data.get("refresh_expires_in", 1800)
        )
        
        response.set_cookie(
            key="csrf_token",
            value=new_csrf_token,
            secure=True,
            samesite="strict",
            max_age=new_token_data.get("expires_in", 300)
        )
        
        return {"success": True, "message": "Password changed successfully", "csrf_token": new_csrf_token}
        
    except Exception as e:
        error_msg = str(e)
        print(f"Error in password change: {error_msg}")
        raise HTTPException(
            status_code=500,
            detail=f"Error: {error_msg}"
        )

def get_user_info(token):
    """Extracts basic information from the JWT token"""
    try:
        # In a real implementation, you should use PyJWT to decode the token
        # For simplicity, here we just make a request to Keycloak
        keycloak_url = "https://keycloak.dev-tools.svc.cluster.local"
        userinfo_url = f"{keycloak_url}/realms/master/protocol/openid-connect/userinfo"
        
        response = requests.get(
            userinfo_url,
            headers={"Authorization": f"Bearer {token}"},
            verify=False
        )
        
        if response.status_code != 200:
            # Try with the devtools realm
            userinfo_url = f"{keycloak_url}/realms/devtools/protocol/openid-connect/userinfo"
            response = requests.get(
                userinfo_url,
                headers={"Authorization": f"Bearer {token}"},
                verify=False
            )
            
        if response.status_code != 200:
            return {"preferred_username": "unknown"}
        
        return response.json()
    except Exception as e:
        print(f"Error decoding token: {e}")
        return {"preferred_username": "unknown"}