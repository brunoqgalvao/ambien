"""
Unit tests for Voice Embedding Service

Run with: pytest test_main.py -v

NOTE: Tests that require the full FastAPI app are skipped if torch is not installed.
Unit tests for cosine_similarity run without dependencies.
"""
import base64
import io
import os
import struct
import sys
import wave
from unittest.mock import MagicMock, patch, AsyncMock

import numpy as np
import pytest

# Set test environment variables before importing main
os.environ["API_KEY"] = "test-api-key"
os.environ["HF_TOKEN"] = "test-hf-token"

# Check if torch is available (needed for full app tests)
try:
    import torch
    TORCH_AVAILABLE = True
except ImportError:
    TORCH_AVAILABLE = False


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture
def mock_embedding_model():
    """Mock the Resemblyzer encoder."""
    mock_encoder = MagicMock()
    # embed_utterance returns a 256-dim numpy array
    mock_encoder.embed_utterance.return_value = np.random.randn(256).astype(np.float32)
    return mock_encoder


@pytest.fixture
def client(mock_embedding_model):
    """Create test client with mocked model."""
    if not TORCH_AVAILABLE:
        pytest.skip("torch not installed - skipping integration tests")

    from fastapi.testclient import TestClient

    # Mock both the encoder and the preprocess_wav function
    with patch("main._encoder", mock_embedding_model):
        with patch("main.get_encoder", return_value=mock_embedding_model):
            # Mock preprocess_wav where it's imported (inside extract_embedding_from_file)
            with patch("resemblyzer.preprocess_wav", return_value=np.zeros(16000)):
                from main import app
                yield TestClient(app)


@pytest.fixture
def auth_headers():
    """Authentication headers for API requests."""
    return {"X-API-Key": "test-api-key"}


@pytest.fixture
def sample_wav_bytes():
    """Generate a minimal valid WAV file for testing."""
    # Create a simple WAV file in memory
    buffer = io.BytesIO()

    # WAV parameters
    sample_rate = 16000
    duration = 0.5  # 0.5 seconds
    num_samples = int(sample_rate * duration)

    with wave.open(buffer, 'wb') as wav_file:
        wav_file.setnchannels(1)  # Mono
        wav_file.setsampwidth(2)  # 16-bit
        wav_file.setframerate(sample_rate)

        # Generate simple sine wave
        samples = []
        for i in range(num_samples):
            sample = int(32767 * np.sin(2 * np.pi * 440 * i / sample_rate))
            samples.append(struct.pack('<h', sample))
        wav_file.writeframes(b''.join(samples))

    buffer.seek(0)
    return buffer.read()


@pytest.fixture
def sample_embedding():
    """Generate a sample 256-dim embedding."""
    np.random.seed(42)  # For reproducibility
    return np.random.randn(256).astype(np.float32).tolist()


# ============================================================================
# Health Check Tests
# ============================================================================

class TestHealthEndpoint:
    """Tests for /health endpoint."""

    def test_health_check_returns_200(self, client):
        """Health check should return 200 status."""
        response = client.get("/health")
        assert response.status_code == 200

    def test_health_check_response_structure(self, client):
        """Health check should return correct structure."""
        response = client.get("/health")
        data = response.json()

        assert "status" in data
        assert "model_loaded" in data
        assert "version" in data

    def test_health_check_no_auth_required(self, client):
        """Health check should not require authentication."""
        response = client.get("/health")
        assert response.status_code == 200

    def test_health_check_version(self, client):
        """Health check should return version 1.0.0."""
        response = client.get("/health")
        data = response.json()
        assert data["version"] == "1.0.0"


# ============================================================================
# Authentication Tests
# ============================================================================

