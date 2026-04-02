package api_test

import (
	"bytes"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"testing"

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
