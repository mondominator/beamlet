package api

import (
	"encoding/json"
	"io"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/mondominator/beamlet/server/internal/auth"
	"github.com/mondominator/beamlet/server/internal/model"
	"github.com/mondominator/beamlet/server/internal/storage"
)

func (s *Server) UploadFile(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())

	if err := r.ParseMultipartForm(s.Config.MaxFileSize); err != nil {
		http.Error(w, "request too large", http.StatusRequestEntityTooLarge)
		return
	}

	recipientID := r.FormValue("recipient_id")
	if recipientID == "" {
		http.Error(w, "recipient_id is required", http.StatusBadRequest)
		return
	}

	contentType := r.FormValue("content_type")
	if contentType == "" {
		contentType = "file"
	}

	f := &model.File{
		SenderID:    user.ID,
		RecipientID: recipientID,
		ContentType: contentType,
		Message:     r.FormValue("message"),
		ExpiresAt:   time.Now().UTC().Add(time.Duration(s.Config.ExpiryDays) * 24 * time.Hour),
	}

	if contentType == "text" || contentType == "link" {
		f.TextContent = r.FormValue("text_content")
		f.Filename = contentType
		f.FileType = "text/plain"
	} else {
		file, header, err := r.FormFile("file")
		if err != nil {
			http.Error(w, "file is required", http.StatusBadRequest)
			return
		}
		defer file.Close()

		f.Filename = header.Filename
		f.FileType = header.Header.Get("Content-Type")
		if f.FileType == "" {
			f.FileType = "application/octet-stream"
		}
		f.FileSize = header.Size

		path, err := s.Storage.Save(header.Filename, f.FileType, file)
		if err != nil {
			http.Error(w, "failed to save file", http.StatusInternalServerError)
			return
		}
		f.FilePath = path

		thumbPath, err := storage.GenerateThumbnail(path, s.Config.DataDir, f.FileType)
		if err == nil && thumbPath != "" {
			f.ThumbnailPath = thumbPath
		}
	}

	created, err := s.FileStore.Create(f)
	if err != nil {
		http.Error(w, "failed to create file record", http.StatusInternalServerError)
		return
	}

	// Send push notification (non-blocking)
	// Pass sender's device token so we can exclude it from notifications
	// (handles send-to-self case: phone->iPad without notifying the sending phone)
	senderDeviceToken := r.Header.Get("X-Device-Token")
	if s.Pusher != nil {
		go s.Pusher.Notify(recipientID, user.Name, created, senderDeviceToken)
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(created)
}

func (s *Server) ListFiles(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())

	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 || limit > 100 {
		limit = 20
	}

	files, err := s.FileStore.ListForRecipient(user.ID, limit, offset)
	if err != nil {
		http.Error(w, "failed to list files", http.StatusInternalServerError)
		return
	}

	if files == nil {
		files = []model.File{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(files)
}

func (s *Server) ListSentFiles(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())

	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 || limit > 100 {
		limit = 20
	}

	files, err := s.FileStore.ListForSender(user.ID, limit, offset)
	if err != nil {
		http.Error(w, "failed to list sent files", http.StatusInternalServerError)
		return
	}

	if files == nil {
		files = []model.File{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(files)
}

func (s *Server) DownloadFile(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	f, err := s.FileStore.GetByID(id)
	if err != nil {
		http.Error(w, "file not found", http.StatusNotFound)
		return
	}

	if f.ContentType == "text" || f.ContentType == "link" {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(f)
		return
	}

	reader, err := s.Storage.Read(f.FilePath)
	if err != nil {
		http.Error(w, "file not found on disk", http.StatusNotFound)
		return
	}
	defer reader.Close()

	w.Header().Set("Content-Type", f.FileType)
	w.Header().Set("Content-Disposition", "attachment; filename=\""+f.Filename+"\"")
	io.Copy(w, reader)
}

func (s *Server) DownloadThumbnail(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	f, err := s.FileStore.GetByID(id)
	if err != nil {
		http.Error(w, "file not found", http.StatusNotFound)
		return
	}

	if f.ThumbnailPath == "" {
		http.Error(w, "no thumbnail", http.StatusNotFound)
		return
	}

	reader, err := s.Storage.Read(f.ThumbnailPath)
	if err != nil {
		http.Error(w, "thumbnail not found", http.StatusNotFound)
		return
	}
	defer reader.Close()

	w.Header().Set("Content-Type", "image/jpeg")
	io.Copy(w, reader)
}

func (s *Server) DeleteFile(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	f, err := s.FileStore.GetByID(id)
	if err != nil {
		http.Error(w, "file not found", http.StatusNotFound)
		return
	}

	if f.FilePath != "" {
		s.Storage.Delete(f.FilePath)
	}
	if f.ThumbnailPath != "" {
		s.Storage.Delete(f.ThumbnailPath)
	}

	if err := s.FileStore.Delete(id); err != nil {
		http.Error(w, "failed to delete", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "deleted"})
}

func (s *Server) MarkFileRead(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	if err := s.FileStore.MarkRead(id); err != nil {
		http.Error(w, "failed to mark read", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func (s *Server) TogglePin(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	pinned, err := s.FileStore.TogglePin(id)
	if err != nil {
		http.Error(w, "failed to toggle pin", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"pinned": pinned})
}