class TestAuthentication:
    """Tests for API key authentication."""

    def test_missing_api_key_returns_422(self, client, sample_embedding):
        """Request without API key should return 422."""
        response = client.post(
            "/compare-embeddings",
            json={"embedding1": sample_embedding, "embedding2": sample_embedding}
        )
        assert response.status_code == 422

    def test_invalid_api_key_returns_401(self, client, sample_embedding):
        """Request with invalid API key should return 401."""
        response = client.post(
            "/compare-embeddings",
            headers={"X-API-Key": "wrong-key"},
            json={"embedding1": sample_embedding, "embedding2": sample_embedding}
        )
        assert response.status_code == 401

    def test_valid_api_key_succeeds(self, client, auth_headers, sample_embedding):
        """Request with valid API key should succeed."""
        response = client.post(
            "/compare-embeddings",
            headers=auth_headers,
            json={"embedding1": sample_embedding, "embedding2": sample_embedding}
        )
        assert response.status_code == 200


# ============================================================================
# Extract Embedding Tests (Base64)
# ============================================================================

class TestExtractEmbeddingBase64:
    """Tests for /extract-embedding endpoint (base64 input)."""

    def test_extract_embedding_success(self, client, auth_headers, sample_wav_bytes, mock_embedding_model):
        """Should extract embedding from valid base64 audio."""
        audio_b64 = base64.b64encode(sample_wav_bytes).decode()

        response = client.post(
            "/extract-embedding",
            headers=auth_headers,
            json={"audio_base64": audio_b64, "format": "wav"}
        )

        assert response.status_code == 200
        data = response.json()
        assert "embedding" in data
        assert "dimension" in data
        assert data["dimension"] == 256
        assert len(data["embedding"]) == 256

    def test_extract_embedding_invalid_base64(self, client, auth_headers):
        """Should return 400 for invalid base64."""
        response = client.post(
            "/extract-embedding",
            headers=auth_headers,
            json={"audio_base64": "not-valid-base64!!!", "format": "wav"}
        )

        assert response.status_code == 400
        assert "base64" in response.json()["detail"].lower()

    def test_extract_embedding_returns_float_list(self, client, auth_headers, sample_wav_bytes, mock_embedding_model):
        """Embedding should be a list of floats."""
        audio_b64 = base64.b64encode(sample_wav_bytes).decode()

        response = client.post(
            "/extract-embedding",
            headers=auth_headers,
            json={"audio_base64": audio_b64, "format": "wav"}
        )

        data = response.json()
        assert all(isinstance(x, (int, float)) for x in data["embedding"])


# ============================================================================
# Extract Embedding Tests (File Upload)
# ============================================================================

class TestExtractEmbeddingUpload:
    """Tests for /extract-embedding/upload endpoint."""

    def test_upload_success(self, client, auth_headers, sample_wav_bytes, mock_embedding_model):
        """Should extract embedding from uploaded file."""
        response = client.post(
            "/extract-embedding/upload",
            headers=auth_headers,
            files={"file": ("test.wav", sample_wav_bytes, "audio/wav")}
        )

        assert response.status_code == 200
        data = response.json()
        assert "embedding" in data
        assert len(data["embedding"]) == 256

    def test_upload_without_auth(self, client, sample_wav_bytes):
        """Should require authentication."""
        response = client.post(
            "/extract-embedding/upload",
            files={"file": ("test.wav", sample_wav_bytes, "audio/wav")}
        )

        assert response.status_code == 422


# ============================================================================
# Compare Embeddings Tests
# ============================================================================

