package api_test

import (
	"bytes"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/mondominator/beamlet/server/internal/api"
	"github.com/mondominator/beamlet/server/internal/model"
)

func TestUploadFile(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}
	srv.ContactStore.Add(aliceID, bobID)

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	writer.WriteField("recipient_id", bobID)
	writer.WriteField("message", "check this out")
	part, _ := writer.CreateFormFile("file", "photo.jpg")
	part.Write([]byte("fake image data"))
	writer.Close()

	req := httptest.NewRequest("POST", "/api/files", body)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	var f model.File
	if err := json.NewDecoder(rec.Body).Decode(&f); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if f.Filename != "photo.jpg" {
		t.Fatalf("expected photo.jpg, got %s", f.Filename)
	}
}

func TestUploadText(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}
	srv.ContactStore.Add(aliceID, bobID)

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	writer.WriteField("recipient_id", bobID)
	writer.WriteField("content_type", "text")
	writer.WriteField("text_content", "Hello from Alice!")
	writer.Close()

	req := httptest.NewRequest("POST", "/api/files", body)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestListFiles(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else {
			bobID = u.ID
		}
	}

	srv.FileStore.Create(&model.File{
		SenderID:    bobID,
		RecipientID: aliceID,
		Filename:    "test.jpg",
		FileType:    "image/jpeg",
		ContentType: "file",
	})

	req := httptest.NewRequest("GET", "/api/files?limit=10&offset=0", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var files []model.File
	json.NewDecoder(rec.Body).Decode(&files)
	if len(files) != 1 {
		t.Fatalf("expected 1 file, got %d", len(files))
	}
}

