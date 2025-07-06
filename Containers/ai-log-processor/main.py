from fastapi import FastAPI, Request
import uvicorn

app = FastAPI()

@app.post("/process-logs")
async def process_logs(request: Request):
    data = await request.json()
    logs = data.get("logs", "")
    # Your AI logic can go here; for now, echoing with an AI header.
    processed = f"## AI Processed Logs\n\n{logs}\n\n[AI insights go here]"
    return {"logs": processed}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=5000)