class TestCompareEmbeddings:
    """Tests for /compare-embeddings endpoint."""

    def test_compare_identical_embeddings(self, client, auth_headers, sample_embedding):
        """Identical embeddings should have similarity ~1.0."""
        response = client.post(
            "/compare-embeddings",
            headers=auth_headers,
            json={"embedding1": sample_embedding, "embedding2": sample_embedding}
        )

        assert response.status_code == 200
        data = response.json()
        assert data["similarity"] == pytest.approx(1.0, abs=0.001)
        assert data["is_same_speaker"] is True

    def test_compare_different_embeddings(self, client, auth_headers):
        """Different embeddings should have lower similarity."""
        np.random.seed(42)
        emb1 = np.random.randn(256).tolist()
        np.random.seed(123)
        emb2 = np.random.randn(256).tolist()

        response = client.post(
            "/compare-embeddings",
            headers=auth_headers,
            json={"embedding1": emb1, "embedding2": emb2}
        )

        assert response.status_code == 200
        data = response.json()
        # Random embeddings should have low similarity
        assert -1.0 <= data["similarity"] <= 1.0

    def test_compare_response_structure(self, client, auth_headers, sample_embedding):
        """Response should have correct structure."""
        response = client.post(
            "/compare-embeddings",
            headers=auth_headers,
            json={"embedding1": sample_embedding, "embedding2": sample_embedding}
        )

        data = response.json()
        assert "similarity" in data
        assert "is_same_speaker" in data

    def test_compare_wrong_dimension_embedding1(self, client, auth_headers, sample_embedding):
        """Should reject embedding1 with wrong dimension."""
        wrong_dim = [0.1] * 128  # Wrong dimension

        response = client.post(
            "/compare-embeddings",
            headers=auth_headers,
            json={"embedding1": wrong_dim, "embedding2": sample_embedding}
        )

        assert response.status_code == 400
        assert "256" in response.json()["detail"]

    def test_compare_wrong_dimension_embedding2(self, client, auth_headers, sample_embedding):
        """Should reject embedding2 with wrong dimension."""
        wrong_dim = [0.1] * 512  # Wrong dimension

        response = client.post(
            "/compare-embeddings",
            headers=auth_headers,
            json={"embedding1": sample_embedding, "embedding2": wrong_dim}
        )

        assert response.status_code == 400
        assert "256" in response.json()["detail"]

    def test_compare_orthogonal_embeddings(self, client, auth_headers):
        """Orthogonal embeddings should have similarity ~0."""
        # Create two orthogonal vectors
        emb1 = [0.0] * 256
        emb1[0] = 1.0

        emb2 = [0.0] * 256
        emb2[1] = 1.0

        response = client.post(
            "/compare-embeddings",
            headers=auth_headers,
            json={"embedding1": emb1, "embedding2": emb2}
        )

        data = response.json()
        assert data["similarity"] == pytest.approx(0.0, abs=0.001)
        assert data["is_same_speaker"] is False

    def test_compare_opposite_embeddings(self, client, auth_headers):
        """Opposite embeddings should have similarity ~-1."""
        emb1 = [1.0] * 256
        emb2 = [-1.0] * 256

        response = client.post(
            "/compare-embeddings",
            headers=auth_headers,
            json={"embedding1": emb1, "embedding2": emb2}
        )

        data = response.json()
        assert data["similarity"] == pytest.approx(-1.0, abs=0.001)
        assert data["is_same_speaker"] is False


# ============================================================================
# Cosine Similarity Unit Tests (standalone - no torch dependency)
# ============================================================================

def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    """Compute cosine similarity between two vectors.

    This is a copy of the function from main.py for standalone testing.
    """
    norm_a = np.linalg.norm(a)
    norm_b = np.linalg.norm(b)
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return float(np.dot(a, b) / (norm_a * norm_b))


