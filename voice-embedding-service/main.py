"""
Voice Embedding Service - Extract and compare speaker embeddings using Resemblyzer
"""
import os
import io
import base64
import tempfile
from typing import List, Optional
from contextlib import asynccontextmanager

import numpy as np
from fastapi import FastAPI, HTTPException, Depends, Header, UploadFile, File
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

# Global model holder
_encoder = None


def get_encoder():
    """Lazy-load the speaker encoder model."""
    global _encoder
    if _encoder is None:
        from resemblyzer import VoiceEncoder

        # Load the pre-trained encoder (downloads automatically on first use)
        _encoder = VoiceEncoder()
        print("✓ Speaker encoder model loaded successfully")

    return _encoder


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Pre-load model on startup for faster first request."""
    try:
        get_encoder()
    except Exception as e:
        print(f"⚠ Model pre-load failed (will retry on first request): {e}")
    yield


app = FastAPI(
    title="Voice Embedding Service",
    description="Extract and compare speaker voice embeddings using Resemblyzer",
    version="1.0.0",
    lifespan=lifespan
)


# ============================================================================
# Authentication
# ============================================================================

API_KEY = os.getenv("API_KEY", "dev-key-change-me")


async def verify_api_key(x_api_key: str = Header(..., alias="X-API-Key")):
    """Simple API key authentication."""
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")
    return x_api_key


# ============================================================================
# Request/Response Models
# ============================================================================

class EmbeddingRequest(BaseModel):
    """Request body for embedding extraction with base64 audio."""
    audio_base64: str = Field(..., description="Base64-encoded audio file (wav, mp3, m4a, etc.)")
    format: Optional[str] = Field("wav", description="Audio format hint (wav, mp3, m4a)")


class EmbeddingResponse(BaseModel):
    """Response containing the extracted embedding."""
    embedding: List[float] = Field(..., description="256-dimensional speaker embedding vector")
    dimension: int = Field(256, description="Embedding dimension")


class CompareRequest(BaseModel):
    """Request body for comparing two embeddings."""
    embedding1: List[float] = Field(..., description="First 256-dim embedding vector")
    embedding2: List[float] = Field(..., description="Second 256-dim embedding vector")


class CompareResponse(BaseModel):
    """Response containing similarity score."""
    similarity: float = Field(..., description="Cosine similarity score (-1 to 1, higher = more similar)")
    is_same_speaker: bool = Field(..., description="Whether embeddings likely belong to same speaker (similarity > 0.75)")


class HealthResponse(BaseModel):
    """Health check response."""
    status: str
    model_loaded: bool
    version: str


# ============================================================================
# Utility Functions
# ============================================================================

def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    """Compute cosine similarity between two vectors."""
    norm_a = np.linalg.norm(a)
    norm_b = np.linalg.norm(b)
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return float(np.dot(a, b) / (norm_a * norm_b))


def extract_embedding_from_file(file_path: str) -> np.ndarray:
    """Extract speaker embedding from an audio file."""
    from resemblyzer import preprocess_wav

    encoder = get_encoder()

    # Preprocess the audio file (handles resampling to 16kHz)
    wav = preprocess_wav(file_path)

    # Get the embedding (256-dimensional)
    embedding = encoder.embed_utterance(wav)

    return embedding


# ============================================================================
# API Endpoints
# ============================================================================

@app.get("/health", response_model=HealthResponse, tags=["Health"])
async def health_check():
    """Check service health and model status."""
    global _encoder
    return HealthResponse(
        status="healthy",
        model_loaded=_encoder is not None,
        version="1.0.0"
    )


@app.post(
    "/extract-embedding",
    response_model=EmbeddingResponse,
    tags=["Embeddings"],
    dependencies=[Depends(verify_api_key)]
)
async def extract_embedding_base64(request: EmbeddingRequest):
    """
    Extract speaker embedding from base64-encoded audio.

    Accepts WAV audio format. Returns a 256-dimensional embedding vector.
    """
    try:
        # Decode base64 audio
        audio_bytes = base64.b64decode(request.audio_base64)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid base64 encoding: {e}")

    # Determine file extension
    ext = request.format if request.format else "wav"
    if not ext.startswith("."):
        ext = f".{ext}"

    # Write to temp file
    with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as tmp:
        tmp.write(audio_bytes)
        tmp_path = tmp.name

    try:
        embedding = extract_embedding_from_file(tmp_path)
        return EmbeddingResponse(
            embedding=embedding.tolist(),
            dimension=len(embedding)
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Embedding extraction failed: {e}")
    finally:
        # Clean up temp file
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


@app.post(
    "/extract-embedding/upload",
    response_model=EmbeddingResponse,
    tags=["Embeddings"],
    dependencies=[Depends(verify_api_key)]
)
async def extract_embedding_upload(file: UploadFile = File(...)):
    """
    Extract speaker embedding from uploaded audio file.

    Accepts WAV audio format. Returns a 256-dimensional embedding vector.
    """
    # Get file extension
    ext = os.path.splitext(file.filename or "audio.wav")[1] or ".wav"

    # Read file content
    content = await file.read()

    # Write to temp file
    with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as tmp:
        tmp.write(content)
        tmp_path = tmp.name

    try:
        embedding = extract_embedding_from_file(tmp_path)
        return EmbeddingResponse(
            embedding=embedding.tolist(),
            dimension=len(embedding)
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Embedding extraction failed: {e}")
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


@app.post(
    "/compare-embeddings",
    response_model=CompareResponse,
    tags=["Embeddings"],
    dependencies=[Depends(verify_api_key)]
)
async def compare_embeddings(request: CompareRequest):
    """
    Compare two speaker embeddings and return similarity score.

    Uses cosine similarity. Scores above 0.75 typically indicate the same speaker.
    """
    # Validate dimensions
    if len(request.embedding1) != 256:
        raise HTTPException(
            status_code=400,
            detail=f"embedding1 must be 256-dimensional, got {len(request.embedding1)}"
        )
    if len(request.embedding2) != 256:
        raise HTTPException(
            status_code=400,
            detail=f"embedding2 must be 256-dimensional, got {len(request.embedding2)}"
        )

    # Convert to numpy arrays
    emb1 = np.array(request.embedding1, dtype=np.float32)
    emb2 = np.array(request.embedding2, dtype=np.float32)

    # Compute similarity
    similarity = cosine_similarity(emb1, emb2)

    # Threshold for same-speaker detection (tunable)
    SAME_SPEAKER_THRESHOLD = 0.75

    return CompareResponse(
        similarity=similarity,
        is_same_speaker=similarity > SAME_SPEAKER_THRESHOLD
    )


# ============================================================================
# Error Handlers
# ============================================================================

@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Catch-all exception handler."""
    return JSONResponse(
        status_code=500,
        content={"detail": f"Internal server error: {str(exc)}"}
    )


# ============================================================================
# Main Entry Point
# ============================================================================

if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", 8000))
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=port,
        reload=os.getenv("ENV", "production") == "development"
    )
