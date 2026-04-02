package push

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"

	"github.com/mondominator/beamlet/server/internal/model"
	"github.com/mondominator/beamlet/server/internal/store"
)

const fcmEndpoint = "https://fcm.googleapis.com/fcm/send"

// FCMNotifier sends push notifications via the FCM legacy HTTP API.
type FCMNotifier struct {
	serverKey string
	client    *http.Client
	userStore *store.UserStore
}

func NewFCMNotifier(serverKey string, userStore *store.UserStore) *FCMNotifier {
	log.Println("FCM configured (legacy HTTP API)")
	return &FCMNotifier{
		serverKey: serverKey,
		client:    &http.Client{Timeout: 10 * time.Second},
		userStore: userStore,
	}
}

// fcmRequest is the JSON body sent to the FCM legacy HTTP API.
type fcmRequest struct {
	To           string          `json:"to"`
	Notification fcmNotification `json:"notification"`
	Data         fcmData         `json:"data"`
}

type fcmNotification struct {
	Title string `json:"title"`
	Body  string `json:"body"`
	Sound string `json:"sound,omitempty"`
}

type fcmData struct {
	FileID      string `json:"file_id"`
	SenderName  string `json:"sender_name"`
	ContentType string `json:"content_type"`
}

// fcmResponse is the JSON response from the FCM legacy HTTP API.
type fcmResponse struct {
	Success int `json:"success"`
	Failure int `json:"failure"`
	Results []struct {
		MessageID string `json:"message_id,omitempty"`
		Error     string `json:"error,omitempty"`
	} `json:"results"`
}

func (f *FCMNotifier) Send(device model.Device, pl Payload) error {
	reqBody := fcmRequest{
		To: device.APNsToken,
		Notification: fcmNotification{
			Title: pl.AlertTitle,
			Body:  pl.AlertBody,
			Sound: "default",
		},
		Data: fcmData{
			FileID:      pl.FileID,
			SenderName:  pl.AlertTitle,
			ContentType: pl.AlertBody,
		},
	}

	body, err := json.Marshal(reqBody)
	if err != nil {
		return fmt.Errorf("marshal FCM request: %w", err)
	}

	req, err := http.NewRequest("POST", fcmEndpoint, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create FCM request: %w", err)
	}
	req.Header.Set("Authorization", "key="+f.serverKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := f.client.Do(req)
	if err != nil {
		return fmt.Errorf("FCM request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("FCM returned status %d: %s", resp.StatusCode, string(respBody))
	}

	var fcmResp fcmResponse
	if err := json.Unmarshal(respBody, &fcmResp); err != nil {
		return fmt.Errorf("parse FCM response: %w", err)
	}

	log.Printf("push/fcm: device %s success=%d failure=%d",
		truncToken(device.APNsToken), fcmResp.Success, fcmResp.Failure)

	// Handle token invalidation
	if len(fcmResp.Results) > 0 {
		result := fcmResp.Results[0]
		if result.Error == "NotRegistered" || result.Error == "InvalidRegistration" {
			log.Printf("push/fcm: deactivating device %s: %s", truncToken(device.APNsToken), result.Error)
			f.userStore.DeactivateDevice(device.APNsToken)
		}
	}

	return nil
}
