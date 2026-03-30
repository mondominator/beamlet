package push_test

import (
	"testing"

	"github.com/mondominator/beamlet/server/internal/push"
)

func TestBuildPayload_Image(t *testing.T) {
	payload := push.BuildPayload("Alice", "image/jpeg", "abc-123")
	if payload.AlertTitle != "Alice" {
		t.Fatalf("expected title Alice, got %s", payload.AlertTitle)
	}
	if payload.AlertBody != "sent you a photo" {
		t.Fatalf("expected 'sent you a photo', got %s", payload.AlertBody)
	}
	if payload.FileID != "abc-123" {
		t.Fatalf("expected file ID abc-123, got %s", payload.FileID)
	}
}

func TestBuildPayload_Video(t *testing.T) {
	payload := push.BuildPayload("Bob", "video/mp4", "def-456")
	if payload.AlertBody != "sent you a video" {
		t.Fatalf("expected 'sent you a video', got %s", payload.AlertBody)
	}
}

func TestBuildPayload_Text(t *testing.T) {
	payload := push.BuildPayload("Charlie", "text/plain", "ghi-789")
	if payload.AlertBody != "sent you a message" {
		t.Fatalf("expected 'sent you a message', got %s", payload.AlertBody)
	}
}

func TestBuildPayload_Generic(t *testing.T) {
	payload := push.BuildPayload("Dana", "application/pdf", "jkl-012")
	if payload.AlertBody != "sent you a file" {
		t.Fatalf("expected 'sent you a file', got %s", payload.AlertBody)
	}
}
