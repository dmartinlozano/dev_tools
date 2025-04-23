import os
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

# CORS
dashboard_hostname = os.environ.get("DASHBOARD_HOSTNAME", "dashboard.dev-tools.svc.cluster.local")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], #only for development
    #allow_origins=[f"https://{dashboard_hostname}"], #TODO enable this in production
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["*"],
)

@app.get("/api/health")
def health():
    return JSONResponse(content={"status": "ok"}, status_code=200)

import src.auth
