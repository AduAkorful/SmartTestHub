from fastapi import FastAPI, File, UploadFile
import os
import shutil

app = FastAPI()

UPLOAD_DIR = "/app/input"
os.makedirs(UPLOAD_DIR, exist_ok=True)

@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    file_location = os.path.join(UPLOAD_DIR, file.filename)
    with open(file_location, "wb") as f:
        shutil.copyfileobj(file.file, f)
    return {"filename": file.filename, "status": "success"}