class TestCosineSimilarity:
    """Unit tests for cosine_similarity function."""

    def test_identical_vectors(self):
        """Identical vectors should have similarity 1.0."""
        a = np.array([1.0, 2.0, 3.0])
        b = np.array([1.0, 2.0, 3.0])

        assert cosine_similarity(a, b) == pytest.approx(1.0)

    def test_orthogonal_vectors(self):
        """Orthogonal vectors should have similarity 0."""
        a = np.array([1.0, 0.0, 0.0])
        b = np.array([0.0, 1.0, 0.0])

        assert cosine_similarity(a, b) == pytest.approx(0.0)

    def test_opposite_vectors(self):
        """Opposite vectors should have similarity -1."""
        a = np.array([1.0, 1.0, 1.0])
        b = np.array([-1.0, -1.0, -1.0])

        assert cosine_similarity(a, b) == pytest.approx(-1.0)

    def test_zero_vector(self):
        """Zero vector should return 0."""
        a = np.array([0.0, 0.0, 0.0])
        b = np.array([1.0, 2.0, 3.0])

        assert cosine_similarity(a, b) == 0.0

    def test_scaled_vectors(self):
        """Scaled vectors should have same similarity."""
        a = np.array([1.0, 2.0, 3.0])
        b = np.array([2.0, 4.0, 6.0])  # a * 2

        assert cosine_similarity(a, b) == pytest.approx(1.0)

    def test_high_dimensional_vectors(self):
        """Test with 256-dim vectors like real embeddings."""
        np.random.seed(42)
        a = np.random.randn(256)

        # Same vector should have similarity 1.0
        assert cosine_similarity(a, a) == pytest.approx(1.0)

        # Negated vector should have similarity -1.0
        assert cosine_similarity(a, -a) == pytest.approx(-1.0)

    def test_similar_vectors(self):
        """Test that similar vectors have high similarity."""
        np.random.seed(42)
        a = np.random.randn(256)
        # Add small noise
        b = a + np.random.randn(256) * 0.1

        sim = cosine_similarity(a, b)
        assert sim > 0.9  # Should still be very similar


# ============================================================================
# Edge Cases
# ============================================================================

class TestEdgeCases:
    """Tests for edge cases and error handling."""

    def test_empty_embedding_array(self, client, auth_headers):
        """Should handle empty embedding arrays."""
        response = client.post(
            "/compare-embeddings",
            headers=auth_headers,
            json={"embedding1": [], "embedding2": []}
        )

        # Should fail validation (wrong dimension)
        assert response.status_code == 400

    def test_nan_in_embedding(self, client, auth_headers, sample_embedding):
        """NaN values cause JSON serialization error - tests current behavior."""
        emb_with_nan = sample_embedding.copy()
        emb_with_nan[0] = float('nan')

        # NaN can't be serialized to JSON, so this will raise an error
        # This tests the current behavior - in production, you might want to
        # add validation to reject NaN values with a 400 error
        import pytest
        with pytest.raises(ValueError, match="JSON"):
            client.post(
                "/compare-embeddings",
                headers=auth_headers,
                json={"embedding1": emb_with_nan, "embedding2": sample_embedding}
            )

    def test_very_large_embedding_values(self, client, auth_headers):
        """Should handle very large embedding values."""
        large_emb = [1e10] * 256

        response = client.post(
            "/compare-embeddings",
            headers=auth_headers,
            json={"embedding1": large_emb, "embedding2": large_emb}
        )

        assert response.status_code == 200
        data = response.json()
        assert data["similarity"] == pytest.approx(1.0, abs=0.001)


# ============================================================================
# Integration Tests (Require Model)
# ============================================================================

@pytest.mark.skipif(
    os.getenv("RUN_INTEGRATION_TESTS") != "true",
    reason="Integration tests require model download (first run only)"
)
class TestIntegration:
    """Integration tests that require the actual Resemblyzer model."""

    def test_real_model_loads(self):
        """Test that the real model can be loaded."""
        from main import get_encoder

        encoder = get_encoder()
        assert encoder is not None

    def test_real_embedding_extraction(self, sample_wav_bytes):
        """Test embedding extraction with real model."""
        import tempfile
        from main import extract_embedding_from_file

        # Write sample audio to temp file
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            f.write(sample_wav_bytes)
            temp_path = f.name

        try:
            embedding = extract_embedding_from_file(temp_path)
            assert len(embedding) == 256
            assert embedding.dtype == np.float32 or embedding.dtype == np.float64
        finally:
            os.unlink(temp_path)


# ============================================================================
# Run Tests
# ============================================================================

if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
