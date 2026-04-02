package push

import "testing"

func TestTruncToken_Short(t *testing.T) {
	got := truncToken("abc")
	if got != "abc" {
		t.Fatalf("expected 'abc', got %s", got)
	}
}

func TestTruncToken_Empty(t *testing.T) {
	got := truncToken("")
	if got != "" {
		t.Fatalf("expected empty string, got %s", got)
	}
}

func TestTruncToken_Exact16(t *testing.T) {
	input := "1234567890abcdef"
	got := truncToken(input)
	if got != input {
		t.Fatalf("expected %s, got %s", input, got)
	}
}

func TestTruncToken_Long(t *testing.T) {
	input := "1234567890abcdef1234567890abcdef"
	got := truncToken(input)
	if got != "1234567890abcdef" {
		t.Fatalf("expected first 16 chars, got %s", got)
	}
}

func TestTruncToken_Exactly17(t *testing.T) {
	input := "1234567890abcdefg"
	got := truncToken(input)
	if got != "1234567890abcdef" {
		t.Fatalf("expected first 16 chars, got %s", got)
	}
}

func TestTruncToken_Exactly15(t *testing.T) {
	input := "1234567890abcde"
	got := truncToken(input)
	if got != input {
		t.Fatalf("expected %s, got %s", input, got)
	}
}

func TestBuildPayloadInternal_AllBranches(t *testing.T) {
	tests := []struct {
		name       string
		sender     string
		fileType   string
		fileID     string
		wantTitle  string
		wantBody   string
		wantFileID string
	}{
		{"image/jpeg", "Alice", "image/jpeg", "f1", "Alice", "sent you a photo", "f1"},
		{"image/png", "Bob", "image/png", "f2", "Bob", "sent you a photo", "f2"},
		{"image/heic", "Carol", "image/heic", "f3", "Carol", "sent you a photo", "f3"},
		{"video/mp4", "Dana", "video/mp4", "f4", "Dana", "sent you a video", "f4"},
		{"video/quicktime", "Eve", "video/quicktime", "f5", "Eve", "sent you a video", "f5"},
		{"text/plain", "Frank", "text/plain", "f6", "Frank", "sent you a message", "f6"},
		{"text/html", "Grace", "text/html", "f7", "Grace", "sent you a message", "f7"},
		{"application/pdf", "Hank", "application/pdf", "f8", "Hank", "sent you a file", "f8"},
		{"audio/mpeg", "Ivy", "audio/mpeg", "f9", "Ivy", "sent you a file", "f9"},
		{"empty", "Jack", "", "f10", "Jack", "sent you a file", "f10"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			p := BuildPayload(tt.sender, tt.fileType, tt.fileID)
			if p.AlertTitle != tt.wantTitle {
				t.Errorf("AlertTitle = %q, want %q", p.AlertTitle, tt.wantTitle)
			}
			if p.AlertBody != tt.wantBody {
				t.Errorf("AlertBody = %q, want %q", p.AlertBody, tt.wantBody)
			}
			if p.FileID != tt.wantFileID {
				t.Errorf("FileID = %q, want %q", p.FileID, tt.wantFileID)
			}
		})
	}
}
