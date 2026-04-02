package push

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/mondominator/beamlet/server/internal/model"
	"github.com/mondominator/beamlet/server/internal/store"
	"golang.org/x/oauth2/google"
)

// FCMNotifier sends push notifications via the FCM HTTP v1 API.
type FCMNotifier struct {
	projectID string
	client    *http.Client
	userStore *store.UserStore

	mu          sync.Mutex
	accessToken string
	tokenExpiry time.Time
	credJSON    []byte
}

func NewFCMNotifier(serviceAccountPath string, userStore *store.UserStore) (*FCMNotifier, error) {
	credJSON, err := os.ReadFile(serviceAccountPath)
	if err != nil {
		return nil, fmt.Errorf("read FCM service account: %w", err)
	}

	var sa struct {
		ProjectID string `json:"project_id"`
	}
	if err := json.Unmarshal(credJSON, &sa); err != nil {
		return nil, fmt.Errorf("parse FCM service account: %w", err)
	}
	if sa.ProjectID == "" {
		return nil, fmt.Errorf("FCM service account missing project_id")
	}

	log.Printf("FCM configured (v1 API, project: %s)", sa.ProjectID)
	return &FCMNotifier{
		projectID: sa.ProjectID,
		client:    &http.Client{Timeout: 10 * time.Second},
		userStore: userStore,
		credJSON:  credJSON,
	}, nil
}

type fcmV1Request struct {
	Message fcmV1Message `json:"message"`
}

type fcmV1Message struct {
	Token        string            `json:"token"`
	Notification *fcmNotification  `json:"notification,omitempty"`
	Data         map[string]string `json:"data,omitempty"`
	Android      *fcmAndroid       `json:"android,omitempty"`
}

type fcmNotification struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

type fcmAndroid struct {
	Priority     string           `json:"priority,omitempty"`
	Notification *fcmAndroidNotif `json:"notification,omitempty"`
}

type fcmAndroidNotif struct {
	Sound     string `json:"sound,omitempty"`
	ChannelID string `json:"channel_id,omitempty"`
}

func (f *FCMNotifier) getAccessToken() (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()

	if f.accessToken != "" && time.Now().Before(f.tokenExpiry) {
		return f.accessToken, nil
	}

	creds, err := google.CredentialsFromJSON(context.Background(), f.credJSON, "https://www.googleapis.com/auth/firebase.messaging")
	if err != nil {
		return "", fmt.Errorf("create credentials: %w", err)
	}

	token, err := creds.TokenSource.Token()
	if err != nil {
		return "", fmt.Errorf("get access token: %w", err)
	}

	f.accessToken = token.AccessToken
	f.tokenExpiry = token.Expiry.Add(-60 * time.Second)
	return f.accessToken, nil
}

func (f *FCMNotifier) Send(device model.Device, pl Payload) error {
	token, err := f.getAccessToken()
	if err != nil {
		return fmt.Errorf("FCM auth: %w", err)
	}

	reqBody := fcmV1Request{
		Message: fcmV1Message{
			Token: device.APNsToken,
			Notification: &fcmNotification{
				Title: pl.AlertTitle,
				Body:  pl.AlertBody,
			},
			Data: map[string]string{
				"file_id":      pl.FileID,
				"sender_name":  pl.AlertTitle,
				"content_type": pl.AlertBody,
			},
			Android: &fcmAndroid{
				Priority: "high",
				Notification: &fcmAndroidNotif{
					Sound:     "default",
					ChannelID: "beamlet_inbox",
				},
			},
		},
	}

	body, err := json.Marshal(reqBody)
	if err != nil {
		return fmt.Errorf("marshal FCM request: %w", err)
	}

	endpoint := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", f.projectID)
	req, err := http.NewRequest("POST", endpoint, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create FCM request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := f.client.Do(req)
	if err != nil {
		return fmt.Errorf("FCM request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)

	if resp.StatusCode != http.StatusOK {
		var errResp struct {
			Error struct {
				Code   int    `json:"code"`
				Status string `json:"status"`
			} `json:"error"`
		}
		if json.Unmarshal(respBody, &errResp) == nil {
			if errResp.Error.Code == 404 || errResp.Error.Status == "NOT_FOUND" {
				log.Printf("push/fcm: deactivating device %s: token not registered", truncToken(device.APNsToken))
				f.userStore.DeactivateDevice(device.APNsToken)
			}
		}
		return fmt.Errorf("FCM returned status %d: %s", resp.StatusCode, string(respBody))
	}

	log.Printf("push/fcm: sent to device %s", truncToken(device.APNsToken))
	return nil
}