func TestDownloadFile(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	fileContent := []byte("hello file content")
	path, _ := srv.Storage.Save("test.txt", "text/plain", bytes.NewReader(fileContent))

	f, _ := srv.FileStore.Create(&model.File{
		SenderID:    bobID,
		RecipientID: aliceID,
		Filename:    "test.txt",
		FilePath:    path,
		FileType:    "text/plain",
		FileSize:    int64(len(fileContent)),
		ContentType: "file",
	})

	req := httptest.NewRequest("GET", "/api/files/"+f.ID, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if rec.Body.String() != "hello file content" {
		t.Fatalf("unexpected body: %s", rec.Body.String())
	}
}

func TestDeleteFile(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	f, _ := srv.FileStore.Create(&model.File{
		SenderID:    bobID,
		RecipientID: aliceID,
		Filename:    "delete-me.txt",
		FileType:    "text/plain",
		ContentType: "file",
	})

	req := httptest.NewRequest("DELETE", "/api/files/"+f.ID, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestMarkFileRead(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	f, _ := srv.FileStore.Create(&model.File{
		SenderID:    bobID,
		RecipientID: aliceID,
		Filename:    "read-me.txt",
		FileType:    "text/plain",
		ContentType: "file",
	})

	req := httptest.NewRequest("PUT", "/api/files/"+f.ID+"/read", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	got, _ := srv.FileStore.GetByID(f.ID)
	if !got.Read {
		t.Fatal("expected file to be marked read")
	}
}

func TestDownloadFileIDOR(t *testing.T) {
	srv, aliceToken := setupTestServer(t)
	router := api.NewRouter(srv)

	// Create Charlie (a third user)
	_, charlieToken, _ := srv.UserStore.Create("Charlie")

	users, _ := srv.UserStore.List()
	var bobID, charlieID string
	for _, u := range users {
		if u.Name == "Bob" {
			bobID = u.ID
		} else if u.Name == "Charlie" {
			charlieID = u.ID
		}
	}

	// Create a file FROM Charlie TO Bob (Alice is not involved)
	fileContent := []byte("secret data")
	path, _ := srv.Storage.Save("secret.txt", "text/plain", bytes.NewReader(fileContent))
	f, _ := srv.FileStore.Create(&model.File{
		SenderID:    charlieID,
		RecipientID: bobID,
		Filename:    "secret.txt",
		FilePath:    path,
		FileType:    "text/plain",
		FileSize:    int64(len(fileContent)),
		ContentType: "file",
	})

	// Alice tries to download it - should get 404
	req := httptest.NewRequest("GET", "/api/files/"+f.ID, nil)
	req.Header.Set("Authorization", "Bearer "+aliceToken)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for IDOR attempt, got %d", rec.Code)
	}

	// Charlie (the sender) should be able to download it
	req = httptest.NewRequest("GET", "/api/files/"+f.ID, nil)
	req.Header.Set("Authorization", "Bearer "+charlieToken)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for sender download, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestUploadFileNotContact(t *testing.T) {
	srv, aliceToken := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var bobID string
	for _, u := range users {
		if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	// Alice tries to upload to Bob WITHOUT adding them as contacts
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	writer.WriteField("recipient_id", bobID)
	part, _ := writer.CreateFormFile("file", "photo.jpg")
	part.Write([]byte("fake image data"))
	writer.Close()

	req := httptest.NewRequest("POST", "/api/files", body)
	req.Header.Set("Authorization", "Bearer "+aliceToken)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for non-contact upload, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestTogglePin(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	f, _ := srv.FileStore.Create(&model.File{
		SenderID:    bobID,
		RecipientID: aliceID,
		Filename:    "pin-me.txt",
		FileType:    "text/plain",
		ContentType: "file",
	})

	// Toggle pin ON
	req := httptest.NewRequest("PUT", "/api/files/"+f.ID+"/pin", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp map[string]interface{}
	json.NewDecoder(rec.Body).Decode(&resp)
	if resp["pinned"] != true {
		t.Fatalf("expected pinned=true, got %v", resp["pinned"])
	}

	// Toggle pin OFF
	req = httptest.NewRequest("PUT", "/api/files/"+f.ID+"/pin", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	json.NewDecoder(rec.Body).Decode(&resp)
	if resp["pinned"] != false {
		t.Fatalf("expected pinned=false, got %v", resp["pinned"])
	}
}

func TestListSentFiles(t *testing.T) {
	srv, aliceToken := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	// Add as contacts first
	srv.ContactStore.Add(aliceID, bobID)

	// Upload a file from Alice to Bob
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	writer.WriteField("recipient_id", bobID)
	writer.WriteField("content_type", "text")
	writer.WriteField("text_content", "Hello Bob!")
	writer.Close()

	req := httptest.NewRequest("POST", "/api/files", body)
	req.Header.Set("Authorization", "Bearer "+aliceToken)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("upload failed: expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	// Alice calls GET /api/files/sent
	req = httptest.NewRequest("GET", "/api/files/sent?limit=10&offset=0", nil)
	req.Header.Set("Authorization", "Bearer "+aliceToken)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var files []model.File
	json.NewDecoder(rec.Body).Decode(&files)
	if len(files) != 1 {
		t.Fatalf("expected 1 sent file, got %d", len(files))
	}
	if files[0].SenderID != aliceID {
		t.Fatalf("expected sender_id %s, got %s", aliceID, files[0].SenderID)
	}
}

func TestDownloadThumbnail(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	// Save a fake thumbnail file
	thumbContent := []byte("fake thumbnail jpeg data")
	thumbPath, _ := srv.Storage.Save("thumb.jpg", "image/jpeg", bytes.NewReader(thumbContent))

	f, _ := srv.FileStore.Create(&model.File{
		SenderID:      bobID,
		RecipientID:   aliceID,
		Filename:      "photo.jpg",
		FilePath:      thumbPath, // reuse for simplicity
		ThumbnailPath: thumbPath,
		FileType:      "image/jpeg",
		FileSize:      int64(len(thumbContent)),
		ContentType:   "file",
	})

	req := httptest.NewRequest("GET", "/api/files/"+f.ID+"/thumbnail", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	if rec.Header().Get("Content-Type") != "image/jpeg" {
		t.Fatalf("expected Content-Type image/jpeg, got %s", rec.Header().Get("Content-Type"))
	}

	if rec.Body.String() != string(thumbContent) {
		t.Fatalf("unexpected thumbnail body")
	}
}

func TestMarkFileReadIDOR(t *testing.T) {
	srv, _ := setupTestServer(t)
	router := api.NewRouter(srv)

	// Create Charlie
	_, charlieToken, _ := srv.UserStore.Create("Charlie")

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	// Create a file from Bob to Alice (Charlie not involved)
	f, _ := srv.FileStore.Create(&model.File{
		SenderID:    bobID,
		RecipientID: aliceID,
		Filename:    "private.txt",
		FileType:    "text/plain",
		ContentType: "file",
	})

	// Charlie tries to mark it read - should get 404
	req := httptest.NewRequest("PUT", "/api/files/"+f.ID+"/read", nil)
	req.Header.Set("Authorization", "Bearer "+charlieToken)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for IDOR mark-read, got %d", rec.Code)
	}

	// Verify file is still unread
	got, _ := srv.FileStore.GetByID(f.ID)
	if got.Read {
		t.Fatal("file should not be marked read by unauthorized user")
	}
}

func TestDeleteFileIDOR(t *testing.T) {
	srv, _ := setupTestServer(t)
	router := api.NewRouter(srv)

	// Create Charlie
	_, charlieToken, _ := srv.UserStore.Create("Charlie")

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	// Create a file from Bob to Alice (Charlie not involved)
	f, _ := srv.FileStore.Create(&model.File{
		SenderID:    bobID,
		RecipientID: aliceID,
		Filename:    "no-delete.txt",
		FileType:    "text/plain",
		ContentType: "file",
	})

	// Charlie tries to delete it - should get 404
	req := httptest.NewRequest("DELETE", "/api/files/"+f.ID, nil)
	req.Header.Set("Authorization", "Bearer "+charlieToken)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for IDOR delete, got %d", rec.Code)
	}

	// Verify file still exists
	got, err := srv.FileStore.GetByID(f.ID)
	if err != nil || got == nil {
		t.Fatal("file should still exist after unauthorized delete attempt")
	}
}

func TestUploadFileMissingRecipientID(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	// No recipient_id field
	part, _ := writer.CreateFormFile("file", "photo.jpg")
	part.Write([]byte("fake image data"))
	writer.Close()

	req := httptest.NewRequest("POST", "/api/files", body)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for missing recipient_id, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestUploadFileMissingFile(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}
	srv.ContactStore.Add(aliceID, bobID)

	// Send content_type=file (default) but no file attachment
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	writer.WriteField("recipient_id", bobID)
	// No file field, no content_type override
	writer.Close()

	req := httptest.NewRequest("POST", "/api/files", body)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for missing file, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestUploadLinkContentType(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}
	srv.ContactStore.Add(aliceID, bobID)

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	writer.WriteField("recipient_id", bobID)
	writer.WriteField("content_type", "link")
	writer.WriteField("text_content", "https://example.com")
	writer.Close()

	req := httptest.NewRequest("POST", "/api/files", body)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	var f model.File
	json.NewDecoder(rec.Body).Decode(&f)
	if f.ContentType != "link" {
		t.Fatalf("expected content_type 'link', got %s", f.ContentType)
	}
	if f.TextContent != "https://example.com" {
		t.Fatalf("expected text_content, got %s", f.TextContent)
	}
}

func TestUploadFileWithExpiryDays(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}
	srv.ContactStore.Add(aliceID, bobID)

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	writer.WriteField("recipient_id", bobID)
	writer.WriteField("content_type", "text")
	writer.WriteField("text_content", "test expiry")
	writer.WriteField("expiry_days", "7")
	writer.Close()

	req := httptest.NewRequest("POST", "/api/files", body)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	var f model.File
	json.NewDecoder(rec.Body).Decode(&f)
	// Should expire in about 7 days, not 30
	expiryHours := time.Until(f.ExpiresAt).Hours()
	if expiryHours < 6*24 || expiryHours > 8*24 {
		t.Fatalf("expected expiry around 7 days, got %.0f hours", expiryHours)
	}
}

func TestUploadFileWithInvalidExpiryDays(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}
	srv.ContactStore.Add(aliceID, bobID)

	// Test with out-of-range expiry (>365)
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	writer.WriteField("recipient_id", bobID)
	writer.WriteField("content_type", "text")
	writer.WriteField("text_content", "test expiry")
	writer.WriteField("expiry_days", "999")
	writer.Close()

	req := httptest.NewRequest("POST", "/api/files", body)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	var f model.File
	json.NewDecoder(rec.Body).Decode(&f)
	// Should use default 30 days since 999 is out of range
	expiryHours := time.Until(f.ExpiresAt).Hours()
	if expiryHours < 29*24 || expiryHours > 31*24 {
		t.Fatalf("expected default 30 day expiry, got %.0f hours", expiryHours)
	}
}

func TestUploadFileWithExpiryDaysZero(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}
	srv.ContactStore.Add(aliceID, bobID)

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	writer.WriteField("recipient_id", bobID)
	writer.WriteField("content_type", "text")
	writer.WriteField("text_content", "zero expiry")
	writer.WriteField("expiry_days", "0")
	writer.Close()

	req := httptest.NewRequest("POST", "/api/files", body)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestListFilesEmpty(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	req := httptest.NewRequest("GET", "/api/files", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	// Should return [] not null
	body := strings.TrimSpace(rec.Body.String())
	if body != "[]" {
		t.Fatalf("expected empty array [], got %s", body)
	}
}

func TestListSentFilesEmpty(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	req := httptest.NewRequest("GET", "/api/files/sent", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	body := strings.TrimSpace(rec.Body.String())
	if body != "[]" {
		t.Fatalf("expected empty array [], got %s", body)
	}
}

func TestListFilesDefaultLimit(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	// No limit/offset params -- should use defaults
	req := httptest.NewRequest("GET", "/api/files", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestListFilesNegativeOffset(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	req := httptest.NewRequest("GET", "/api/files?limit=10&offset=-5", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestListFilesExcessiveLimit(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	// limit > 100 should be clamped to 20
	req := httptest.NewRequest("GET", "/api/files?limit=500", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestDownloadFileNotFound(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	req := httptest.NewRequest("GET", "/api/files/nonexistent-id", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", rec.Code)
	}
}

func TestDownloadTextFile(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	// Create a text content type file
	f, _ := srv.FileStore.Create(&model.File{
		SenderID:    bobID,
		RecipientID: aliceID,
		Filename:    "text",
		FileType:    "text/plain",
		ContentType: "text",
		TextContent: "Hello, world!",
	})

	req := httptest.NewRequest("GET", "/api/files/"+f.ID, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// Text content type should return JSON, not file download
	if ct := rec.Header().Get("Content-Type"); !strings.Contains(ct, "application/json") {
		t.Fatalf("expected application/json, got %s", ct)
	}
}

func TestDownloadLinkFile(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	f, _ := srv.FileStore.Create(&model.File{
		SenderID:    bobID,
		RecipientID: aliceID,
		Filename:    "link",
		FileType:    "text/plain",
		ContentType: "link",
		TextContent: "https://example.com",
	})

	req := httptest.NewRequest("GET", "/api/files/"+f.ID, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); !strings.Contains(ct, "application/json") {
		t.Fatalf("expected application/json for link, got %s", ct)
	}
}

func TestDownloadThumbnailNotFound(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	req := httptest.NewRequest("GET", "/api/files/nonexistent-id/thumbnail", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", rec.Code)
	}
}

func TestDownloadThumbnailNoThumbnail(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	// File with no thumbnail
	f, _ := srv.FileStore.Create(&model.File{
		SenderID:    bobID,
		RecipientID: aliceID,
		Filename:    "nothumbs.txt",
		FileType:    "text/plain",
		ContentType: "file",
	})

	req := httptest.NewRequest("GET", "/api/files/"+f.ID+"/thumbnail", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for no thumbnail, got %d", rec.Code)
	}
}

func TestDownloadThumbnailIDOR(t *testing.T) {
	srv, _ := setupTestServer(t)
	router := api.NewRouter(srv)

	_, charlieToken, _ := srv.UserStore.Create("Charlie")

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	thumbContent := []byte("thumb data")
	thumbPath, _ := srv.Storage.Save("thumb.jpg", "image/jpeg", bytes.NewReader(thumbContent))

	f, _ := srv.FileStore.Create(&model.File{
		SenderID:      bobID,
		RecipientID:   aliceID,
		Filename:      "private.jpg",
		ThumbnailPath: thumbPath,
		FileType:      "image/jpeg",
		ContentType:   "file",
	})

	// Charlie tries to access Alice's thumbnail
	req := httptest.NewRequest("GET", "/api/files/"+f.ID+"/thumbnail", nil)
	req.Header.Set("Authorization", "Bearer "+charlieToken)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for IDOR thumbnail, got %d", rec.Code)
	}
}

func TestDeleteFileNotFound(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	req := httptest.NewRequest("DELETE", "/api/files/nonexistent-id", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", rec.Code)
	}
}

func TestDeleteFileWithDiskFiles(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	fileContent := []byte("file to delete")
	filePath, _ := srv.Storage.Save("deleteme.txt", "text/plain", bytes.NewReader(fileContent))
	thumbContent := []byte("thumb to delete")
	thumbPath, _ := srv.Storage.Save("deletethumb.jpg", "image/jpeg", bytes.NewReader(thumbContent))

	f, _ := srv.FileStore.Create(&model.File{
		SenderID:      bobID,
		RecipientID:   aliceID,
		Filename:      "deleteme.txt",
		FilePath:      filePath,
		ThumbnailPath: thumbPath,
		FileType:      "text/plain",
		ContentType:   "file",
	})

	req := httptest.NewRequest("DELETE", "/api/files/"+f.ID, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestMarkFileReadNotFound(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	req := httptest.NewRequest("PUT", "/api/files/nonexistent-id/read", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", rec.Code)
	}
}

func TestTogglePinNotFound(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	req := httptest.NewRequest("PUT", "/api/files/nonexistent-id/pin", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", rec.Code)
	}
}

func TestTogglePinIDOR(t *testing.T) {
	srv, _ := setupTestServer(t)
	router := api.NewRouter(srv)

	_, charlieToken, _ := srv.UserStore.Create("Charlie")

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	f, _ := srv.FileStore.Create(&model.File{
		SenderID:    bobID,
		RecipientID: aliceID,
		Filename:    "nopin.txt",
		FileType:    "text/plain",
		ContentType: "file",
	})

	// Charlie tries to toggle pin on Alice's file
	req := httptest.NewRequest("PUT", "/api/files/"+f.ID+"/pin", nil)
	req.Header.Set("Authorization", "Bearer "+charlieToken)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for IDOR pin, got %d", rec.Code)
	}
}

func TestDownloadFileWithMissingDiskFile(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	// Create file record pointing to non-existent disk path
	f, _ := srv.FileStore.Create(&model.File{
		SenderID:    bobID,
		RecipientID: aliceID,
		Filename:    "ghost.txt",
		FilePath:    "/nonexistent/path/ghost.txt",
		FileType:    "text/plain",
		ContentType: "file",
	})

	req := httptest.NewRequest("GET", "/api/files/"+f.ID, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for missing disk file, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestListSentFilesDefaultParams(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	// No limit/offset params
	req := httptest.NewRequest("GET", "/api/files/sent", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestListSentFilesNegativeOffset(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	req := httptest.NewRequest("GET", "/api/files/sent?limit=10&offset=-1", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestListSentFilesExcessiveLimit(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	req := httptest.NewRequest("GET", "/api/files/sent?limit=999", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestUploadFileWithMessage(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}
	srv.ContactStore.Add(aliceID, bobID)

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	writer.WriteField("recipient_id", bobID)
	writer.WriteField("content_type", "text")
	writer.WriteField("text_content", "hello")
	writer.WriteField("message", "check this out!")
	writer.Close()

	req := httptest.NewRequest("POST", "/api/files", body)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	var f model.File
	json.NewDecoder(rec.Body).Decode(&f)
	if f.Message != "check this out!" {
		t.Fatalf("expected message 'check this out!', got %s", f.Message)
	}
}
