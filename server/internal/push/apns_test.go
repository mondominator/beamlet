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

func TestBuildPayload_ImagePNG(t *testing.T) {
	payload := push.BuildPayload("Eve", "image/png", "file-1")
	if payload.AlertTitle != "Eve" {
		t.Fatalf("expected title Eve, got %s", payload.AlertTitle)
	}
	if payload.AlertBody != "sent you a photo" {
		t.Fatalf("expected 'sent you a photo', got %s", payload.AlertBody)
	}
	if payload.FileID != "file-1" {
		t.Fatalf("expected file ID file-1, got %s", payload.FileID)
	}
}

func TestBuildPayload_ImageGIF(t *testing.T) {
	payload := push.BuildPayload("Frank", "image/gif", "file-2")
	if payload.AlertBody != "sent you a photo" {
		t.Fatalf("expected 'sent you a photo', got %s", payload.AlertBody)
	}
}

func TestBuildPayload_ImageHEIC(t *testing.T) {
	payload := push.BuildPayload("Grace", "image/heic", "file-3")
	if payload.AlertBody != "sent you a photo" {
		t.Fatalf("expected 'sent you a photo', got %s", payload.AlertBody)
	}
}

func TestBuildPayload_VideoMOV(t *testing.T) {
	payload := push.BuildPayload("Hank", "video/quicktime", "file-4")
	if payload.AlertBody != "sent you a video" {
		t.Fatalf("expected 'sent you a video', got %s", payload.AlertBody)
	}
}

func TestBuildPayload_TextHTML(t *testing.T) {
	payload := push.BuildPayload("Ivy", "text/html", "file-5")
	if payload.AlertBody != "sent you a message" {
		t.Fatalf("expected 'sent you a message', got %s", payload.AlertBody)
	}
}

func TestBuildPayload_OctetStream(t *testing.T) {
	payload := push.BuildPayload("Jack", "application/octet-stream", "file-6")
	if payload.AlertBody != "sent you a file" {
		t.Fatalf("expected 'sent you a file', got %s", payload.AlertBody)
	}
}

func TestBuildPayload_AudioMP3(t *testing.T) {
	payload := push.BuildPayload("Kate", "audio/mpeg", "file-7")
	if payload.AlertBody != "sent you a file" {
		t.Fatalf("expected 'sent you a file' for audio, got %s", payload.AlertBody)
	}
}

func TestBuildPayload_EmptyFileType(t *testing.T) {
	payload := push.BuildPayload("Leo", "", "file-8")
	if payload.AlertBody != "sent you a file" {
		t.Fatalf("expected 'sent you a file' for empty type, got %s", payload.AlertBody)
	}
}

func TestBuildPayload_LongSenderName(t *testing.T) {
	longName := "A very long sender name that exceeds normal length"
	payload := push.BuildPayload(longName, "video/mp4", "file-9")
	if payload.AlertTitle != longName {
		t.Fatalf("expected full long name, got %s", payload.AlertTitle)
	}
	if payload.AlertBody != "sent you a video" {
		t.Fatalf("expected 'sent you a video', got %s", payload.AlertBody)
	}
}

func TestBuildPayload_EmptyFields(t *testing.T) {
	payload := push.BuildPayload("", "", "")
	if payload.AlertTitle != "" {
		t.Fatalf("expected empty title, got %s", payload.AlertTitle)
	}
	if payload.AlertBody != "sent you a file" {
		t.Fatalf("expected 'sent you a file', got %s", payload.AlertBody)
	}
	if payload.FileID != "" {
		t.Fatalf("expected empty file ID, got %s", payload.FileID)
	}
}
